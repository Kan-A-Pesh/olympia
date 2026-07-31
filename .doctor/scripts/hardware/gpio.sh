#!/usr/bin/env bash
# gpio.sh — 187 collision de GPIO · 188 plage valide · 189 pinctrl cohérent avec les nœuds
#           190 GPIO réservés · 191 pin_a obligatoire · 192 pin_a unique
#           193 codes uniques · 194 codes valides · 195 anti-rebond · 198 snippet vs dts
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

node -e '
const fs = require("node:fs")
const path = require("node:path")

const walk = (dir) => {
  const out = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) out.push(...walk(p))
    else out.push(p)
  }
  return out
}

if (!fs.existsSync("hardware")) { console.log("OK: aucun fichier matériel à inspecter"); process.exit(0) }
const files = walk("hardware")
const dts = files.filter((f) => f.endsWith(".dts"))
const snippets = files.filter((f) => f.endsWith(".snippet"))
if (dts.length === 0 && snippets.length === 0) { console.log("OK: aucun fichier matériel à inspecter"); process.exit(0) }

const violations = []
const used = new Map()

const claim = (pin, where) => {
  if (pin < 0 || pin > 27) violations.push(`188 ${where} — GPIO ${pin} hors plage 0–27`)
  if (pin === 0 || pin === 1) violations.push(`190 ${where} — GPIO ${pin} réservé à l EEPROM`)
  if (used.has(pin)) violations.push(`187 ${where} — GPIO ${pin} déjà utilisé par ${used.get(pin)}`)
  else used.set(pin, where)
}

for (const file of dts) {
  const text = fs.readFileSync(file, "utf8")

  const nodes = [...text.matchAll(/(\w[\w-]*)\s*\{([^{}]*)\}/g)]
    .filter(([, , body]) => /gpios\s*=/.test(body))

  const nodePins = []
  for (const [, name, body] of nodes) {
    const gpio = body.match(/gpios\s*=\s*<&gpio\s+(\d+)/)
    if (!gpio) continue
    const pin = Number(gpio[1])
    nodePins.push(pin)
    claim(pin, `${file}:${name}`)
    if (!/debounce-interval\s*=/.test(body))
      violations.push(`195 ${file}:${name} — aucun anti-rebond déclaré`)
    const code = body.match(/linux,code\s*=\s*<(\d+)>/)
    if (!code) violations.push(`194 ${file}:${name} — aucun linux,code`)
    else if (Number(code[1]) < 1 || Number(code[1]) > 767)
      violations.push(`194 ${file}:${name} — code ${code[1]} hors plage`)
  }

  const codes = [...text.matchAll(/linux,code\s*=\s*<(\d+)>/g)].map((m) => Number(m[1]))
  const dupCodes = codes.filter((c, i) => codes.indexOf(c) !== i)
  for (const c of new Set(dupCodes)) violations.push(`193 ${file} — code ${c} déclaré plusieurs fois`)

  const pinctrl = text.match(/brcm,pins\s*=\s*<([^>]*)>/)
  if (pinctrl) {
    const declared = pinctrl[1].trim().split(/\s+/).map(Number).sort((a, b) => a - b)
    const fromNodes = [...nodePins].sort((a, b) => a - b)
    if (declared.join(",") !== fromNodes.join(","))
      violations.push(`189 ${file} — brcm,pins [${declared}] ne correspond pas aux nœuds [${fromNodes}]`)
  } else if (nodePins.length > 0) {
    violations.push(`189 ${file} — aucun bloc brcm,pins`)
  }
}

for (const file of snippets) {
  const text = fs.readFileSync(file, "utf8")
  const seenPinA = new Set()

  for (const line of text.split("\n")) {
    if (!/^\s*dtoverlay=rotary-encoder/.test(line)) continue
    const a = line.match(/pin_a=(\d+)/)
    const b = line.match(/pin_b=(\d+)/)
    if (!a) { violations.push(`191 ${file} — ligne rotary-encoder sans pin_a: ${line.trim()}`); continue }
    if (seenPinA.has(a[1])) violations.push(`192 ${file} — pin_a=${a[1]} déclaré plusieurs fois`)
    seenPinA.add(a[1])
    claim(Number(a[1]), `${file}:pin_a`)
    if (b) claim(Number(b[1]), `${file}:pin_b`)
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${used.size} GPIO affectés sans collision`)
'
