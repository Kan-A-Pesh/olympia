#!/usr/bin/env bash
# port.sh — 305 ouverture non exclusive · 306 erreur qui ne ferme pas le port
#           307 interrogation sans expiration · 315 branchement à chaud non surveillé
#           316 débranchement sans reprise · 317 écriture sans gestion de saturation
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

const OPENER = /(new\s+SerialPort\s*\(|openPort\s*\(|openSerial\w*\s*\(|SerialPort\.open\s*\()/
const EXCLUSIVE = /(lock\s*:\s*true|exclusive)/i
const ERROR_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`]error["\x27`]/
const CLOSER = /\.(close|destroy)\s*\(/
const HANDSHAKE = /(handshake|identify|probe|identity|SRPICO)/i
const TIMEOUT = /(timeout|AbortSignal|setTimeout|deadline|expire)/i
const HOTPLUG = /(udev|hotplug|usb-detection|usbDetection|watchDevices|onDeviceAdded)/i
const REOPEN = /(reopen|reconnect|retry)/i
const UNPLUG_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`](close|end|disconnect|removed)["\x27`]/
const DRAIN = /(drain|await\s|\.then\s*\(|writeAsync)/

const targets = []
for (const file of files) {
  const text = read(file)
  if (serialFile.test(file) || SERIAL_CODE.test(text)) targets.push([file, text])
}

const violations = []
const warnings = []
const watchesHotplug = targets.some(([, text]) => HOTPLUG.test(text))

for (const [file, text] of targets) {
  const lines = text.split("\n")

  if (HANDSHAKE.test(text) && !TIMEOUT.test(text))
    violations.push(`307 ${file} — interrogation d identité sans expiration`)

  if (/\.write\s*\(/.test(text) && !DRAIN.test(text))
    warnings.push(`317 ${file} — écriture série sans gestion de saturation`)

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    const where = `${file}:${i + 1}`
    if (!OPENER.test(code)) return

    if (!EXCLUSIVE.test(text)) violations.push(`305 ${where} — port ouvert sans accès exclusif`)
    if (!ERROR_HANDLER.test(text) || !CLOSER.test(text))
      violations.push(`306 ${where} — erreur de port qui ne referme rien`)
    if (!REOPEN.test(text) || !UNPLUG_HANDLER.test(text))
      violations.push(`316 ${where} — débranchement sans reprise`)
    if (!watchesHotplug) warnings.push(`315 ${where} — branchement à chaud non surveillé`)
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${targets.length} fichier(s) série conformes`)
'
