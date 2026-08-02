"""Serveur MCP exposant Fusion 360 à Claude Code.

Il ne parle jamais à Fusion directement : il relaie vers l'add-in OlympiaBridge,
qui écoute en local et se charge de repasser sur le thread principal de Fusion.
"""

import base64
import json
import os
import urllib.error
import urllib.request

try:
    from mcp.server.fastmcp import FastMCP as _Server
except ImportError:
    from mcp.server import MCPServer as _Server

from mcp.types import ImageContent

BRIDGE = os.environ.get("OLYMPIA_FUSION_BRIDGE", "http://127.0.0.1:8765")
TIMEOUT_S = float(os.environ.get("OLYMPIA_FUSION_TIMEOUT", "45"))

mcp = _Server("fusion")


def _call(route, payload=None):
    url = "{}/{}".format(BRIDGE, route)
    data = json.dumps(payload or {}).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            return json.loads(response.read())
    except urllib.error.URLError as error:
        return {
            "ok": False,
            "error": (
                "Le pont ne répond pas sur {}. Ouvre Fusion, puis Utilitaires → "
                "Scripts et compléments → onglet Compléments → OlympiaBridge → "
                "Exécuter. Détail : {}"
            ).format(BRIDGE, error),
        }


def _format(outcome):
    if outcome.get("ok"):
        return outcome
    return "ÉCHEC : {}".format(outcome.get("error", "raison inconnue"))


@mcp.tool()
def fusion_info() -> str:
    """Décrit le document Fusion ouvert : corps, composants, cotes, paramètres.

    À appeler en premier pour savoir ce qui existe avant de modifier quoi que ce soit.
    """
    outcome = _call("info")
    if not outcome.get("ok"):
        return _format(outcome)

    lines = [
        "Document : {}".format(outcome["document"]),
        "Unités : {}".format(outcome["unitsManager"]),
        "Opérations dans la chronologie : {}".format(outcome["timelineCount"]),
    ]

    if outcome["rootBodies"]:
        lines.append("\nCorps à la racine :")
        for body in outcome["rootBodies"]:
            size = " × ".join(str(v) for v in body["size_mm"])
            state = "" if body["visible"] else " (masqué)"
            lines.append("  {} — {} mm{}".format(body["name"], size, state))

    for component in outcome["components"]:
        lines.append("\nComposant {} :".format(component["name"]))
        for body in component["bodies"]:
            size = " × ".join(str(v) for v in body["size_mm"])
            state = "" if body["visible"] else " (masqué)"
            lines.append("  {} — {} mm{}".format(body["name"], size, state))

    if outcome["parameters"]:
        lines.append("\nParamètres :")
        for parameter in outcome["parameters"]:
            comment = " — {}".format(parameter["comment"]) if parameter["comment"] else ""
            lines.append("  {} = {}{}".format(parameter["name"], parameter["value"], comment))

    return "\n".join(lines)


@mcp.tool()
def fusion_screenshot(view: str = "iso", width: int = 1400, height: int = 900) -> ImageContent:
    """Capture la vue Fusion et la renvoie en image.

    view : iso, front, back, left, right, top ou bottom. La vue est recadrée
    sur le modèle avant capture.
    """
    outcome = _call("screenshot", {"view": view, "width": width, "height": height})
    if not outcome.get("ok"):
        raise RuntimeError(outcome.get("error", "capture impossible"))

    with open(outcome["path"], "rb") as handle:
        data = handle.read()
    try:
        os.remove(outcome["path"])
    except OSError:
        pass

    return ImageContent(
        type="image",
        data=base64.b64encode(data).decode("ascii"),
        mimeType="image/png",
    )


@mcp.tool()
def fusion_eval(code: str) -> str:
    """Exécute du Python dans le contexte de Fusion et rend ce qu'il produit.

    Sont déjà en portée : adsk, app, ui, design, root. Affecte ce que tu veux
    récupérer à la variable `result`.

    Les longueurs de l'API sont en CENTIMÈTRES et les angles en RADIANS pour
    ValueInput.createByReal — préfère createByString avec une unité explicite.

    Exemple :
        box = root.bRepBodies.item(0).boundingBox
        result = (box.maxPoint.x - box.minPoint.x) * 10
    """
    outcome = _call("eval", {"code": code})
    if not outcome.get("ok"):
        return "ÉCHEC :\n{}".format(outcome.get("error", ""))

    parts = []
    if outcome.get("stdout"):
        parts.append(outcome["stdout"].rstrip())
    parts.append("result = {}".format(outcome.get("result")))
    return "\n".join(parts)


@mcp.tool()
def fusion_set_parameter(name: str, expression: str) -> str:
    """Change un paramètre utilisateur et régénère le modèle.

    L'expression suit la syntaxe Fusion, unité comprise : "340 mm", "18 deg".
    """
    outcome = _call("set_parameter", {"name": name, "expression": expression})
    if not outcome.get("ok"):
        return _format(outcome)
    return "{} : {} → {}".format(outcome["name"], outcome["from"], outcome["to"])


@mcp.tool()
def fusion_health() -> str:
    """Vérifie que l'add-in tourne dans Fusion."""
    outcome = _call("health")
    if outcome.get("ok"):
        return "Le pont répond sur {}.".format(BRIDGE)
    return _format(outcome)


if __name__ == "__main__":
    mcp.run()
