#!/usr/bin/env bash
# streams.sh — 255 flux sans gestion d erreur · 256 flux jamais fermé
#              257 écouteur ajouté dans une boucle · 273 analyse JSON sur le chemin chaud
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_HOT_PATH="${DOCTOR_HOT_PATH:-(waveform|sample|frame|decode|render)}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const hotPath = new RegExp(process.env.DOCTOR_HOT_PATH, "i")

const OPEN = /(createReadStream|createWriteStream|createConnection|new SerialPort|net\.connect)\s*\(/
const ERROR_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`]error["\x27`]/
const CLOSER = /\.(close|destroy|end)\s*\(|pipeline\s*\(/
const LISTENER = /\.(on|once|addListener|prependListener)\s*\(/
const DATA_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`]data["\x27`]/

const strip = (line) =>
  line.replace(/\/\/.*$/, "").replace(/"[^"]*"|\x27[^\x27]*\x27|`[^`]*`/g, "\x22\x22")

const violations = []
let streams = 0

for (const file of files) {
  const text = read(file)
  const lines = text.split("\n")
  const hasError = ERROR_HANDLER.test(text) || /pipeline\s*\(/.test(text)
  const hasClose = CLOSER.test(text)

  let depth = 0
  const loops = []

  lines.forEach((line, i) => {
    const where = `${file}:${i + 1}`
    const code = strip(line)

    if (OPEN.test(code)) {
      streams += 1
      if (!hasError) violations.push(`255 ${where} — flux ouvert sans gestion de error`)
      if (!hasClose) violations.push(`256 ${where} — flux ouvert jamais fermé`)
    }

    if (loops.length > 0 && LISTENER.test(code))
      violations.push(`257 ${where} — écouteur ajouté dans une boucle`)

    if (/JSON\.parse\s*\(/.test(code) && (hotPath.test(file) || DATA_HANDLER.test(text)))
      violations.push(`273 ${where} — analyse JSON sur le chemin des données`)

    const opens = (code.match(/\{/g) || []).length
    const closes = (code.match(/\}/g) || []).length
    const isLoop = /\b(for|while)\s*\(/.test(code) || /\.(forEach|map)\s*\(/.test(code)
    if (isLoop && opens > closes) loops.push(depth)
    depth += opens - closes
    while (loops.length > 0 && depth <= loops[loops.length - 1]) loops.pop()
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${streams} flux ouvert(s) sous contrôle`)
'
