#!/usr/bin/env bash
# messages.sh — 158 message entrant validé par un schéma · 162 charge utile vide traitée
#               169 lecture binaire précédée d une vérification de longueur
#
# 169 raisonne par fichier : un décodeur qui borne sa trame ailleurs que dans la fonction
# de lecture reste conforme, seule l absence totale de contrôle de longueur est signalée.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_MQTT_FILE="${DOCTOR_MQTT_FILE:-(mqtt|Mqtt|MQTT)}"
export DOCTOR_SCHEMA_CALL="${DOCTOR_SCHEMA_CALL:-\\.(safeParse|parse)\\s*\\(|decode[A-Z]\\w*\\s*\\(}"
export DOCTOR_BINARY_READ="${DOCTOR_BINARY_READ:-\\.(get(Uint|Int|Float|Big)\\w*|read(U|)Int\\w*|readBig\\w*|readFloat\\w*|readDouble\\w*)\\s*\\(}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const mqttRe = new RegExp(process.env.DOCTOR_MQTT_FILE)
const schemaRe = new RegExp(process.env.DOCTOR_SCHEMA_CALL)
const readRe = new RegExp(process.env.DOCTOR_BINARY_READ)
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

let handlers = 0
let readers = 0

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }

  if (readRe.test(text) && !/(byteLength|\.length|BYTES|LENGTH|SIZE)/.test(text)) {
    const hit = text.match(readRe)
    readers += 1
    fails.push(`169 ${file}:${lineAt(text, text.indexOf(hit[0]))} — lecture binaire sans contrôle de longueur`)
  } else if (readRe.test(text)) {
    readers += 1
  }

  if (!mqttRe.test(text)) continue

  const bodies = []
  for (const m of text.matchAll(/\.on\w*\(\s*["\x60\x27]message["\x60\x27]/g)) {
    const open = text.indexOf("(", m.index)
    const span = paren(text, open)
    const arrow = span.indexOf("=>")
    if (arrow < 0) continue
    bodies.push([m.index, block(text, open + arrow)])
  }
  for (const m of text.matchAll(/\b(?:function|const|let)\s+\w*(?:[Mm]essage[Hh]andler|(?:on|handle)\w*Message)\w*\b/g))
    bodies.push([m.index, block(text, m.index)])

  for (const [index, body] of bodies) {
    if (!body) continue
    const at = `${file}:${lineAt(text, index)}`
    handlers += 1
    if (!schemaRe.test(body)) fails.push(`158 ${at} — message entrant décodé sans schéma`)
    if (!/(byteLength|\.length)\s*(===|!==|<|>|<=|>=)\s*0\b/.test(body) && !/\b(isEmpty|isRetainedDeletion|isTombstone)\b/.test(body))
      fails.push(`162 ${at} — charge utile vide non traitée`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${handlers} gestionnaire(s) et ${readers} décodeur(s) binaires conformes`)
'
