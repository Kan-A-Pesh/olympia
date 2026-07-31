#!/usr/bin/env bash
# power.sh — 498 tension déclarée par rail · 499 budget de courant calculé
#            500 marge de régulateur · 503 zone secteur signalée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DOCTOR_REGULATOR_MARGIN="${DOCTOR_REGULATOR_MARGIN:-1.3}" \
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
if (!fs.existsSync("hardware")) done("aucun plan d alimentation à inspecter")
const docs = walk("hardware").filter((f) => /\.md$/i.test(f))
if (docs.length === 0) done("aucun plan d alimentation à inspecter")

const MARGIN = Number(process.env.DOCTOR_REGULATOR_MARGIN)
const fails = []

const RAIL_TABLE = /(rail|tension|voltage|aliment)/i
const VOLTAGE = /\d+(?:[.,]\d+)?\s*V\b/
const CURRENT = /(\d+(?:[.,]\d+)?)\s*(m?)A\b/g
const CAPACITY = /(capacit|nominal|calibr|rating|fourni|d[ée]bit)/i
const LOAD = /(pointe|pic|cr[êe]te|peak|charge|conso|demand)/i
const MAINS = /(230\s*V|240\s*V|110\s*V|secteur|mains|IEC\s*C\d|LRS-\d+|prise murale)/i
const ISOLATION = /(isolation|isol[ée]|danger|barri[èe]re|creepage|clearance|entrefer|terre de protection|capot[ée]|s[ée]par[ée])/i
const TOTAL = /(budget|total|consommation|somme|cumul)[^\n]{0,60}\d+(?:[.,]\d+)?\s*m?A\b/i

const amps = (cell) => {
  const out = []
  for (const m of cell.matchAll(CURRENT)) out.push(Number(m[1].replace(",", ".")) / (m[2] ? 1000 : 1))
  return out
}

let railCount = 0

for (const doc of docs) {
  const lines = fs.readFileSync(doc, "utf8").split("\n")
  const text = lines.join("\n")
  let hasRailTable = false

  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].trim().startsWith("|")) continue
    if (!/^\s*\|[\s|:-]+\|\s*$/.test(lines[i + 1] || "")) continue
    const header = lines[i].split("|").slice(1, -1).map((c) => c.trim())
    if (!RAIL_TABLE.test(header.join(" "))) continue
    hasRailTable = true

    const capacityAt = header.findIndex((c) => CAPACITY.test(c))
    const loadAt = header.findIndex((c) => LOAD.test(c))

    for (let r = i + 2; r < lines.length && lines[r].trim().startsWith("|"); r++) {
      const cells = lines[r].split("|").slice(1, -1).map((c) => c.trim())
      if (cells.length < 2) continue
      railCount++
      const where = `${doc}:${r + 1}`
      const row = cells.join(" ")

      if (!VOLTAGE.test(row)) fails.push(`498 ${where} — ${cells[0]} sans tension déclarée`)

      if (capacityAt >= 0 && loadAt >= 0) {
        const capacity = amps(cells[capacityAt] || "")[0]
        const load = amps(cells[loadAt] || "")[0]
        if (capacity !== undefined && load !== undefined && capacity < load * MARGIN)
          fails.push(`500 ${where} — ${cells[0]} fournit ${capacity} A pour ${load} A demandés, marge ${MARGIN} attendue`)
      } else if (amps(row).length > 0 && !LOAD.test(row) && !/marge|margin/i.test(row)) {
        fails.push(`500 ${where} — ${cells[0]} sans marge sur le pic`)
      }
    }
  }

  if (hasRailTable && !TOTAL.test(text))
    fails.push(`499 ${doc} — aucun budget de courant total`)

  if (MAINS.test(text) && !ISOLATION.test(text))
    fails.push(`503 ${doc} — tension secteur sans mention d isolation`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${railCount} rail(s) documentés`)
'
