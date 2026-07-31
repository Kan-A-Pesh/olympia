#!/usr/bin/env bash
# migrations.sh — 329 migration numérotée · 331 migration réversible
#                 340 aucune mesure stockée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)
MIGRATIONS=$(printf '%s\n' "$ALL" | grep -E '(^|/)migrations/.*\.(sql|ts)$' | grep -vE '\.test\.ts$' || true)
SCHEMA=$(printf '%s\n' "$ALL" | grep -E '\.(sql|ts)$' || true)
[[ -z "$SCHEMA" ]] && { echo "OK: aucun schéma à inspecter"; exit 0; }

export DOCTOR_MIGRATIONS="$MIGRATIONS"
export DOCTOR_SCHEMA="$SCHEMA"
export DOCTOR_MEASUREMENT_TABLES="${DOCTOR_MEASUREMENT_TABLES:-(measure|sample|reading|waveform|history|datapoint|series|frame|trace)}"

node -e '
const fs = require("node:fs")
const migrations = (process.env.DOCTOR_MIGRATIONS || "").split("\n").filter(Boolean)
const schema = (process.env.DOCTOR_SCHEMA || "").split("\n").filter(Boolean)
const measureRe = new RegExp(process.env.DOCTOR_MEASUREMENT_TABLES, "i")
const fails = []
const warns = []
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch (e) { return "" } }

for (const file of migrations) {
  const base = file.split("/").pop()
  if (/^(index|migrate|runner|types)\./.test(base)) continue
  if (!/^[0-9]{3,}[-_.]/.test(base))
    fails.push(`329 ${file} — migration sans numéro de version en préfixe`)

  const text = read(file)
  const paired = migrations.some((other) => other !== file && other.includes(base.split(".")[0]) && /down/i.test(other))
  if (!paired && !/(--\s*down|export\s+const\s+down|function\s+down|\bdown\s*:)/i.test(text))
    warns.push(`331 ${file} — migration sans inverse`)
}

for (const file of schema) {
  const text = read(file)
  if (!/CREATE\s+TABLE/i.test(text)) continue
  for (const m of text.matchAll(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["\x60\x27]?(\w+)/gi)) {
    if (measureRe.test(m[1]))
      fails.push(`340 ${file} — table de mesures "${m[1]}", seuls les réglages sont persistés`)
  }
  for (const m of text.matchAll(/\bBLOB\b/gi))
    fails.push(`340 ${file} — colonne BLOB, aucune mesure ne doit être stockée`)
}

for (const v of fails) console.log("FAIL: " + v)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${migrations.length} migration(s) conformes`)
'
