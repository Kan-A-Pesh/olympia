#!/usr/bin/env bash
# device.sh — 320 débit d échantillonnage reçu non borné
#             322 appareil USB non marqué comme non authentifié
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

const SAMPLE_RATE = /\bsample[_]?rate\w*/i
const RATE_BOUND = /(Math\.min\s*\(|clamp|MAX_SAMPLE|maxSampleRate|MIN_SAMPLE|safeParse|\.parse\s*\()/
const USB_TRANSPORT = /transport\s*:\s*["\x27`]usb["\x27`]\s*[,}]/
const UNAUTHENTICATED = /isAuthenticated\s*:\s*false/

const violations = []
let targets = 0

for (const file of files) {
  const text = read(file)
  const lines = text.split("\n")

  if (serialFile.test(file) || SERIAL_CODE.test(text)) {
    targets += 1
    if (SAMPLE_RATE.test(text) && !RATE_BOUND.test(text))
      violations.push(`320 ${file} — débit d échantillonnage reçu non borné`)
  }

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    if (!USB_TRANSPORT.test(code)) return
    const window = lines.slice(Math.max(0, i - 3), i + 4).join("\n")
    if (!UNAUTHENTICATED.test(window))
      violations.push(`322 ${file}:${i + 1} — appareil USB non marqué comme non authentifié`)
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${targets} appareil(s) série déclarés sans confiance implicite`)
'
