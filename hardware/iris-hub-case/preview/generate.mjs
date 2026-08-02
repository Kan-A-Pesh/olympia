import { writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

export const params = {
  printBedMm: 256,
  splitXMm: 42,
  minSplitClearanceMm: 10,

  screenWidthMm: 335,
  screenHeightMm: 230,
  screenThicknessMm: 7,
  screenTiltDeg: 18,

  baseWidthMm: 340,
  baseDepthMm: 150,
  baseHeightRearMm: 70,
  baseHeightFrontMm: 38,
  panelStartDepthMm: 54,

  cradleGapMm: 12,
  cradleLipHeightMm: 14,
  cradleOffsetFromRearMm: 26,

  edpSlotWidthMm: 22,
  edpSlotOffsetXMm: 130,
  edpCableLengthMm: 25,

  internals: [
    { name: "carte driver eDP", w: 75, d: 56.5, h: 16, x: 126, z: -40, massG: 60 },
    { name: "Raspberry Pi 4", w: 85, d: 56, h: 18, x: -110, z: -42, massG: 46 },
    { name: "LRS-50-12", w: 99, d: 82, h: 30, x: -105, z: 30, massG: 200 },
    { name: "buck XL4016", w: 61, d: 41, h: 27, x: 0, z: 40, massG: 40 },
  ],

  footDepthMm: 58,
  footWidthMm: 46,
  footHeightMm: 10,
  footOffsetXMm: 122,

  screenMassG: 350,
  shellMassG: 450,
  minTipMarginMm: 25,

  encoderCapRadiusMm: 9,
  encoderCapHeightMm: 15,
  encoderSpacingMm: 46,
  encoderGroupCenterXMm: -83,

  padButtonRadiusMm: 4.5,
  padButtonHeightMm: 5,
  padSpacingMm: 16,
  padCenterXMm: 105,

  usbPortWidthMm: 14,
  usbPortHeightMm: 7,
  usbSpacingMm: 20,
  usbCenterXMm: -20,

  wallMm: 3,
}

const vertices = []
const groups = []
let current = null

const openGroup = (name) => {
  current = { name, faces: [] }
  groups.push(current)
}

const addVertex = (p) => {
  vertices.push(p)
  return vertices.length
}

const addQuad = (a, b, c, d) => current.faces.push([a, b, c, d])

function addBox(width, height, depth, place) {
  const hw = width / 2
  const hd = depth / 2
  const corners = [
    [-hw, 0, -hd], [hw, 0, -hd], [hw, 0, hd], [-hw, 0, hd],
    [-hw, height, -hd], [hw, height, -hd], [hw, height, hd], [-hw, height, hd],
  ]
  const [v0, v1, v2, v3, v4, v5, v6, v7] = corners.map((c) => addVertex(place(c)))

  addQuad(v0, v3, v2, v1)
  addQuad(v4, v5, v6, v7)
  addQuad(v0, v1, v5, v4)
  addQuad(v2, v3, v7, v6)
  addQuad(v1, v2, v6, v5)
  addQuad(v3, v0, v4, v7)
}

function addCylinder(radius, height, place, segments = 24) {
  const bottom = []
  const top = []
  for (let i = 0; i < segments; i++) {
    const a = (i / segments) * Math.PI * 2
    const x = Math.cos(a) * radius
    const z = Math.sin(a) * radius
    bottom.push(addVertex(place([x, 0, z])))
    top.push(addVertex(place([x, height, z])))
  }
  for (let i = 0; i < segments; i++) {
    const j = (i + 1) % segments
    addQuad(bottom[i], bottom[j], top[j], top[i])
  }
  for (let i = 1; i < segments - 1; i++) {
    addQuad(bottom[0], bottom[i], bottom[i + 1], bottom[i])
    addQuad(top[0], top[i], top[i + 1], top[i])
  }
}

const translate = (dx, dy, dz) => ([x, y, z]) => [x + dx, y + dy, z + dz]

const tiltAboutX = (angleRad, dx, dy, dz) => ([x, y, z]) => {
  const cos = Math.cos(angleRad)
  const sin = Math.sin(angleRad)
  return [x + dx, y * cos - z * sin + dy, y * sin + z * cos + dz]
}

function buildBaseShell(p) {
  const hw = p.baseWidthMm / 2
  const hd = p.baseDepthMm / 2
  const zBend = -hd + p.panelStartDepthMm

  const profile = [
    [-hd, 0], [hd, 0], [hd, p.baseHeightFrontMm], [zBend, p.baseHeightRearMm], [-hd, p.baseHeightRearMm],
  ]

  const left = profile.map(([z, y]) => addVertex([-hw, y, z]))
  const right = profile.map(([z, y]) => addVertex([hw, y, z]))

  for (let i = 0; i < profile.length; i++) {
    const j = (i + 1) % profile.length
    addQuad(left[i], right[i], right[j], left[j])
  }
  addQuad(left[0], left[1], left[2], left[3])
  addQuad(right[3], right[2], right[1], right[0])
}

function panelPlacer(p) {
  const hd = p.baseDepthMm / 2
  const zBend = -hd + p.panelStartDepthMm
  const run = hd - zBend
  const rise = p.baseHeightRearMm - p.baseHeightFrontMm
  const slope = Math.atan2(rise, run)

  return (offsetAlongPanel, x) => {
    const z = zBend + Math.cos(slope) * offsetAlongPanel
    const y = p.baseHeightRearMm - Math.sin(slope) * offsetAlongPanel
    return tiltAboutX(slope, x, y, z)
  }
}

function build(p = params) {
  vertices.length = 0
  groups.length = 0

  openGroup("base")
  buildBaseShell(p)

  openGroup("cradle")
  const hd = p.baseDepthMm / 2
  const cradleZ = -hd + p.cradleOffsetFromRearMm
  const lipDepth = 6
  addBox(p.baseWidthMm, p.cradleLipHeightMm, lipDepth, translate(0, p.baseHeightRearMm, cradleZ - p.cradleGapMm / 2 - lipDepth / 2))
  addBox(p.baseWidthMm, p.cradleLipHeightMm, lipDepth, translate(0, p.baseHeightRearMm, cradleZ + p.cradleGapMm / 2 + lipDepth / 2))

  openGroup("edp-slot")
  addBox(p.edpSlotWidthMm, 2, p.cradleGapMm, translate(p.edpSlotOffsetXMm, p.baseHeightRearMm - 1, cradleZ))

  openGroup("screen")
  const tilt = (p.screenTiltDeg * Math.PI) / 180
  addBox(
    p.screenWidthMm,
    p.screenHeightMm,
    p.screenThicknessMm,
    tiltAboutX(-tilt, 0, p.baseHeightRearMm - p.cradleLipHeightMm / 2, cradleZ),
  )

  const onPanel = panelPlacer(p)

  openGroup("encoders")
  for (let i = 0; i < 4; i++) {
    const x = p.encoderGroupCenterXMm + (i - 1.5) * p.encoderSpacingMm
    addCylinder(p.encoderCapRadiusMm, p.encoderCapHeightMm, onPanel(30, x))
  }

  openGroup("pad")
  const pad = [
    [-1, -1], [0, -1], [1, -1],
    [-1, 0], [1, 0],
    [-1, 1], [0, 1], [1, 1],
  ]
  for (const [cx, cy] of pad) {
    const x = p.padCenterXMm + cx * p.padSpacingMm
    addCylinder(p.padButtonRadiusMm, p.padButtonHeightMm, onPanel(30 + cy * p.padSpacingMm, x))
  }

  openGroup("usb")
  for (let i = 0; i < 4; i++) {
    const x = p.usbCenterXMm + (i - 1.5) * p.usbSpacingMm
    addBox(p.usbPortWidthMm, p.usbPortHeightMm, 3, translate(x, 12, p.baseDepthMm / 2))
  }

  openGroup("split")
  addBox(1.2, p.baseHeightRearMm, p.baseDepthMm, translate(p.splitXMm, 0, 0))

  openGroup("feet")
  const footZ = -hd - p.footDepthMm / 2
  for (const sign of [-1, 1]) {
    addBox(p.footWidthMm, p.footHeightMm, p.footDepthMm, translate(sign * p.footOffsetXMm, 0, footZ))
  }

  openGroup("internals")
  for (const c of p.internals) addBox(c.w, c.h, c.d, translate(c.x, p.wallMm, c.z))

  return { vertices, groups }
}

function screenCentreOfMass(p) {
  const cradleZ = -p.baseDepthMm / 2 + p.cradleOffsetFromRearMm
  const tilt = (p.screenTiltDeg * Math.PI) / 180
  const along = p.screenHeightMm / 2
  return {
    y: p.baseHeightRearMm - p.cradleLipHeightMm / 2 + along * Math.cos(tilt),
    z: cradleZ - along * Math.sin(tilt),
  }
}

function checkStability(p) {
  const screen = screenCentreOfMass(p)
  const masses = [
    { massG: p.screenMassG, z: screen.z },
    { massG: p.shellMassG, z: 0 },
    ...p.internals.map((c) => ({ massG: c.massG, z: c.z })),
  ]

  const total = masses.reduce((sum, m) => sum + m.massG, 0)
  const centreZ = masses.reduce((sum, m) => sum + m.massG * m.z, 0) / total

  const rearPivotZ = -p.baseDepthMm / 2 - p.footDepthMm
  const bareRearPivotZ = -p.baseDepthMm / 2
  const margin = centreZ - rearPivotZ
  const bareMargin = centreZ - bareRearPivotZ

  const problems = []
  if (margin < p.minTipMarginMm) {
    problems.push(`bascule arrière : ${margin.toFixed(0)} mm de marge, ${p.minTipMarginMm} mm requis`)
  }

  const feetHalf = p.footWidthMm / 2
  for (const sign of [-1, 1]) {
    const inner = sign * p.footOffsetXMm - feetHalf
    const outer = sign * p.footOffsetXMm + feetHalf
    if (Math.min(inner, outer) < p.splitXMm && p.splitXMm < Math.max(inner, outer)) {
      problems.push(`le pied ${sign < 0 ? "gauche" : "droit"} est à cheval sur le plan de joint`)
    }
  }

  return { problems, totalMassG: total, centreZ, margin, bareMargin, screen }
}

function headroomAt(p, z) {
  const hd = p.baseDepthMm / 2
  const zBend = -hd + p.panelStartDepthMm
  if (z <= zBend) return p.baseHeightRearMm
  const t = (z - zBend) / (hd - zBend)
  return p.baseHeightRearMm - t * (p.baseHeightRearMm - p.baseHeightFrontMm)
}

function checkInternals(p) {
  const problems = []
  const halfW = p.baseWidthMm / 2 - p.wallMm
  const halfD = p.baseDepthMm / 2 - p.wallMm

  const boxes = p.internals.map((c) => ({
    ...c,
    x0: c.x - c.w / 2, x1: c.x + c.w / 2,
    z0: c.z - c.d / 2, z1: c.z + c.d / 2,
  }))

  for (const b of boxes) {
    if (b.x0 < -halfW || b.x1 > halfW) problems.push(`${b.name} déborde en largeur`)
    if (b.z0 < -halfD || b.z1 > halfD) problems.push(`${b.name} déborde en profondeur`)

    const clearance = Math.min(headroomAt(p, b.z0), headroomAt(p, b.z1)) - p.wallMm
    if (b.h > clearance) {
      problems.push(`${b.name} : ${b.h} mm de haut pour ${clearance.toFixed(0)} mm sous le capot`)
    }
  }

  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i]
      const b = boxes[j]
      if (a.x0 < b.x1 && b.x0 < a.x1 && a.z0 < b.z1 && b.z0 < a.z1) {
        problems.push(`${a.name} et ${b.name} se chevauchent`)
      }
    }
  }

  for (const b of boxes) {
    if (b.x0 < p.splitXMm && p.splitXMm < b.x1) {
      problems.push(`${b.name} est à cheval sur le plan de joint`)
    }
  }

  const driver = boxes.find((b) => b.name.includes("driver"))
  if (driver) {
    const hd = p.baseDepthMm / 2
    const slotZ = -hd + p.cradleOffsetFromRearMm
    const dx = Math.max(0, Math.abs(driver.x - p.edpSlotOffsetXMm) - driver.w / 2)
    const dz = Math.max(0, Math.abs(driver.z - slotZ) - driver.d / 2)
    const reach = Math.hypot(dx, dz)
    if (reach > p.edpCableLengthMm) {
      problems.push(`câble eDP : ${reach.toFixed(0)} mm à parcourir pour ${p.edpCableLengthMm} mm disponibles`)
    }
    return { problems, cableReachMm: reach }
  }

  return { problems, cableReachMm: null }
}

function checkPrintability(p) {
  const bed = p.printBedMm
  const pieces = [
    { name: "gauche", width: p.splitXMm + p.baseWidthMm / 2 },
    { name: "droite", width: p.baseWidthMm / 2 - p.splitXMm },
  ]

  const obstacles = []
  for (let i = 0; i < 4; i++) {
    const x = p.encoderGroupCenterXMm + (i - 1.5) * p.encoderSpacingMm
    obstacles.push({ what: `encodeur ${i + 1}`, from: x - p.encoderCapRadiusMm, to: x + p.encoderCapRadiusMm })
  }
  for (const cx of [-1, 0, 1]) {
    const x = p.padCenterXMm + cx * p.padSpacingMm
    obstacles.push({ what: `pavé colonne ${cx + 2}`, from: x - p.padButtonRadiusMm, to: x + p.padButtonRadiusMm })
  }
  for (let i = 0; i < 4; i++) {
    const x = p.usbCenterXMm + (i - 1.5) * p.usbSpacingMm
    obstacles.push({ what: `port USB ${i + 1}`, from: x - p.usbPortWidthMm / 2, to: x + p.usbPortWidthMm / 2 })
  }

  const problems = []
  for (const piece of pieces) {
    if (piece.width > bed) problems.push(`pièce ${piece.name} : ${piece.width.toFixed(0)} mm > plateau ${bed} mm`)
  }
  for (const o of obstacles) {
    if (p.splitXMm > o.from && p.splitXMm < o.to) problems.push(`le plan de joint coupe ${o.what}`)
  }

  const clearance = Math.min(...obstacles.map((o) => Math.min(Math.abs(p.splitXMm - o.from), Math.abs(p.splitXMm - o.to))))
  if (clearance < p.minSplitClearanceMm) {
    problems.push(`dégagement du joint ${clearance.toFixed(0)} mm < ${p.minSplitClearanceMm} mm requis pour deux parois et leur bride`)
  }

  return { pieces, problems, clearanceMm: clearance }
}

function toObj({ vertices: verts, groups: gs }) {
  const lines = ["# iris-hub-case — massing preview, millimetres", "mtllib preview.mtl"]
  for (const [x, y, z] of verts) lines.push(`v ${x.toFixed(3)} ${y.toFixed(3)} ${z.toFixed(3)}`)
  for (const g of gs) {
    lines.push(`g ${g.name}`, `usemtl ${g.name}`)
    for (const f of g.faces) lines.push(`f ${f.join(" ")}`)
  }
  return lines.join("\n") + "\n"
}

const MATERIALS = {
  base: [0.62, 0.63, 0.66],
  cradle: [0.45, 0.47, 0.5],
  "edp-slot": [0.9, 0.35, 0.25],
  screen: [0.12, 0.13, 0.16],
  encoders: [0.85, 0.72, 0.3],
  pad: [0.35, 0.6, 0.85],
  usb: [0.3, 0.75, 0.55],
  split: [0.82, 0.37, 0.82],
  internals: [0.55, 0.47, 0.35],
  feet: [0.45, 0.5, 0.55],
}

const toMtl = () =>
  Object.entries(MATERIALS)
    .map(([name, [r, g, b]]) => `newmtl ${name}\nKd ${r} ${g} ${b}\nKa 0.1 0.1 0.1\n`)
    .join("\n")

const here = dirname(fileURLToPath(import.meta.url))
const model = build()
writeFileSync(join(here, "iris-hub-case.obj"), toObj(model))
writeFileSync(join(here, "preview.mtl"), toMtl())
console.log(`${model.vertices.length} sommets, ${model.groups.length} groupes`)

const { pieces, problems, clearanceMm } = checkPrintability(params)
console.log(`\nPlateau ${params.printBedMm} mm — joint à x = ${params.splitXMm} mm`)
for (const piece of pieces) {
  console.log(`  ${piece.name.padEnd(8)} ${piece.width.toFixed(0)} × ${params.baseDepthMm} × ${params.baseHeightRearMm} mm`)
}
console.log(`  dégagement du joint : ${clearanceMm.toFixed(0)} mm`)

const internals = checkInternals(params)
console.log(`\nImplantation interne`)
for (const c of params.internals) {
  const headroom = Math.min(headroomAt(params, c.z - c.d / 2), headroomAt(params, c.z + c.d / 2)) - params.wallMm
  console.log(`  ${c.name.padEnd(18)} ${c.w} × ${c.d} × ${c.h} mm, ${headroom.toFixed(0)} mm sous le capot`)
}
if (internals.cableReachMm !== null) {
  console.log(`  câble eDP : ${internals.cableReachMm.toFixed(0)} mm à parcourir / ${params.edpCableLengthMm} mm`)
}

const stability = checkStability(params)
console.log(`\nStabilité`)
console.log(`  masse totale        ${stability.totalMassG} g`)
console.log(`  centre de gravité   z = ${stability.centreZ.toFixed(0)} mm`)
console.log(`  CG de l'écran       z = ${stability.screen.z.toFixed(0)} mm, y = ${stability.screen.y.toFixed(0)} mm`)
console.log(`  marge sans pieds    ${stability.bareMargin.toFixed(0)} mm`)
console.log(`  marge avec pieds    ${stability.margin.toFixed(0)} mm (min ${params.minTipMarginMm})`)

const allProblems = [...problems, ...internals.problems, ...stability.problems]
if (allProblems.length > 0) {
  console.log("")
  for (const problem of allProblems) console.log(`  PROBLÈME : ${problem}`)
  process.exitCode = 1
}
