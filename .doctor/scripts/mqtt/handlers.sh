#!/usr/bin/env bash
# handlers.sh — 295 charge utile bornée avant décodage · 296 republication synchrone
#               302 gestionnaire total
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_MQTT_FILE="${DOCTOR_MQTT_FILE:-(mqtt|Mqtt|MQTT)}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const mqttRe = new RegExp(process.env.DOCTOR_MQTT_FILE)
const fails = []
const warns = []
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const paren = (t, from) => {
  let d = 0
  for (let i = from; i < t.length; i++) {
    if (t[i] === "(") d++
    else if (t[i] === ")") { d--; if (d === 0) return t.slice(from, i + 1) }
  }
  return t.slice(from)
}
const block = (t, from) => {
  const start = t.indexOf("{", from)
  if (start < 0) return ""
  let d = 0
  for (let i = start; i < t.length; i++) {
    if (t[i] === "{") d++
    else if (t[i] === "}") { d--; if (d === 0) return t.slice(start, i + 1) }
  }
  return t.slice(start)
}

let seen = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  if (!mqttRe.test(text)) continue

  const handlers = []
  for (const m of text.matchAll(/\.on\w*\(\s*["\x60\x27]message["\x60\x27]/g)) {
    const span = paren(text, text.indexOf("(", m.index))
    const arrow = span.indexOf("=>")
    if (arrow < 0) continue
    handlers.push([m.index, block(text, text.indexOf("(", m.index) + arrow)])
  }
  for (const m of text.matchAll(/\b(?:function|const|let)\s+\w*(?:[Mm]essage[Hh]andler|(?:on|handle)\w*Message)\w*\b/g))
    handlers.push([m.index, block(text, m.index)])

  for (const [index, body] of handlers) {
    if (!body) continue
    const at = `${file}:${lineAt(text, index)}`
    seen += 1

    if (!/(byteLength|\.length)\s*(>=|<=|>|<|===)/.test(body) && !/MAX_(PAYLOAD|MESSAGE|FRAME)/.test(body))
      fails.push(`295 ${at} — charge utile décodée sans borne de taille`)
    if (/\.publish(Async)?\s*\(/.test(body))
      warns.push(`296 ${at} — republication synchrone depuis un gestionnaire de message`)
    if (/\bswitch\s*\(/.test(body) && !/\bdefault\s*:/.test(body))
      fails.push(`302 ${at} — aiguillage sans cas par défaut`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} gestionnaire(s) de message conformes`)
'
