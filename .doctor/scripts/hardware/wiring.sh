#!/usr/bin/env bash
# wiring.sh — 501 connecteurs précisés · 502 longueur de liaison admissible
#             504 filtre d anti-rebond par voie d encodeur
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DOCTOR_EDP_MAX_MM="${DOCTOR_EDP_MAX_MM:-300}" \
DOCTOR_HDMI_MAX_MM="${DOCTOR_HDMI_MAX_MM:-5000}" \
DOCTOR_USB_MAX_MM="${DOCTOR_USB_MAX_MM:-3000}" \
DOCTOR_I2C_MAX_MM="${DOCTOR_I2C_MAX_MM:-500}" \
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
if (!fs.existsSync("hardware")) done("aucun câblage à inspecter")
const files = walk("hardware").filter((f) => /\.(md|snippet|dts|txt|csv)$/i.test(f))
if (files.length === 0) done("aucun câblage à inspecter")

const LIMITS = [
  { name: "eDP", pattern: /\bedp\b/i, max: Number(process.env.DOCTOR_EDP_MAX_MM) },
  { name: "HDMI", pattern: /\bhdmi\b/i, max: Number(process.env.DOCTOR_HDMI_MAX_MM) },
  { name: "USB", pattern: /\busb\b/i, max: Number(process.env.DOCTOR_USB_MAX_MM) },
  { name: "I2C", pattern: /\b(i2c|iic|smbus)\b/i, max: Number(process.env.DOCTOR_I2C_MAX_MM) },
]
const LINK_TABLE = /(liaison|c[âa]ble|nappe|connect|cordon|harnais)/i
const GENDER = /(m[âa]le|femelle|male|female|plug|embase|receptacle|prise)/i
const LENGTH = /(\d+(?:[.,]\d+)?)\s*(mm|cm|m)\b/g

const fails = []
const warns = []
const texts = new Map(files.map((f) => [f, fs.readFileSync(f, "utf8")]))

const toMm = (value, unit) => {
  const n = Number(value.replace(",", "."))
  return unit === "cm" ? n * 10 : unit === "m" ? n * 1000 : n
}

for (const [file, text] of texts) {
  const lines = text.split("\n")

  lines.forEach((line, i) => {
    for (const limit of LIMITS) {
      if (!limit.pattern.test(line)) continue
      for (const m of line.matchAll(LENGTH)) {
        const mm = toMm(m[1], m[2])
        if (mm > limit.max)
          fails.push(`502 ${file}:${i + 1} — liaison ${limit.name} de ${mm} mm, au-delà de ${limit.max} mm`)
      }
    }
  })

  if (!/\.md$/i.test(file)) continue
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].trim().startsWith("|")) continue
    if (!/^\s*\|[\s|:-]+\|\s*$/.test(lines[i + 1] || "")) continue
    const header = lines[i].split("|").slice(1, -1).map((c) => c.trim())
    if (!LINK_TABLE.test(header.join(" "))) continue
    for (let r = i + 2; r < lines.length && lines[r].trim().startsWith("|"); r++) {
      const cells = lines[r].split("|").slice(1, -1).map((c) => c.trim())
      if (cells.length < 2) continue
      if (!GENDER.test(cells.join(" ")))
        warns.push(`501 ${file}:${r + 1} — ${cells[0]} sans genre de connecteur`)
    }
  }
}

let channels = 0
for (const [, text] of texts) {
  for (const line of text.split("\n")) {
    if (!/dtoverlay\s*=\s*rotary-encoder/.test(line)) continue
    channels += (line.match(/pin_[ab]\s*=/g) || []).length
  }
}

if (channels > 0) {
  const all = [...texts.values()].join("\n")
  const counted = (word) => {
    let best = 0
    for (const m of all.matchAll(new RegExp(`(\\d+)\\s*(?:x\\s*)?(?:${word})`, "gi")))
      best = Math.max(best, Number(m[1]))
    return best
  }
  const resistors = counted("r[ée]sistances?|resistors?")
  const capacitors = counted("condensateurs?|capacitors?")
  if (resistors === 0 && capacitors === 0)
    fails.push(`504 hardware — ${channels} voies d encodeur sans filtre d anti-rebond documenté`)
  else if (resistors < channels || capacitors < channels)
    fails.push(`504 hardware — ${channels} voies d encodeur pour ${resistors} résistance(s) et ${capacitors} condensateur(s)`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${channels} voie(s) d encodeur filtrées, liaisons dans les limites`)
'
