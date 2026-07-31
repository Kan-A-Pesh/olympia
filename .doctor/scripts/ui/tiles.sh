#!/usr/bin/env bash
# tiles.sh — 242 état vide · 243 état figé · 244 appareil relayé marqué · 245 étiquette de commande
#            246 nom d appareil en dur · 247 unité en dur · 248 formatage hors utilitaire
#            249 formatage dépendant de la locale · 250 texte dessiné sans repli
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all \
  | grep -E '\.(ts|tsx|jsx)$' | grep -vE '\.(d|test|spec)\.tsx?$' || true)
[[ -z "$FILES" ]] && { echo "OK: aucune tuile à inspecter"; exit 0; }

printf '%s\n' "$FILES" \
  | DEVICE_NAMES="${DOCTOR_UI_DEVICE_NAMES:-Rigol|Siglent|Owon|Hantek|Keysight|Tektronix|Fluke|Korad|Uni-?T|DS1054Z|SDS1104|UT61|HDS242}" \
    UNITS="${DOCTOR_UI_UNITS:-V|mV|kV|uV|A|mA|uA|Hz|kHz|MHz|GHz|Ω|ohm|°C|°F|dBm|dB|W|mW|kW|F|uF|nF|pF|H|mH|s|ms|us|ns}" \
    EMPTY_MARKERS="${DOCTOR_UI_EMPTY_MARKERS:-[Ee]mpty|hasData|isEmpty|noData|length === 0|length > 0|\\?\\?}" \
    STALE_MARKERS="${DOCTOR_UI_STALE_MARKERS:-[Ss]tale|lastSeen|lastUpdate|freshness|ageMs}" \
    node -e '
const fs = require("node:fs")

const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)
const fails = []
const warns = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length
const fail = (id, file, line, msg) => fails.push(`${id} ${file}:${line} — ${msg}`)

const DEVICE_NAMES = new RegExp(`(^|[^\\w])(${process.env.DEVICE_NAMES})([^\\w]|$)`, "g")
const UNITS = process.env.UNITS
const BARE_UNIT = new RegExp(`["'"'"'\`]\\s*(${UNITS})\\s*["'"'"'\`]`, "g")
const SUFFIX_UNIT = new RegExp("\\$\\{[^{}]*\\}\\s*(" + UNITS + ")\\s*(`|<)", "g")
const EMPTY = new RegExp(process.env.EMPTY_MARKERS)
const STALE = new RegExp(process.env.STALE_MARKERS)
const TILE = /(^|\/)[\w-]*tile[\w-]*\.(tsx|jsx)$/i
const FORMATTER = /(format|unit|humaniz)/i
const CONTROL_LABEL = /<\w*(Knob|Encoder|Dial|Control)\w*\b[^<>]*\slabel\s*=\s*["'"'"'`]/g
const CANVAS_FALLBACK = /(aria-label|aria-live|role\s*=\s*["'"'"']img|sr-only|srOnly|<figcaption|visually-hidden)/

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }
  const base = file.split("/").pop()
  const isView = /\.(tsx|jsx)$/.test(file)

  if (TILE.test(file)) {
    if (!EMPTY.test(text)) fail(242, file, 1, "tuile sans traitement de l absence de données")
    if (!STALE.test(text)) fail(243, file, 1, "tuile qui ne distingue pas une mesure figée")
  }

  if (isView) {
    if (/(isAuthenticated|authenticated|trusted)/.test(text) && !/(relay|Relay|unverified)/.test(text))
      fail(244, file, lineOf(text, text.search(/(isAuthenticated|authenticated|trusted)/)),
        "appareil authentifié affiché sans distinguer un appareil relayé")

    for (const m of text.matchAll(CONTROL_LABEL))
      fail(245, file, lineOf(text, m.index), "étiquette de commande codée en dur au lieu de venir du driver")

    for (const m of text.matchAll(DEVICE_NAMES))
      fail(246, file, lineOf(text, m.index), `nom d appareil en dur (${m[2]})`)

    if (!FORMATTER.test(base)) {
      for (const m of text.matchAll(BARE_UNIT))
        fail(247, file, lineOf(text, m.index), `unité physique en dur (${m[0]})`)
      for (const m of text.matchAll(SUFFIX_UNIT))
        fail(247, file, lineOf(text, m.index), `unité physique accolée à une mesure (${m[1]})`)
      for (const m of text.matchAll(/\.(toFixed|toPrecision)\(/g))
        fail(248, file, lineOf(text, m.index), "mesure formatée hors de l utilitaire de formatage")
    }
  }

  for (const m of text.matchAll(/(toLocaleString\(|toLocaleDateString\(|toLocaleTimeString\(|Intl\.(NumberFormat|DateTimeFormat)\()/g))
    fail(249, file, lineOf(text, m.index), `formatage dépendant de la locale (${m[1]})`)

  if (/(fillText|strokeText)\(/.test(text) && !CANVAS_FALLBACK.test(text))
    warns.push(`250 ${file}:${lineOf(text, text.search(/(fillText|strokeText)\(/))} — texte dessiné dans le canevas sans repli lisible`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length === 0) console.log(`OK: ${files.length} fichier(s) sans donnée d appareil codée en dur`)
'
