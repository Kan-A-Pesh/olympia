#!/usr/bin/env bash
# plan.sh — 196 plan GPIO documenté ↔ .dts · 197 codes du .dts ↔ table du daemon
#           199 broche à fonction alternative · 200 .stl sans fichier source
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SOURCES=$("$DOCTOR_DIR/utils/list-files.sh" src)

DOCTOR_SOURCE_FILES="$SOURCES" \
DOCTOR_PANEL_FILE="${DOCTOR_PANEL_FILE:-(^|/)input/panel\.ts$}" \
node -e '
const fs = require("node:fs")
const path = require("node:path")

const done = (msg) => { console.log(`OK: ${msg}`); process.exit(0) }
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const walk = (dir) => {
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(p))
    else out.push(p)
  }
  return out
}

if (!fs.existsSync("hardware")) done("aucun fichier matériel à inspecter")
const files = walk("hardware")
const dtsFiles = files.filter((f) => f.endsWith(".dts"))
const snippets = files.filter((f) => f.endsWith(".snippet"))
if (dtsFiles.length === 0 && snippets.length === 0) done("aucun fichier matériel à inspecter")

const PAD = ["nw", "n", "ne", "w", "e", "sw", "s", "se"]
const KEYPAD = { nw: 71, n: 72, ne: 73, w: 75, e: 77, sw: 79, s: 80, se: 81 }
const FROM_ROSE = { NO: "nw", N: "n", NE: "ne", O: "w", E: "e", SO: "sw", S: "s", SE: "se" }

const fails = []
const warns = []

const padNodes = new Map()
const encNodes = new Map()
for (const file of dtsFiles) {
  const text = read(file)
  for (const match of text.matchAll(/key-([\w-]+)\s*\{([^{}]*)\}/g)) {
    const gpio = match[2].match(/gpios\s*=\s*<&gpio\s+(\d+)/)
    const code = match[2].match(/linux,code\s*=\s*<(\d+)>/)
    if (!gpio || !code) continue
    const entry = { file, pin: Number(gpio[1]), code: Number(code[1]) }
    if (PAD.includes(match[1])) padNodes.set(match[1], entry)
    const encoder = match[1].match(/^enc(\d+)$/)
    if (encoder) encNodes.set(Number(encoder[1]), entry)
  }
}

const overlays = []
const overlayLines = new Set()
for (const file of snippets) {
  for (const line of read(file).split("\n")) {
    const trimmed = line.trim()
    if (!/^dtoverlay=rotary-encoder/.test(trimmed)) continue
    overlayLines.add(trimmed)
    const a = trimmed.match(/pin_a=(\d+)/)
    const b = trimmed.match(/pin_b=(\d+)/)
    if (a) overlays.push({ file, a: Number(a[1]), b: b ? Number(b[1]) : null })
  }
}

const plan = { file: null, encoders: new Map(), pad: new Map(), total: null }
for (const file of snippets) {
  let inPad = false
  for (const line of read(file).split("\n")) {
    const encoder = line.match(/^#\s+encodeur\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/i)
    if (encoder) {
      plan.file = file
      plan.encoders.set(Number(encoder[1]), { a: Number(encoder[2]), b: Number(encoder[3]), push: Number(encoder[4]) })
      continue
    }
    if (/^#.*[Pp]av[eé] directionnel/.test(line)) inPad = true
    if (inPad && /^#/.test(line)) {
      let hit = false
      for (const m of line.matchAll(/\b(NO|NE|SO|SE|N|S|E|O)\s+(\d+)\b/g)) {
        plan.file = file
        plan.pad.set(FROM_ROSE[m[1]], Number(m[2]))
        hit = true
      }
      if (!hit && plan.pad.size > 0) inPad = false
    }
    const total = line.match(/^#\s*(\d+)\s+GPIO au total/i)
    if (total) plan.total = Number(total[1])
  }
}

if (plan.encoders.size > 0 || plan.pad.size > 0) {
  for (const [index, encoder] of plan.encoders) {
    const overlay = overlays.find((o) => o.a === encoder.a)
    if (!overlay) fails.push(`196 ${plan.file} — encodeur ${index}: aucune ligne rotary-encoder avec pin_a=${encoder.a}`)
    else if (overlay.b !== encoder.b)
      fails.push(`196 ${overlay.file} — encodeur ${index}: pin_b=${overlay.b} dans la ligne dtoverlay, ${encoder.b} dans le plan`)
    if (encNodes.size === 0) continue
    const node = encNodes.get(index)
    if (!node) fails.push(`196 ${plan.file} — aucun noeud key-enc${index} dans le device tree`)
    else if (node.pin !== encoder.push)
      fails.push(`196 ${node.file} — key-enc${index} sur GPIO ${node.pin}, ${encoder.push} dans le plan`)
  }

  if (padNodes.size > 0) {
    for (const [direction, pin] of plan.pad) {
      const node = padNodes.get(direction)
      if (!node) { fails.push(`196 ${plan.file} — aucun noeud key-${direction} dans le device tree`); continue }
      if (node.pin !== pin) fails.push(`196 ${node.file} — key-${direction} sur GPIO ${node.pin}, ${pin} dans le plan`)
      if (node.code !== KEYPAD[direction])
        fails.push(`196 ${node.file} — key-${direction} en code ${node.code}, pavé numérique ${KEYPAD[direction]}`)
    }
    if (plan.pad.size > 0)
      for (const direction of padNodes.keys())
        if (!plan.pad.has(direction)) fails.push(`196 ${plan.file} — key-${direction} absent du plan documenté`)
  }

  if (plan.total !== null) {
    const pins = new Set()
    for (const encoder of plan.encoders.values()) { pins.add(encoder.a); pins.add(encoder.b); pins.add(encoder.push) }
    for (const pin of plan.pad.values()) pins.add(pin)
    if (pins.size !== plan.total)
      fails.push(`196 ${plan.file} — ${plan.total} GPIO annoncés, ${pins.size} affectés par le plan`)
  }
}

if (fs.existsSync("docs") && overlayLines.size > 0) {
  const documented = new Map()
  for (const file of walk("docs").filter((f) => f.endsWith(".md")))
    for (const line of read(file).split("\n")) {
      const trimmed = line.trim()
      if (/^dtoverlay=rotary-encoder/.test(trimmed)) documented.set(trimmed, file)
    }
  if (documented.size > 0) {
    for (const [line, file] of documented)
      if (!overlayLines.has(line)) fails.push(`196 ${file} — "${line}" absent du snippet de configuration`)
    for (const line of overlayLines)
      if (!documented.has(line)) fails.push(`196 ${[...snippets][0]} — "${line}" absent de la documentation`)
  }
}

const panelFiles = (process.env.DOCTOR_SOURCE_FILES || "").split("\n")
  .filter(Boolean)
  .filter((f) => new RegExp(process.env.DOCTOR_PANEL_FILE).test(f))

for (const file of panelFiles) {
  if (padNodes.size === 0 && encNodes.size === 0) break
  const text = read(file)

  const directions = text.match(/directions\s*:\s*\{([^}]*)\}/)
  if (directions) {
    const table = new Map()
    for (const m of directions[1].matchAll(/(\d+)\s*:\s*["\x27]([a-z]+)["\x27]/g)) table.set(Number(m[1]), m[2])
    for (const [direction, node] of padNodes) {
      const mapped = table.get(node.code)
      if (mapped === undefined) fails.push(`197 ${file} — code ${node.code} (key-${direction}) absent de la table directions`)
      else if (mapped !== direction)
        fails.push(`197 ${file} — code ${node.code} lu comme "${mapped}", key-${direction} dans le device tree`)
    }
    for (const [code, direction] of table)
      if (![...padNodes.values()].some((n) => n.code === code))
        fails.push(`197 ${file} — code ${code} ("${direction}") sans noeud correspondant dans le device tree`)
  } else if (padNodes.size > 0) {
    fails.push(`197 ${file} — aucune table directions face aux ${padNodes.size} touches du device tree`)
  }

  const pushes = text.match(/pushes\s*:\s*\{([^}]*)\}/)
  if (pushes && encNodes.size > 0) {
    const table = new Map()
    for (const m of pushes[1].matchAll(/(\d+)\s*:\s*(\d+)/g)) table.set(Number(m[1]), Number(m[2]))
    for (const [index, node] of encNodes) {
      const mapped = table.get(node.code)
      if (mapped === undefined) fails.push(`197 ${file} — code ${node.code} (key-enc${index}) absent de la table pushes`)
      else if (mapped !== index - 1)
        fails.push(`197 ${file} — code ${node.code} rangé en position ${mapped}, key-enc${index} attend ${index - 1}`)
    }
    for (const code of table.keys())
      if (![...encNodes.values()].some((n) => n.code === code))
        fails.push(`197 ${file} — code ${code} sans poussoir correspondant dans le device tree`)
  } else if (encNodes.size > 0) {
    fails.push(`197 ${file} — aucune table pushes face aux ${encNodes.size} poussoirs du device tree`)
  }

  const list = text.match(/DIRECTIONS\s*=\s*\[([^\]]*)\]/)
  if (list && padNodes.size > 0) {
    const declared = [...list[1].matchAll(/["\x27]([a-z]+)["\x27]/g)].map((m) => m[1])
    for (const direction of padNodes.keys())
      if (!declared.includes(direction)) fails.push(`197 ${file} — direction "${direction}" du device tree absente de DIRECTIONS`)
    for (const direction of declared)
      if (!padNodes.has(direction)) fails.push(`197 ${file} — direction "${direction}" sans touche dans le device tree`)
  }

  const encoders = text.match(/encoders\s*:\s*\[([^\]]*)\]/)
  if (encoders && overlays.length > 0) {
    const opened = [...encoders[1].matchAll(/rotary@(\d+)/g)].map((m) => Number(m[1]))
    if (opened.length > 0) {
      const declared = overlays.map((o) => o.a)
      if (opened.length !== declared.length)
        fails.push(`197 ${file} — ${opened.length} encodeur(s) ouverts, ${declared.length} ligne(s) rotary-encoder`)
      for (let i = 0; i < Math.min(opened.length, declared.length); i += 1)
        if (opened[i] !== declared[i])
          fails.push(`197 ${file} — encodeur ${i + 1} ouvert sur rotary@${opened[i]}, pin_a=${declared[i]} dans la configuration`)
    }
  }
}

const claimed = new Map()
for (const [direction, node] of padNodes) claimed.set(node.pin, `key-${direction}`)
for (const [index, node] of encNodes) claimed.set(node.pin, `key-enc${index}`)
for (const overlay of overlays) {
  claimed.set(overlay.a, "rotary-encoder pin_a")
  if (overlay.b !== null) claimed.set(overlay.b, "rotary-encoder pin_b")
}

const configText = snippets.map(read).join("\n")
const PERIPHERALS = [
  { name: "SPI0", enabled: /^\s*dtparam=spi=on/m, pins: [7, 8, 9, 10, 11] },
  { name: "SPI1", enabled: /^\s*dtoverlay=spi1-/m, pins: [16, 17, 18, 19, 20, 21] },
  { name: "I2C1", enabled: /^\s*dtparam=i2c(_arm)?=on/m, pins: [2, 3] },
  { name: "I2S", enabled: /^\s*dtparam=i2s=on/m, pins: [18, 19, 20, 21] },
  { name: "UART0", enabled: /^\s*(enable_uart=1|dtoverlay=(uart[0-9]|miniuart-bt))/m, pins: [14, 15] },
]
for (const peripheral of PERIPHERALS) {
  if (!peripheral.enabled.test(configText)) continue
  for (const pin of peripheral.pins)
    if (claimed.has(pin))
      warns.push(`199 GPIO ${pin} (${claimed.get(pin)}) porte ${peripheral.name}, activé dans la configuration`)
}
for (const pin of [14, 15]) {
  if (!claimed.has(pin) || /enable_uart=0/.test(configText)) continue
  warns.push(`199 GPIO ${pin} (${claimed.get(pin)}) sert la console série par défaut, aucun enable_uart=0 déclaré`)
}

const DESIGN = /\.(f3d|step|stp|scad|fcstd|ipt|sldprt|blend|3mf|dxf|svg)$/i
const meshes = files.filter((f) => /\.stl$/i.test(f))
for (const mesh of meshes) {
  const enclosure = mesh.split(path.sep).slice(0, 2).join(path.sep)
  const stem = path.basename(mesh).replace(/\.stl$/i, "")
  const designs = files.filter((f) => f.startsWith(enclosure + path.sep) && DESIGN.test(f))
  if (designs.some((f) => path.basename(f).replace(DESIGN, "") === stem)) continue
  if (designs.length > 0) continue
  warns.push(`200 ${mesh} — aucun fichier source de conception dans ${enclosure}`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const w of warns) console.log(`WARN: ${w}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length > 0) console.log(`OK: plan GPIO cohérent (${warns.length} avertissement(s))`)
else console.log(`OK: ${claimed.size} GPIO du plan, du device tree et du daemon concordent`)
'
