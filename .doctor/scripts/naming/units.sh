#!/usr/bin/env bash
# units.sh — 408 toute grandeur porte son unité · 409 aucune durée sans unité
#
# Les fichiers de schéma sont exclus : leurs noms décrivent un format JSON partagé avec des
# firmwares C, ils ne suivent pas les conventions TypeScript.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SCHEMA_FILES="${DOCTOR_SCHEMA_FILES:-identity.ts}"
FILES=$("$DOCTOR_DIR/utils/list-files.sh" src | grep -vE "/($SCHEMA_FILES)$" || true)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_TIME_ROOTS="${DOCTOR_TIME_ROOTS:-timeout|delay|interval|duration|elapsed|period|ttl|lifetime|latency|backoff|debounce|throttle|uptime|cooldown|timespan}" \
DOCTOR_QUANTITY_ROOTS="${DOCTOR_QUANTITY_ROOTS:-rate|frequency|freq|voltage|amplitude|temperature|resistance|capacitance|inductance|bandwidth|distance|speed|velocity|pressure|humidity|angle|energy|gain}" \
DOCTOR_UNITS="${DOCTOR_UNITS:-ms|msec|msecs|millis|milliseconds|s|sec|secs|second|seconds|us|usec|micros|ns|nanos|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|hz|khz|mhz|ghz|v|mv|kv|volt|volts|a|ma|amp|amps|ohm|ohms|kohm|celsius|kelvin|fahrenheit|percent|pct|ratio|db|dbm|bps|kbps|mbps|byte|bytes|bit|bits|px|pixels|deg|degrees|rad|radians|m|mm|cm|km|meters|count|per}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const timeRoots = new Set(process.env.DOCTOR_TIME_ROOTS.split("|"))
const quantityRoots = new Set(process.env.DOCTOR_QUANTITY_ROOTS.split("|"))
const units = new Set(process.env.DOCTOR_UNITS.split("|"))
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const wordsOf = (name) => name
  .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
  .replace(/[_#$]/g, " ")
  .toLowerCase()
  .split(/\s+/)
  .filter(Boolean)

const DECL = /(?:^|[^A-Za-z0-9_$.])(?:const|let|var|readonly|function)[ \t]+(#?[A-Za-z0-9_$]+)/g
const ANNOTATED = /(?:^|[^A-Za-z0-9_$."\x27])([A-Za-z_$][A-Za-z0-9_$]*)[ \t]*\??[ \t]*:[ \t]*[A-Za-z0-9_$({[]/g

const violations = []
let named = 0

for (const file of files) {
  const text = strip(read(file))
  const lines = text.split("\n")
  const reported = new Set()

  lines.forEach((line, index) => {
    for (const pattern of [DECL, ANNOTATED]) {
      let match
      pattern.lastIndex = 0
      while ((match = pattern.exec(line)) !== null) {
        const name = match[1]
        const words = wordsOf(name)
        if (words.length === 0) continue
        named += 1
        if (words.some((w) => units.has(w))) continue
        const time = words.find((w) => timeRoots.has(w))
        const quantity = words.find((w) => quantityRoots.has(w))
        if (!time && !quantity) continue
        const key = `${index}:${name}`
        if (reported.has(key)) continue
        reported.add(key)
        if (time) violations.push(`409 ${file}:${index + 1} — "${name}" est une durée sans unité (ex. ${time}Ms)`)
        else violations.push(`408 ${file}:${index + 1} — "${name}" est une grandeur sans unité (ex. ${quantity}Hz)`)
      }
    }
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${named} identifiant(s) inspecté(s), toute grandeur porte son unité`)
'
