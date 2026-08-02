#!/usr/bin/env bash
# design.sh — 489 nomenclature par boîtier · 490 quantités chiffrées · 491 cote sans unité
#             492 pièce hors plateau · 493 maillage démesuré · 494 conception binaire hors LFS
#             495 notice de montage · 496 visserie spécifiée · 497 cote non mesurée non signalée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DOCTOR_PRINT_BED_MM="${DOCTOR_PRINT_BED_MM:-256}" \
DOCTOR_MESH_MAX_MB="${DOCTOR_MESH_MAX_MB:-20}" \
DOCTOR_MESH_MAX_TRIANGLES="${DOCTOR_MESH_MAX_TRIANGLES:-200000}" \
node -e '
const fs = require("node:fs")
const path = require("node:path")

const SKIP = new Set([".git", "node_modules", "dist"])
const walk = (dir) => {
  const out = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue
    const p = path.join(dir, e.name)
    if (e.isDirectory()) out.push(...walk(p))
    else out.push(p)
  }
  return out
}

const done = (msg) => { console.log(`OK: ${msg}`); process.exit(0) }
if (!fs.existsSync("hardware")) done("aucun dossier de conception à inspecter")
const files = walk("hardware")
if (files.length === 0) done("aucun dossier de conception à inspecter")

const BED = Number(process.env.DOCTOR_PRINT_BED_MM)
const MAX_MB = Number(process.env.DOCTOR_MESH_MAX_MB)
const MAX_TRI = Number(process.env.DOCTOR_MESH_MAX_TRIANGLES)
const fails = []
const warns = []

const CAD = /\.(f3d|step|stp|sldprt|3mf|dwg|sat|iges|igs)$/i
const MESH = /\.(stl|obj|ply)$/i
const docs = files.filter((f) => /\.md$/i.test(f))
const boms = files.filter((f) => /^(bom|nomenclature)[\w.-]*\.(md|csv|tsv|json)$/i.test(path.basename(f)))
const assemblies = files.filter((f) => /^(assembly|montage)[\w.-]*\.md$/i.test(path.basename(f)))

const enclosures = fs.readdirSync("hardware", { withFileTypes: true })
  .filter((e) => e.isDirectory() && !SKIP.has(e.name))
  .map((e) => path.join("hardware", e.name))

for (const enclosure of enclosures) {
  const own = files.filter((f) => f.startsWith(`${enclosure}${path.sep}`))
  const artifacts = own.filter((f) => CAD.test(f) || MESH.test(f))
  if (artifacts.length === 0) continue
  if (!own.some((f) => boms.includes(f))) warns.push(`489 ${enclosure} — aucune nomenclature`)
  if (!own.some((f) => assemblies.includes(f))) warns.push(`495 ${enclosure} — aucune notice de montage`)
}

const QTY = /(qt[ée]?|quantit|qty|nombre)/i
for (const bom of boms) {
  const text = fs.readFileSync(bom, "utf8")
  const head = text.split("\n").slice(0, 5).join(" ")
  if (!QTY.test(head)) warns.push(`490 ${bom} — aucune colonne de quantité`)
}

for (const doc of assemblies) {
  const text = fs.readFileSync(doc, "utf8")
  if (!/\bM\d([.,]\d)?\s*[×x]\s*\d+/.test(text))
    warns.push(`496 ${doc} — aucune visserie spécifiée (diamètre × longueur)`)
}

const UNIT = /(mm|cm|µm|um|inch|\bin\b|\bmil\b|°|")/
const DIM = /\d+(?:[.,]\d+)?\s*[×x]\s*\d+(?:[.,]\d+)?/
// M3 x 8 est une designation ISO de visserie, pas une cote : l unite y est normative.
const FASTENER = /\bM\d+(?:[.,]\d+)?\s*[×x]\s*\d+(?:[.,]\d+)?/
const PLACEHOLDER = /^(\?+|tbd|todo|xx+|n\/a|-+|—+|\.\.\.|)$/i
const MEASURE = /(à mesurer|a mesurer|non mesur|à confirmer|a confirmer|estim|provisoire)/i
const PARAM = /(length|width|height|thickness|offset|depth|diam|angle|pitch|entraxe|longueur|largeur|hauteur|[ée]paisseur|profondeur|cote|dimension|encombrement|_mm)/i

for (const doc of docs) {
  const lines = fs.readFileSync(doc, "utf8").split("\n")
  lines.forEach((line, i) => {
    const where = `${doc}:${i + 1}`
    if (/^\s*\|?[\s|:-]+\|?\s*$/.test(line)) return

    const withoutFasteners = line.replace(new RegExp(FASTENER.source, "g"), "")
    if (DIM.test(withoutFasteners) && !UNIT.test(withoutFasteners))
      fails.push(`491 ${where} — cote sans unité: ${line.trim().slice(0, 60)}`)

    if (line.trim().startsWith("|")) {
      const cells = line.split("|").slice(1, -1).map((c) => c.trim())
      if (cells.length >= 2 && PARAM.test(cells[0])) {
        const values = cells.slice(1)
        const empty = values.every((c) => PLACEHOLDER.test(c.replace(/[*`]/g, "").trim()))
        if (empty && !MEASURE.test(line))
          fails.push(`497 ${where} — ${cells[0]} sans valeur ni mention de mesure`)
      }
    }
  })
}

const bbox = (file) => {
  const bytes = fs.statSync(file).size
  if (bytes > MAX_MB * 1024 * 1024) return { size: [0, 0, 0], triangles: 0, bytes }
  const buf = fs.readFileSync(file)
  const min = [Infinity, Infinity, Infinity]
  const max = [-Infinity, -Infinity, -Infinity]
  let triangles = 0
  const head = buf.subarray(0, Math.min(512, buf.length)).toString("latin1")
  if (/^\s*solid/.test(head) && !head.includes("\u0000")) {
    const text = buf.toString("latin1")
    triangles = (text.match(/facet\s+normal/g) || []).length
    for (const m of text.matchAll(/vertex\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)/g)) {
      for (let a = 0; a < 3; a++) {
        const v = Number(m[a + 1])
        if (!Number.isFinite(v)) continue
        if (v < min[a]) min[a] = v
        if (v > max[a]) max[a] = v
      }
    }
  } else if (buf.length >= 84) {
    triangles = buf.readUInt32LE(80)
    const available = Math.floor((buf.length - 84) / 50)
    for (let t = 0; t < Math.min(triangles, available); t++) {
      const base = 84 + t * 50 + 12
      for (let v = 0; v < 3; v++) {
        for (let a = 0; a < 3; a++) {
          const value = buf.readFloatLE(base + v * 12 + a * 4)
          if (!Number.isFinite(value)) continue
          if (value < min[a]) min[a] = value
          if (value > max[a]) max[a] = value
        }
      }
    }
  }
  const size = min.map((v, a) => (Number.isFinite(v) && Number.isFinite(max[a]) ? max[a] - v : 0))
  return { size, triangles, bytes: buf.length }
}

for (const file of files.filter((f) => /\.stl$/i.test(f))) {
  const { size, triangles, bytes } = bbox(file)
  const over = size.filter((v) => v > BED)
  if (over.length > 0)
    fails.push(`492 ${file} — ${size.map((v) => v.toFixed(1)).join(" × ")} mm, au-delà du plateau ${BED} mm`)
  if (triangles > MAX_TRI)
    fails.push(`493 ${file} — ${triangles} triangles, au-delà de ${MAX_TRI}`)
  else if (bytes > MAX_MB * 1024 * 1024)
    fails.push(`493 ${file} — ${Math.round(bytes / 1048576)} Mo, au-delà de ${MAX_MB} Mo`)
}

const binaries = files.filter((f) => CAD.test(f) || /\.stl$/i.test(f))
if (binaries.length > 0) {
  const rules = ["", "hardware/"].map((d) => `${d}.gitattributes`)
    .filter((f) => fs.existsSync(f))
    .map((f) => fs.readFileSync(f, "utf8"))
    .join("\n")
  const missing = new Set()
  for (const f of binaries) {
    const ext = path.extname(f).slice(1).toLowerCase()
    if (!new RegExp(`\\*\\.${ext}[^\\n]*filter=lfs`, "i").test(rules)) missing.add(ext)
  }
  for (const ext of missing) warns.push(`494 hardware — .${ext} versionné sans règle LFS`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${enclosures.length} boîtier(s) conformes`)
'
