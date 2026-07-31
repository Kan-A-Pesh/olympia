#!/usr/bin/env bash
# publish.sh — 283 qualité de service explicite · 284 carte d identité retenue
#              285 mesures jamais retenues
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
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const paren = (t, from) => {
  let d = 0
  for (let i = from; i < t.length; i++) {
    if (t[i] === "(") d++
    else if (t[i] === ")") { d--; if (d === 0) return t.slice(from, i + 1) }
  }
  return t.slice(from)
}
const args = (span) => {
  const parts = []
  let cur = ""
  let d = 0
  for (const ch of span.slice(1, -1)) {
    if (ch === "," && d === 0) { parts.push(cur); cur = ""; continue }
    if ("([{".includes(ch)) d++
    else if (")]}".includes(ch)) d--
    cur += ch
  }
  parts.push(cur)
  return parts.map((p) => p.trim())
}

let seen = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  if (!mqttRe.test(text)) continue

  for (const m of text.matchAll(/\.publish(?:Async)?\s*\(/g)) {
    const span = paren(text, m.index + m[0].length - 1)
    const parts = args(span)
    const topic = parts[0] || ""
    const at = `${file}:${lineAt(text, m.index)}`
    seen += 1

    if (!/\bqos\s*:/.test(span)) fails.push(`283 ${at} — publication sans qualité de service explicite`)

    const retained = /\bretain\s*:\s*true/.test(span)
    if (/(identityTopic|quarantineTopic|\/identity)/.test(topic) && !retained)
      fails.push(`284 ${at} — carte d identité publiée sans retain`)
    if (/(dataTopic|\/data\/)/.test(topic) && retained)
      fails.push(`285 ${at} — mesure publiée en retenu`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} publication(s) MQTT conformes`)
'
