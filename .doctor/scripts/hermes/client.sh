#!/usr/bin/env bash
# client.sh — 163 Retain Handling fixé · 164 testament déclaré par tout producteur
#             165 connexion en MQTT 5 · 166 carte d identité jamais en qualité de service 0
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_MQTT_FILE="${DOCTOR_MQTT_FILE:-(mqtt|Mqtt|MQTT)}"
export DOCTOR_MQTT_VERSION="${DOCTOR_MQTT_VERSION:-5}"
export DOCTOR_IDENTITY_TOPIC="${DOCTOR_IDENTITY_TOPIC:-(identityTopic|quarantineTopic|/identity)}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const mqttRe = new RegExp(process.env.DOCTOR_MQTT_FILE)
const identityRe = new RegExp(process.env.DOCTOR_IDENTITY_TOPIC)
const version = process.env.DOCTOR_MQTT_VERSION
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
const split = (span) => {
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

  const isProducer = /\.publish(Async)?\s*\(/.test(text)

  for (const m of text.matchAll(/\b(?:mqtt\.)?connect(?:Async)?\s*\(/g)) {
    const before = text.slice(0, m.index).replace(/\s+$/, "")
    if (!/[=(,.]$|=>$|\b(await|return)$/.test(before)) continue
    const span = paren(text, m.index + m[0].length - 1)
    const at = `${file}:${lineAt(text, m.index)}`
    seen += 1

    const declared = span.match(/\bprotocolVersion\s*:\s*([0-9]+)/)
    if (!declared) fails.push(`165 ${at} — connexion sans protocolVersion, MQTT ${version} attendu`)
    else if (declared[1] !== version) fails.push(`165 ${at} — connexion en MQTT ${declared[1]}, ${version} attendu`)

    if (isProducer && !/\bwill\s*:/.test(span)) fails.push(`164 ${at} — producteur connecté sans testament`)
  }

  for (const m of text.matchAll(/\.subscribe(?:Async)?\s*\(/g)) {
    const span = paren(text, m.index + m[0].length - 1)
    const at = `${file}:${lineAt(text, m.index)}`
    seen += 1
    if (!/\b(rh|retainHandling)\s*:/.test(span)) fails.push(`163 ${at} — abonnement sans Retain Handling`)
  }

  for (const m of text.matchAll(/\.publish(?:Async)?\s*\(/g)) {
    const span = paren(text, m.index + m[0].length - 1)
    const topic = split(span)[0] || ""
    const at = `${file}:${lineAt(text, m.index)}`
    seen += 1
    if (identityRe.test(topic) && /\bqos\s*:\s*0\b/.test(span))
      fails.push(`166 ${at} — carte d identité publiée en qualité de service 0`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} appel(s) de client MQTT conformes`)
'
