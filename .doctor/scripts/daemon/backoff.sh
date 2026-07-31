#!/usr/bin/env bash
# backoff.sh — 261 reprise sans délai croissant · 262 délai non bruité
#              263 délai non plafonné · 264 boucle de reprise muette
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_RETRY_NAMES="${DOCTOR_RETRY_NAMES:-(reconnect|reopen|backoff|retry|retries|reattempt)}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const retryName = new RegExp("\\b" + process.env.DOCTOR_RETRY_NAMES + "[A-Za-z]*\\b", "i")

const DELAY = /(setTimeout|delayMs|delay\s*\(|sleep\s*\(|backoff|waitMs)/i
const CAP = /(Math\.min\s*\(|max(Delay|Backoff|Wait|Interval)|MAX_[A-Z0-9_]*(DELAY|BACKOFF|WAIT|INTERVAL))/
const JITTER = /(jitter|random)/i
const TRACE = /(logger\.|\blog\s*\(|\bwarn\s*\(|\berror\s*\(|\bdebug\s*\(|emit\s*\(\s*["\x27`](error|status)["\x27`])/

const violations = []
const warnings = []
let targets = 0

for (const file of files) {
  const text = read(file)
  const lines = text.split("\n")
  const at = lines.findIndex((l) => retryName.test(l.replace(/\/\/.*$/, "")))
  if (at === -1) continue
  targets += 1
  const where = `${file}:${at + 1}`

  if (!DELAY.test(text)) violations.push(`261 ${where} — reprise sans délai croissant`)
  if (!CAP.test(text)) violations.push(`263 ${where} — délai de reprise non plafonné`)
  if (!TRACE.test(text)) violations.push(`264 ${where} — boucle de reprise sans trace`)
  if (!JITTER.test(text)) warnings.push(`262 ${where} — délai de reprise non bruité`)
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${targets} chemin(s) de reprise temporisé(s)`)
'
