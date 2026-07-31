#!/usr/bin/env bash
# connect.sh — 286 session conservée · 287 expiration de session · 288 délai de testament
#              289 maintien · 290 identifiant client · 291 identifiant aléatoire
#              292 secret dans l adresse · 293 adresse en dur · 294 schéma chiffré
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_MQTT_CONFIG="${DOCTOR_MQTT_CONFIG:-(^|/)(config|settings|env)[^/]*\.ts$}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const configRe = new RegExp(process.env.DOCTOR_MQTT_CONFIG)
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

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }

  for (const m of text.matchAll(/(mqtts?|tcp|wss?):\/\/[^\s"\x60\x27\/@]*:[^\s"\x60\x27\/@]*@/g))
    fails.push(`292 ${file}:${lineAt(text, m.index)} — identifiants portés par l adresse du broker`)

  for (const m of text.matchAll(/\b(mqtt|tcp|ws):\/\//g))
    fails.push(`294 ${file}:${lineAt(text, m.index)} — schéma ${m[1]} en clair, mqtts attendu`)

  if (!configRe.test(file))
    for (const m of text.matchAll(/\bmqtts:\/\//g))
      fails.push(`293 ${file}:${lineAt(text, m.index)} — adresse de broker en dur hors configuration`)

  if (!/(from "mqtt"|require\("mqtt"\)|mqtt\.connect|connectAsync|MqttClient)/.test(text)) continue

  for (const m of text.matchAll(/\b(?:mqtt\.)?connect(?:Async)?\s*\(/g)) {
    const before = text.slice(0, m.index).replace(/\s+$/, "")
    if (!/[=(,.]$|=>$|\b(await|return)$/.test(before)) continue
    const args = paren(text, m.index + m[0].length - 1)
    const at = `${file}:${lineAt(text, m.index)}`

    if (!/\bkeep[aA]live\b/.test(args)) fails.push(`289 ${at} — connexion sans intervalle de maintien explicite`)
    if (!/\bsessionExpiryInterval\b/.test(args)) fails.push(`287 ${at} — connexion sans expiration de session explicite`)
    if (/\bwill\s*:/.test(args) && !/\bwillDelayInterval\b/.test(args))
      fails.push(`288 ${at} — testament sans délai`)
    if (!/\bclean\s*:/.test(args)) warns.push(`286 ${at} — reprise de session non déclarée (clean implicite)`)

    const clientId = args.match(/\bclientId\s*:\s*([^,\n}]+)/)
    if (!clientId) {
      fails.push(`290 ${at} — aucun clientId, le broker en tirerait un au hasard`)
    } else {
      const value = clientId[1].trim()
      if (/^["\x60\x27]/.test(value) && !/\$\{/.test(value))
        fails.push(`290 ${at} — clientId littéral, l identifiant d appareil est attendu`)
      if (/(Math\.random|randomUUID|randomBytes|nanoid|uuid|Date\.now)/i.test(value))
        fails.push(`291 ${at} — clientId tiré au hasard: ${value}`)
    }
  }
}

for (const v of fails) console.log("FAIL: " + v)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log("OK: connexions MQTT explicites")
'
