#!/usr/bin/env bash
# framing.sh — 308 signature non validée · 309 trame coupée non gérée · 310 parseur sans état
#              311 flux binaire converti en chaîne · 312 encodage de lecture implicite
#              313 trame sans taille maximale · 314 tampon d assemblage non plafonné
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_SERIAL_FILES="${DOCTOR_SERIAL_FILES:-(serial|sigrok|uart|tty|usb|pico)}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const serialFile = new RegExp(process.env.DOCTOR_SERIAL_FILES, "i")
const SERIAL_CODE = /(from\s+["\x27]serialport["\x27]|new\s+SerialPort\b|\/dev\/tty)/

const DATA_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`]data["\x27`]/
const IDENTITY = /(SRPICO|handshake|identify|signature)/i
const VALIDATED = /(startsWith|\.test\s*\(|\.match\s*\(|safeParse|\.parse\s*\(|===\s*["\x27`])/
const PARSER_CLASS = /class\s+\w*Parser\b/
const LEFTOVER = /#?(pending|remainder|rest|carry|leftover)\b/
const BINARY_STRING = /["\x27`]\s*\+\s*(chunk|data|buf|buffer|frame)\b|\b(chunk|data|buf|buffer|frame)\s*\+\s*["\x27`]|\$\{\s*(chunk|buf|buffer|frame)\s*\}/
const IMPLICIT_ENCODING = /\.toString\s*\(\s*\)/
const FRAME_CAP = /(MAX_FRAME|maxFrame|MAX_[A-Z0-9_]*(BYTES|LEN|LENGTH|SIZE)|max(Bytes|Length|Size))/
const CONCAT = /(Buffer\.concat\s*\(|\.concat\s*\(|\+=\s*chunk\b)/
const LENGTH_GUARD = /\.length\s*(>=|>|<=|<)/

const violations = []
let targets = 0

for (const file of files) {
  const text = read(file)
  if (!serialFile.test(file) && !SERIAL_CODE.test(text)) continue
  targets += 1
  const lines = text.split("\n")

  if (IDENTITY.test(text) && !VALIDATED.test(text))
    violations.push(`308 ${file} — signature reçue utilisée sans validation`)

  if (DATA_HANDLER.test(text)) {
    if (!PARSER_CLASS.test(text)) violations.push(`310 ${file} — parseur sans état de classe`)
    if (!LEFTOVER.test(text)) violations.push(`309 ${file} — trames coupées non gérées`)
  }

  if (/\bframe\b/i.test(text) && !FRAME_CAP.test(text))
    violations.push(`313 ${file} — trame sans taille maximale`)

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    const where = `${file}:${i + 1}`

    if (BINARY_STRING.test(code)) violations.push(`311 ${where} — flux binaire converti en chaîne`)
    if (IMPLICIT_ENCODING.test(code)) violations.push(`312 ${where} — encodage de lecture implicite`)
    if (CONCAT.test(code) && !LENGTH_GUARD.test(text) && !FRAME_CAP.test(text))
      violations.push(`314 ${where} — tampon d assemblage non plafonné`)
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${targets} parseur(s) de trames bornés`)
'
