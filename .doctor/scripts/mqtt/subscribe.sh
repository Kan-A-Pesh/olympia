#!/usr/bin/env bash
# subscribe.sh — 281 joker à la racine · 282 filtres issus des constantes
#                300 résiliation à l arrêt · 301 filtre souscrit deux fois
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
const split = (text) => {
  const parts = []
  let cur = ""
  let d = 0
  for (const ch of text) {
    if (ch === "," && d === 0) { parts.push(cur); cur = ""; continue }
    if ("([{".includes(ch)) d++
    else if (")]}".includes(ch)) d--
    cur += ch
  }
  parts.push(cur)
  return parts.map((p) => p.trim()).filter(Boolean)
}

const filters = new Map()
let seen = 0

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  if (!mqttRe.test(text)) continue

  let subscribes = 0
  for (const m of text.matchAll(/\.subscribe(?:Async)?\s*\(/g)) {
    const span = paren(text, m.index + m[0].length - 1)
    const first = split(span.slice(1, -1))[0] || ""
    const at = `${file}:${lineAt(text, m.index)}`
    subscribes += 1
    seen += 1

    const list = first.startsWith("[") ? split(first.slice(1, -1)) : [first]
    for (const filter of list) {
      const literal = filter.match(/^["\x60\x27]([^"\x60\x27]*)["\x60\x27]$/)
      if (literal && /^[#+]/.test(literal[1])) {
        fails.push(`281 ${at} — abonnement au joker de racine "${literal[1]}"`)
      } else if (/["\x60\x27]/.test(filter)) {
        fails.push(`282 ${at} — filtre littéral ${filter}, constante partagée attendue`)
      }
      const key = filter.replace(/\s+/g, "")
      if (!key) continue
      if (filters.has(key)) fails.push(`301 ${at} — filtre ${key} déjà souscrit en ${filters.get(key)}`)
      else filters.set(key, at)
    }
  }

  if (subscribes > 0 && !/\.(unsubscribe|end)(Async)?\s*\(/.test(text))
    fails.push(`300 ${file} — abonnements jamais résiliés`)
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} abonnement(s) MQTT conformes`)
'
