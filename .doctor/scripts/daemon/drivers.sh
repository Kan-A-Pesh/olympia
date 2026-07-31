#!/usr/bin/env bash
# drivers.sh — 274 démarrage non idempotent · 275 arrêt qui ne libère pas le port
#              276 registre acceptant les doublons · 277 appareil inconnu sans trace
#              278 échec de driver avalé
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_DRIVER_FILES="${DOCTOR_DRIVER_FILES:-(driver|registry)}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const driverFile = new RegExp(process.env.DOCTOR_DRIVER_FILES, "i")

const START_BODY = /^\s*(public\s+|private\s+|async\s+|#)*start\s*\([^)]*\)\s*(:[^{;]*)?\{/
const STOP_BODY = /^\s*(public\s+|private\s+|async\s+|#)*stop\s*\([^)]*\)\s*(:[^{;]*)?\{/
const REGISTER_BODY = /^\s*(public\s+|private\s+|async\s+|#)*register\s*\([^)]*\)\s*(:[^{;]*)?\{/
const IDEMPOTENT = /#?(started|running|isStarted|isRunning|active)\b/
const UNRESOLVED = /if\s*\(\s*!\s*(driver|factory|handler|match)\w*\s*\)|(driver|factory)\w*\s*===\s*undefined/i
const TRACE = /(logger\.|\blog\s*\(|\bwarn\s*\(|\berror\s*\(|emit\s*\(\s*["\x27`])/
const RETHROW = /(\bthrow\b|reject\s*\(|\.emit\s*\(\s*["\x27`]error["\x27`])/
const CATCH = /\bcatch\s*(\([^)]*\))?\s*\{/

const violations = []
const warnings = []
let targets = 0

for (const file of files) {
  const text = read(file)
  if (!driverFile.test(file) && !/class\s+\w*Driver\b/.test(text)) continue
  targets += 1
  const lines = text.split("\n")

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    const where = `${file}:${i + 1}`

    if (START_BODY.test(code) && !IDEMPOTENT.test(text))
      warnings.push(`274 ${where} — démarrage sans garde d idempotence`)

    if (STOP_BODY.test(code) && !/\.(close|destroy|release)\s*\(/.test(text))
      violations.push(`275 ${where} — arrêt qui ne libère pas le port`)

    if (REGISTER_BODY.test(code) && /new\s+(Map|Set)\b/.test(text)) {
      if (!/\.has\s*\(/.test(text) || !/\bthrow\b/.test(text))
        violations.push(`276 ${where} — registre qui accepte les doublons`)
    }

    if (UNRESOLVED.test(code)) {
      const body = lines.slice(i, i + 5).join("\n")
      if (!TRACE.test(body)) violations.push(`277 ${where} — appareil non reconnu sans trace`)
    }

    if (CATCH.test(code)) {
      const body = lines.slice(i, i + 6).join("\n")
      if (!TRACE.test(body) && !RETHROW.test(body))
        violations.push(`278 ${where} — échec de driver avalé`)
    }
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${targets} fichier(s) de driver conformes`)
'
