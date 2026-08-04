"""Génère le boîtier iris-hub dans Fusion 360.

À placer dans ~/Library/Application Support/Autodesk/Autodesk Fusion 360/API/Scripts/
puis lancer depuis UTILITAIRES → Scripts et compléments.

Toutes les cotes sont en millimètres dans PARAMS et deviennent des paramètres
utilisateur pilotables depuis la table des paramètres de Fusion.
"""

import adsk.core
import adsk.fusion
import traceback

# L'API Fusion travaille en centimètres pour createByReal et en radians pour les
# angles. Tout passe donc par createByString avec unité explicite, ou par mm().
PARAMS = [
    ("base_width", 340.0, "largeur hors tout du boîtier", "mm"),
    ("base_depth", 150.0, "profondeur du boîtier hors pieds", "mm"),
    ("base_height_rear", 70.0, "hauteur au dos", "mm"),
    ("base_height_front", 38.0, "hauteur en façade", "mm"),
    ("panel_start_depth", 54.0, "profondeur du plateau plat avant la pente", "mm"),
    ("wall", 3.0, "épaisseur de paroi", "mm"),
    ("split_x", 42.0, "position du plan de joint depuis le centre", "mm"),

    ("screen_width", 335.0, "largeur du capot ThinkPad", "mm"),
    ("screen_height", 230.0, "hauteur du capot", "mm"),
    ("screen_thickness", 7.0, "épaisseur du capot fermé", "mm"),
    ("screen_tilt", 18.0, "inclinaison du capot", "deg"),

    ("cradle_gap", 9.0, "largeur de la gorge du berceau", "mm"),
    ("cradle_lip_height", 14.0, "hauteur des lèvres du berceau", "mm"),
    ("cradle_offset_rear", 26.0, "position du berceau depuis le dos", "mm"),

    ("cable_slot_width", 22.0, "largeur du passage du câble eDP", "mm"),
    ("cable_slot_x", 130.0, "position du passage depuis le centre", "mm"),

    ("encoder_hole_dia", 7.2, "perçage de façade pour EC11, filetage M7x0.75", "mm"),
    ("encoder_spacing", 46.0, "entraxe des encodeurs", "mm"),
    ("encoder_group_x", -83.0, "centre du groupe d'encodeurs", "mm"),
    ("encoder_offset", 30.0, "distance depuis le pli, le long de la façade", "mm"),

    ("pad_hole_dia", 9.0, "perçage de façade pour un capuchon de tactile 6x6", "mm"),
    ("pad_spacing", 16.0, "entraxe du pavé, atteignable au pouce sans bouger la main", "mm"),
    ("pad_center_x", 105.0, "centre du pavé", "mm"),

    ("usb_cut_width", 15.0, "largeur de découpe d'un port USB", "mm"),
    ("usb_cut_height", 8.0, "hauteur de découpe d'un port USB", "mm"),
    ("usb_spacing", 20.0, "entraxe des ports USB", "mm"),
    ("usb_center_x", -20.0, "centre du groupe USB", "mm"),
    ("usb_height", 12.0, "hauteur des ports au-dessus du plancher", "mm"),

    ("foot_width", 46.0, "largeur d'un pied", "mm"),
    ("foot_depth", 58.0, "débord d'un pied vers l'arrière", "mm"),
    ("foot_height", 10.0, "hauteur d'un pied", "mm"),
    ("foot_offset_x", 122.0, "position d'un pied depuis le centre", "mm"),

    # Ruthex RX-M3x5.7 : trou 4,0 mm et paroi mini 1,6 mm sont les cotes du
    # fabricant ; la profondeur suit la règle SPIROL longueur + 2 pas de filet.
    ("insert_hole_dia", 4.0, "perçage recevant l'insert laiton M3", "mm"),
    ("insert_depth", 6.7, "profondeur du perçage d'insert", "mm"),
    ("boss_dia", 8.6, "diamètre extérieur d'un bossage d'insert", "mm"),
    ("boss_height", 9.0, "hauteur d'un bossage", "mm"),
]


def mm(value):
    """Valeur en millimètres pour l'API, qui attend des centimètres."""
    return adsk.core.ValueInput.createByReal(value / 10.0)


def cm(value):
    return value / 10.0


def point(x, y, z):
    return adsk.core.Point3D.create(cm(x), cm(y), cm(z))


def create_parameters(design):
    """Publie PARAMS dans la table des paramètres, sans écraser l'existant."""
    existing = {p.name for p in design.userParameters}
    for name, value, comment, unit in PARAMS:
        if name in existing:
            continue
        design.userParameters.add(
            name,
            adsk.core.ValueInput.createByString("{} {}".format(value, unit)),
            unit,
            comment,
        )


def values():
    return {name: value for name, value, _, _ in PARAMS}


def build_shell(comp, p):
    """Extrude le profil latéral du boîtier sur toute sa largeur."""
    half_depth = p["base_depth"] / 2.0
    bend_z = -half_depth + p["panel_start_depth"]

    sketch = comp.sketches.add(comp.yZConstructionPlane)
    lines = sketch.sketchCurves.sketchLines

    # Le profil est tracé dans le plan YZ : Z en profondeur, Y en hauteur.
    profile_points = [
        (-half_depth, 0.0),
        (half_depth, 0.0),
        (half_depth, p["base_height_front"]),
        (bend_z, p["base_height_rear"]),
        (-half_depth, p["base_height_rear"]),
    ]

    previous = None
    first = None
    for z, y in profile_points:
        current = adsk.core.Point3D.create(cm(-z), cm(y), 0)
        if previous is not None:
            lines.addByTwoPoints(previous, current)
        else:
            first = current
        previous = current
    lines.addByTwoPoints(previous, first)

    profile = sketch.profiles.item(0)
    extrudes = comp.features.extrudeFeatures
    ext_input = extrudes.createInput(
        profile, adsk.fusion.FeatureOperations.NewBodyFeatureOperation
    )
    ext_input.setSymmetricExtent(mm(p["base_width"]), True)
    return extrudes.add(ext_input).bodies.item(0)


def find_panel_face(body, p):
    """Retourne la face inclinée qui portera les commandes.

    Elle se reconnaît à sa normale : orientée vers l'avant ET vers le haut,
    ce qui n'est vrai d'aucune autre face du prisme.
    """
    best = None
    best_score = 0.0
    for face in body.faces:
        try:
            normal = face.geometry.normal
        except AttributeError:
            continue
        if normal.y > 0.1 and normal.z > 0.1:
            score = normal.y * normal.z
            if score > best_score:
                best_score = score
                best = face
    return best


def cut_circles(comp, sketch, diameter, depth):
    """Perce toutes les esquisses de cercles d'un sketch en une seule opération."""
    if sketch.profiles.count == 0:
        return None
    collection = adsk.core.ObjectCollection.create()
    for i in range(sketch.profiles.count):
        collection.add(sketch.profiles.item(i))

    extrudes = comp.features.extrudeFeatures
    cut_input = extrudes.createInput(
        collection, adsk.fusion.FeatureOperations.CutFeatureOperation
    )
    cut_input.setDistanceExtent(False, mm(-depth))
    return extrudes.add(cut_input)


def add_panel_holes(comp, body, p):
    face = find_panel_face(body, p)
    if face is None:
        raise RuntimeError("face de commande introuvable sur le corps du boîtier")

    sketch = comp.sketches.add(face)
    circles = sketch.sketchCurves.sketchCircles

    # Sur une esquisse posée sur la face, X suit la largeur du boîtier et Y
    # descend le long de la pente depuis le pli.
    for i in range(4):
        x = p["encoder_group_x"] + (i - 1.5) * p["encoder_spacing"]
        circles.addByCenterRadius(
            adsk.core.Point3D.create(cm(x), cm(-p["encoder_offset"]), 0),
            cm(p["encoder_hole_dia"] / 2.0),
        )

    pad_cells = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    for cx, cy in pad_cells:
        x = p["pad_center_x"] + cx * p["pad_spacing"]
        y = -(p["encoder_offset"] + cy * p["pad_spacing"])
        circles.addByCenterRadius(
            adsk.core.Point3D.create(cm(x), cm(y), 0), cm(p["pad_hole_dia"] / 2.0)
        )

    cut_circles(comp, sketch, None, p["wall"] + 2.0)


def add_cable_slot(comp, p):
    half_depth = p["base_depth"] / 2.0
    cradle_z = -half_depth + p["cradle_offset_rear"]

    sketch = comp.sketches.add(comp.xZConstructionPlane)
    sketch.sketchCurves.sketchLines.addCenterPointRectangle(
        adsk.core.Point3D.create(cm(p["cable_slot_x"]), cm(cradle_z), 0),
        adsk.core.Point3D.create(
            cm(p["cable_slot_x"] + p["cable_slot_width"] / 2.0),
            cm(cradle_z + p["cradle_gap"] / 2.0),
            0,
        ),
    )
    extrudes = comp.features.extrudeFeatures
    cut_input = extrudes.createInput(
        sketch.profiles.item(0), adsk.fusion.FeatureOperations.CutFeatureOperation
    )
    cut_input.setAllExtent(adsk.fusion.ExtentDirections.PositiveExtentDirection)
    extrudes.add(cut_input)


def offset_plane(comp, base_plane, distance):
    planes = comp.constructionPlanes
    plane_input = planes.createInput()
    plane_input.setByOffset(base_plane, mm(distance))
    return planes.add(plane_input)


def add_cradle(comp, p):
    """Deux lèvres qui forment la gorge recevant le capot.

    La gorge fait cradle_gap pour un capot de screen_thickness : l'écart
    accueille un joint mousse qui rattrape le jeu et évite de marquer le capot.
    """
    half_depth = p["base_depth"] / 2.0
    cradle_z = -half_depth + p["cradle_offset_rear"]
    lip_depth = 6.0
    top = offset_plane(comp, comp.xZConstructionPlane, p["base_height_rear"])
    extrudes = comp.features.extrudeFeatures

    for side in (-1, 1):
        centre_z = cradle_z + side * (p["cradle_gap"] / 2.0 + lip_depth / 2.0)
        sketch = comp.sketches.add(top)
        sketch.sketchCurves.sketchLines.addCenterPointRectangle(
            adsk.core.Point3D.create(0, cm(centre_z), 0),
            adsk.core.Point3D.create(
                cm(p["base_width"] / 2.0), cm(centre_z + lip_depth / 2.0), 0
            ),
        )
        ext_input = extrudes.createInput(
            sketch.profiles.item(0), adsk.fusion.FeatureOperations.JoinFeatureOperation
        )
        ext_input.setDistanceExtent(False, mm(p["cradle_lip_height"]))
        extrudes.add(ext_input)


def add_usb_cuts(comp, p):
    """Quatre découpes rectangulaires dans la façade verticale."""
    sketch = comp.sketches.add(comp.xYConstructionPlane)
    lines = sketch.sketchCurves.sketchLines

    for i in range(4):
        x = p["usb_center_x"] + (i - 1.5) * p["usb_spacing"]
        lines.addCenterPointRectangle(
            adsk.core.Point3D.create(cm(x), cm(p["usb_height"]), 0),
            adsk.core.Point3D.create(
                cm(x + p["usb_cut_width"] / 2.0),
                cm(p["usb_height"] + p["usb_cut_height"] / 2.0),
                0,
            ),
        )

    if sketch.profiles.count == 0:
        return
    collection = adsk.core.ObjectCollection.create()
    for i in range(sketch.profiles.count):
        collection.add(sketch.profiles.item(i))

    extrudes = comp.features.extrudeFeatures
    cut_input = extrudes.createInput(
        collection, adsk.fusion.FeatureOperations.CutFeatureOperation
    )
    cut_input.setAllExtent(adsk.fusion.ExtentDirections.PositiveExtentDirection)
    extrudes.add(cut_input)


def add_screen_reference(comp, p):
    """Corps de référence figurant le capot ThinkPad en place.

    Il ne fait pas partie de la pièce imprimée : il sert à vérifier les
    dégagements et le porte-à-faux. À masquer avant export.
    """
    half_depth = p["base_depth"] / 2.0
    cradle_z = -half_depth + p["cradle_offset_rear"]
    tilt = comp.constructionPlanes.createInput()
    tilt.setByAngle(
        comp.xConstructionAxis,
        adsk.core.ValueInput.createByString("{} deg".format(-p["screen_tilt"])),
        comp.xZConstructionPlane,
    )
    plane = comp.constructionPlanes.add(tilt)

    sketch = comp.sketches.add(plane)
    sketch.sketchCurves.sketchLines.addCenterPointRectangle(
        adsk.core.Point3D.create(0, cm(cradle_z), 0),
        adsk.core.Point3D.create(
            cm(p["screen_width"] / 2.0), cm(cradle_z + p["screen_height"] / 2.0), 0
        ),
    )
    extrudes = comp.features.extrudeFeatures
    ext_input = extrudes.createInput(
        sketch.profiles.item(0), adsk.fusion.FeatureOperations.NewBodyFeatureOperation
    )
    ext_input.setDistanceExtent(False, mm(p["screen_thickness"]))
    body = extrudes.add(ext_input).bodies.item(0)
    body.name = "capot ThinkPad (référence)"
    body.isLightBulbOn = False
    return body


def add_feet(comp, p):
    half_depth = p["base_depth"] / 2.0
    extrudes = comp.features.extrudeFeatures

    for sign in (-1, 1):
        sketch = comp.sketches.add(comp.xZConstructionPlane)
        centre_z = -half_depth - p["foot_depth"] / 2.0
        sketch.sketchCurves.sketchLines.addCenterPointRectangle(
            adsk.core.Point3D.create(cm(sign * p["foot_offset_x"]), cm(centre_z), 0),
            adsk.core.Point3D.create(
                cm(sign * p["foot_offset_x"] + p["foot_width"] / 2.0),
                cm(centre_z + p["foot_depth"] / 2.0),
                0,
            ),
        )
        ext_input = extrudes.createInput(
            sketch.profiles.item(0), adsk.fusion.FeatureOperations.NewBodyFeatureOperation
        )
        ext_input.setDistanceExtent(False, mm(p["foot_height"]))
        extrudes.add(ext_input)


def add_insert_bosses(comp, p, positions):
    """Crée un bossage cylindrique percé pour chaque position (x, z).

    Le perçage suit les cotes Ruthex : 4,0 mm de diamètre sur 6,7 mm de
    profondeur, dans un bossage de 8,6 mm qui laisse 2,3 mm de paroi.
    """
    extrudes = comp.features.extrudeFeatures

    for x, z in positions:
        boss_sketch = comp.sketches.add(comp.xZConstructionPlane)
        boss_sketch.sketchCurves.sketchCircles.addByCenterRadius(
            adsk.core.Point3D.create(cm(x), cm(z), 0), cm(p["boss_dia"] / 2.0)
        )
        boss_input = extrudes.createInput(
            boss_sketch.profiles.item(0),
            adsk.fusion.FeatureOperations.JoinFeatureOperation,
        )
        boss_input.setDistanceExtent(False, mm(p["boss_height"]))
        extrudes.add(boss_input)

        hole_sketch = comp.sketches.add(comp.xZConstructionPlane)
        hole_sketch.sketchCurves.sketchCircles.addByCenterRadius(
            adsk.core.Point3D.create(cm(x), cm(z), 0), cm(p["insert_hole_dia"] / 2.0)
        )
        hole_input = extrudes.createInput(
            hole_sketch.profiles.item(0),
            adsk.fusion.FeatureOperations.CutFeatureOperation,
        )
        hole_input.setDistanceExtent(False, mm(p["insert_depth"]))
        extrudes.add(hole_input)


def boss_positions(p):
    """Six bossages : quatre aux angles, deux de part et d'autre du joint."""
    half_width = p["base_width"] / 2.0 - p["boss_dia"]
    half_depth = p["base_depth"] / 2.0 - p["boss_dia"]
    joint_offset = p["boss_dia"] / 2.0 + 2.0

    return [
        (-half_width, -half_depth),
        (half_width, -half_depth),
        (-half_width, half_depth),
        (half_width, half_depth),
        (p["split_x"] - joint_offset, -half_depth),
        (p["split_x"] - joint_offset, half_depth),
    ]


def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        design = adsk.fusion.Design.cast(app.activeProduct)
        if design is None:
            ui.messageBox("Ouvre un document de conception avant de lancer le script.")
            return

        design.designType = adsk.fusion.DesignTypes.ParametricDesignType
        create_parameters(design)

        root = design.rootComponent
        occurrence = root.occurrences.addNewComponent(adsk.core.Matrix3D.create())
        comp = occurrence.component
        comp.name = "iris-hub-case"

        p = values()
        body = build_shell(comp, p)
        add_panel_holes(comp, body, p)
        add_cradle(comp, p)
        add_cable_slot(comp, p)
        add_usb_cuts(comp, p)
        add_feet(comp, p)
        add_insert_bosses(comp, p, boss_positions(p))
        add_screen_reference(comp, p)

        ui.messageBox(
            "iris-hub-case généré.\n\n"
            "Les cotes sont dans MODIFIER → Modifier les paramètres.\n"
            "Reste à faire à la main : coque, congés, et découpe selon le plan "
            "de joint à x = {} mm.".format(p["split_x"])
        )

    except:  # noqa: E722 - Fusion attend ce motif pour rapporter la trace
        if ui:
            ui.messageBox("Échec :\n{}".format(traceback.format_exc()))
