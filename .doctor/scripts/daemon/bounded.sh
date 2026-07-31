#!/usr/bin/env bash
# bounded.sh — 265 file non bornée · 266 flux rapide sans contre-pression · 267 tampon circulaire
#              268 table sans purge · 269 appareil jamais retiré · 270 réglages non persistés
#              271 écritures de réglages non regroupées
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_QUEUE_NAMES="${DOCTOR_QUEUE_NAMES:-(queue|backlog|outbox|inbox|pending|batch)}" \
DOCTOR_TABLE_NAMES="${DOCTOR_TABLE_NAMES:-(session|client|subscription|cache|entries|seen|inflight)}" \
DOCTOR_DEVICE_NAMES="${DOCTOR_DEVICE_NAMES:-(device|port|handle|peer)}" \
DOCTOR_SETTINGS_FILES="${DOCTOR_SETTINGS_FILES:-(settings|preferences)}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const named = (env, tail) => new RegExp("\\b" + process.env[env] + "[A-Za-z]*\\s*" + tail, "i")

const QUEUE_DECL = named("DOCTOR_QUEUE_NAMES", "(<[^>]*>)?\\s*(:[^=;]*)?=\\s*\\[\\s*\\]")
const TABLE_DECL = named("DOCTOR_TABLE_NAMES", "(:[^=;]*)?=\\s*new\\s+(Map|Set)\\b")
const DEVICE_DECL = named("DOCTOR_DEVICE_NAMES", "(:[^=;]*)?=\\s*new\\s+(Map|Set)\\b")
const RING_DECL = /\b\w*(ring|circular)[A-Za-z]*\s*(:[^=;]*)?=\s*\[\s*\]/i
const RING_PUSH = /\b\w*(ring|circular)[A-Za-z]*\.push\s*\(/i
const settingsFile = new RegExp(process.env.DOCTOR_SETTINGS_FILES, "i")

const BOUND = /(\.length\s*(>=|>)|\.size\s*(>=|>)|MAX_[A-Z0-9_]+|max(Size|Length|Entries|Items|Devices))/
const PRUNE = /\.(delete|clear|shift|evict)\s*\(/
const BACKPRESSURE = /(\.pause\s*\(|\.resume\s*\(|drain|highWaterMark|needDrain|pipeline\s*\()/
const DATA_HANDLER = /\.(on|once|addListener)\s*\(\s*["\x27`]data["\x27`]/
const PERSIST = /(save|persist|writeFile|flush|commit)/i
const DEBOUNCE = /(debounce|throttle|coalesce)/i

const violations = []
let bounded = 0

for (const file of files) {
  const text = read(file)
  const lines = text.split("\n")
  const isSettings = settingsFile.test(file)

  if (isSettings) {
    if (!PERSIST.test(text)) violations.push(`270 ${file} — changement de réglage jamais écrit`)
    if (!DEBOUNCE.test(text) && !(/setTimeout\s*\(/.test(text) && /clearTimeout\s*\(/.test(text)))
      violations.push(`271 ${file} — écritures de réglages non regroupées`)
  }

  if (DATA_HANDLER.test(text) && /\.write\s*\(/.test(text) && !BACKPRESSURE.test(text))
    violations.push(`266 ${file} — flux rapide sans contre-pression`)

  lines.forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "")
    const where = `${file}:${i + 1}`

    if (QUEUE_DECL.test(code)) {
      bounded += 1
      if (!BOUND.test(text)) violations.push(`265 ${where} — file sans taille maximale`)
    }
    if (RING_DECL.test(code) || RING_PUSH.test(code)) {
      bounded += 1
      violations.push(`267 ${where} — tampon circulaire non préalloué`)
    }
    if (TABLE_DECL.test(code)) {
      bounded += 1
      if (!PRUNE.test(text) && !BOUND.test(text))
        violations.push(`268 ${where} — table indexée sans purge ni plafond`)
    }
    if (DEVICE_DECL.test(code)) {
      bounded += 1
      if (!PRUNE.test(text))
        violations.push(`269 ${where} — aucune déconnexion ne retire l appareil`)
    }
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${bounded} structure(s) bornée(s)`)
'
