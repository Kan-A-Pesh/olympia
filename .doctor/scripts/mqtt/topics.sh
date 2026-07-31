#!/usr/bin/env bash
# topics.sh — 297 profondeur de topic bornée · 298 topic construit depuis une entrée externe
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_TOPIC_DEPTH="${DOCTOR_TOPIC_DEPTH:-6}"
export DOCTOR_TOPIC_ROOT="${DOCTOR_TOPIC_ROOT:-olympia}"
export DOCTOR_MQTT_FILE="${DOCTOR_MQTT_FILE:-(mqtt|Mqtt|MQTT)}"
export DOCTOR_UNTRUSTED="${DOCTOR_UNTRUSTED:-(req|request|params|query|body|searchParams|argv|userInput|formData)\.}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const maxDepth = Number(process.env.DOCTOR_TOPIC_DEPTH)
const root = process.env.DOCTOR_TOPIC_ROOT
const mqttRe = new RegExp(process.env.DOCTOR_MQTT_FILE)
const untrusted = new RegExp(process.env.DOCTOR_UNTRUSTED)
const fails = []
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const paren = (t, from) => {
  let d = 0
  for (let i = from; i < t.length; i++) {
    if (t[i] === "(") d++
    else if (t[i] === ")") { d--; if (d === 0) return t.slice(from, i + 1) }
  }
  return t.slice(from)
}

let seen = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }

  const consts = new Map()
  for (const m of text.matchAll(/const\s+([A-Za-z_$][\w$]*)\s*=\s*(["\x60])([^"\x60\n]*)\2/g))
    consts.set(m[1], m[3])
  const resolve = (raw) => {
    let out = raw
    for (let i = 0; i < 5; i++)
      out = out.replace(/\$\{([A-Za-z_$][\w$]*)\}/g, (all, name) => (consts.has(name) ? consts.get(name) : all))
    return out.replace(/\$\{[^}]*\}/g, "+")
  }

  for (const m of text.matchAll(/(["\x60])([^"\x60\n]*\/[^"\x60\n]*)\1/g)) {
    const value = resolve(m[2])
    if (!value.startsWith(root + "/")) continue
    seen += 1
    const depth = value.split("/").length
    if (depth > maxDepth)
      fails.push(`297 ${file}:${lineAt(text, m.index)} — topic de profondeur ${depth} (maximum ${maxDepth}): ${value}`)
  }

  if (!mqttRe.test(text)) continue
  for (const m of text.matchAll(/\.(publish|subscribe|unsubscribe)(?:Async)?\s*\(|\b\w*[Tt]opic\s*\(/g)) {
    const span = paren(text, text.indexOf("(", m.index + m[0].length - 1))
    if (untrusted.test(span))
      fails.push(`298 ${file}:${lineAt(text, m.index)} — topic construit depuis une entrée externe`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} topic(s) dans la profondeur prévue`)
'
