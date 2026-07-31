#!/usr/bin/env bash
# config.sh — 303 débit hors constante · 304 chemin de périphérique en dur
#             318 commandes sigrok dispersées · 319 commande série littérale
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_SIGROK_MODULE="${DOCTOR_SIGROK_MODULE:-sigrok}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const sigrokModule = new RegExp(process.env.DOCTOR_SIGROK_MODULE, "i")

const BAUD_LITERAL = /\bbaud[_a-z]*\s*[:=]\s*[0-9][0-9_]*/i
const SHARED_CONST = /^\s*export\s+const\s+[A-Z][A-Z0-9_]*\s*(:[^=]*)?=/
const DEVICE_PATH = /["\x27`][^"\x27`]*\/dev\/(tty|serial|cu\.)[^"\x27`]*["\x27`]/
const SIGROK = /(SRPICO|sigrok)/i
const LITERAL_WRITE = /\b\w*(port|serial|device|transport|uart|pico)\w*\.write\s*\(\s*["\x27`]/i

const violations = []
let scanned = 0

for (const file of files) {
  const lines = read(file).split("\n")
  scanned += 1
  const isSigrokModule = sigrokModule.test(file)

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    const where = `${file}:${i + 1}`

    if (BAUD_LITERAL.test(code) && !SHARED_CONST.test(code))
      violations.push(`303 ${where} — débit série littéral hors constante partagée`)
    if (DEVICE_PATH.test(code))
      violations.push(`304 ${where} — chemin de périphérique en dur`)
    if (SIGROK.test(code) && !isSigrokModule)
      violations.push(`318 ${where} — protocole sigrok hors du module dédié`)
    if (LITERAL_WRITE.test(code))
      violations.push(`319 ${where} — commande série littérale`)
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: aucun réglage série en dur sur ${scanned} fichier(s)`)
'
