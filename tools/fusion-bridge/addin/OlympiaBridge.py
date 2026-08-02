"""Expose Fusion 360 sur un serveur HTTP local pour le pont MCP.

L'API Fusion n'est appelable que depuis son thread principal. Le serveur HTTP
tourne dans un thread séparé : il ne peut donc pas toucher l'API directement.
Le passage se fait par un événement personnalisé, seul mécanisme que Fusion
offre pour revenir sur le thread principal depuis un thread de travail.

Chaque requête HTTP dépose son travail dans une file, déclenche l'événement,
puis attend que le handler — qui, lui, s'exécute sur le thread principal — ait
posé le résultat.
"""

import adsk.core
import adsk.fusion
import json
import queue
import tempfile
import threading
import traceback
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from io import StringIO

EVENT_ID = "OlympiaBridgeExec"
HOST = "127.0.0.1"
PORT = 8765
CALL_TIMEOUT_S = 30.0

_app = None
_ui = None
_handlers = []
_httpd = None
_server_thread = None
_custom_event = None

_pending = queue.Queue()
_results = {}
_results_lock = threading.Lock()


class _Job:
    def __init__(self, kind, payload):
        self.id = uuid.uuid4().hex
        self.kind = kind
        self.payload = payload
        self.done = threading.Event()


def _submit(kind, payload):
    """Dépose un travail et attend son exécution sur le thread principal."""
    job = _Job(kind, payload)
    _pending.put(job)
    _app.fireCustomEvent(EVENT_ID, job.id)

    if not job.done.wait(CALL_TIMEOUT_S):
        return {"ok": False, "error": "délai dépassé, Fusion n a pas répondu"}

    with _results_lock:
        return _results.pop(job.id, {"ok": False, "error": "résultat perdu"})


def _run_eval(code):
    """Exécute du code dans le contexte Fusion et rend ce qu'il a produit.

    Le code dispose de app, ui, design, root et adsk. Ce qu'il assigne à
    `result` est renvoyé, ainsi que tout ce qu'il imprime.
    """
    design = adsk.fusion.Design.cast(_app.activeProduct)
    scope = {
        "adsk": adsk,
        "app": _app,
        "ui": _ui,
        "design": design,
        "root": design.rootComponent if design else None,
        "result": None,
    }

    captured = StringIO()
    try:
        exec(code, scope)
        value = scope.get("result")
        return {
            "ok": True,
            "result": repr(value) if value is not None else None,
            "stdout": captured.getvalue(),
        }
    except Exception:
        return {"ok": False, "error": traceback.format_exc(), "stdout": captured.getvalue()}


def _run_screenshot(payload):
    view = payload.get("view")
    width = int(payload.get("width", 1400))
    height = int(payload.get("height", 900))

    viewport = _app.activeViewport
    if view:
        orientations = {
            "iso": adsk.core.ViewOrientations.IsoTopRightViewOrientation,
            "front": adsk.core.ViewOrientations.FrontViewOrientation,
            "back": adsk.core.ViewOrientations.BackViewOrientation,
            "left": adsk.core.ViewOrientations.LeftViewOrientation,
            "right": adsk.core.ViewOrientations.RightViewOrientation,
            "top": adsk.core.ViewOrientations.TopViewOrientation,
            "bottom": adsk.core.ViewOrientations.BottomViewOrientation,
        }
        if view in orientations:
            camera = viewport.camera
            camera.viewOrientation = orientations[view]
            camera.isFitView = True
            viewport.camera = camera
    viewport.fit()
    adsk.doEvents()

    path = payload.get("path") or (tempfile.gettempdir() + "/olympia-fusion-" + uuid.uuid4().hex + ".png")
    if not viewport.saveAsImageFile(path, width, height):
        return {"ok": False, "error": "capture impossible"}
    return {"ok": True, "path": path}


def _run_info(_payload):
    design = adsk.fusion.Design.cast(_app.activeProduct)
    if design is None:
        return {"ok": False, "error": "aucun document de conception ouvert"}

    root = design.rootComponent
    bodies = []
    for body in root.bRepBodies:
        box = body.boundingBox
        bodies.append({
            "name": body.name,
            "visible": body.isLightBulbOn,
            "volume_mm3": round(body.volume * 1000.0, 1),
            "size_mm": [
                round((box.maxPoint.x - box.minPoint.x) * 10.0, 2),
                round((box.maxPoint.y - box.minPoint.y) * 10.0, 2),
                round((box.maxPoint.z - box.minPoint.z) * 10.0, 2),
            ],
        })

    components = []
    for occurrence in root.occurrences:
        comp = occurrence.component
        comp_bodies = []
        for body in comp.bRepBodies:
            box = body.boundingBox
            comp_bodies.append({
                "name": body.name,
                "visible": body.isLightBulbOn,
                "size_mm": [
                    round((box.maxPoint.x - box.minPoint.x) * 10.0, 2),
                    round((box.maxPoint.y - box.minPoint.y) * 10.0, 2),
                    round((box.maxPoint.z - box.minPoint.z) * 10.0, 2),
                ],
            })
        components.append({"name": comp.name, "bodies": comp_bodies})

    parameters = [
        {"name": p.name, "value": p.expression, "comment": p.comment}
        for p in design.userParameters
    ]

    return {
        "ok": True,
        "document": _app.activeDocument.name,
        "unitsManager": design.unitsManager.defaultLengthUnits,
        "rootBodies": bodies,
        "components": components,
        "parameters": parameters,
        "timelineCount": design.timeline.count if design.timeline else 0,
    }


def _run_set_parameter(payload):
    design = adsk.fusion.Design.cast(_app.activeProduct)
    if design is None:
        return {"ok": False, "error": "aucun document de conception ouvert"}

    name = payload.get("name")
    expression = payload.get("expression")
    parameter = design.userParameters.itemByName(name)
    if parameter is None:
        return {"ok": False, "error": "paramètre inconnu : {}".format(name)}

    previous = parameter.expression
    parameter.expression = expression
    adsk.doEvents()
    return {"ok": True, "name": name, "from": previous, "to": parameter.expression}


_RUNNERS = {
    "eval": lambda payload: _run_eval(payload.get("code", "")),
    "screenshot": _run_screenshot,
    "info": _run_info,
    "set_parameter": _run_set_parameter,
}


class _MainThreadHandler(adsk.core.CustomEventHandler):
    """Exécuté sur le thread principal : c'est le seul endroit où l'API est sûre."""

    def notify(self, args):
        try:
            while True:
                try:
                    job = _pending.get_nowait()
                except queue.Empty:
                    return

                runner = _RUNNERS.get(job.kind)
                if runner is None:
                    outcome = {"ok": False, "error": "opération inconnue : {}".format(job.kind)}
                else:
                    try:
                        outcome = runner(job.payload)
                    except Exception:
                        outcome = {"ok": False, "error": traceback.format_exc()}

                with _results_lock:
                    _results[job.id] = outcome
                job.done.set()
        except Exception:
            if _ui:
                _ui.messageBox("OlympiaBridge :\n{}".format(traceback.format_exc()))


class _RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def _reply(self, status, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health":
            self._reply(200, {"ok": True, "service": "OlympiaBridge"})
        elif self.path == "/info":
            self._reply(200, _submit("info", {}))
        else:
            self._reply(404, {"ok": False, "error": "route inconnue"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self._reply(400, {"ok": False, "error": "corps JSON invalide"})
            return

        route = self.path.lstrip("/")
        if route not in _RUNNERS:
            self._reply(404, {"ok": False, "error": "route inconnue : {}".format(route)})
            return

        self._reply(200, _submit(route, payload))


def run(context):
    global _app, _ui, _httpd, _server_thread, _custom_event
    try:
        _app = adsk.core.Application.get()
        _ui = _app.userInterface

        try:
            _app.unregisterCustomEvent(EVENT_ID)
        except Exception:
            pass

        _custom_event = _app.registerCustomEvent(EVENT_ID)
        handler = _MainThreadHandler()
        _custom_event.add(handler)
        _handlers.append(handler)

        _httpd = HTTPServer((HOST, PORT), _RequestHandler)
        _server_thread = threading.Thread(target=_httpd.serve_forever, daemon=True)
        _server_thread.start()

        _ui.messageBox(
            "OlympiaBridge écoute sur http://{}:{}\n\n"
            "Laisse Fusion ouvert. Arrête le pont depuis Scripts et compléments.".format(HOST, PORT)
        )
    except Exception:
        if _ui:
            _ui.messageBox("OlympiaBridge n a pas démarré :\n{}".format(traceback.format_exc()))


def stop(context):
    global _httpd
    try:
        if _httpd:
            _httpd.shutdown()
            _httpd.server_close()
            _httpd = None
        if _app:
            _app.unregisterCustomEvent(EVENT_ID)
    except Exception:
        if _ui:
            _ui.messageBox("Arrêt d OlympiaBridge :\n{}".format(traceback.format_exc()))
