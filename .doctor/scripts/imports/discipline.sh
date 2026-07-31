#!/usr/bin/env bash
# discipline.sh — 58 profondeur relative bornée · 70 API DOM dans le daemon
#                 71 imports groupés · 73 import dynamique dans un chemin temps réel
#
# 71 ne vérifie que l ordre des groupes (node:, paquet, relatif), pas l ordre alphabétique
# à l intérieur d un groupe : le tri fin relève du formateur, pas de la suite.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_MAX_RELATIVE="${DOCTOR_MAX_RELATIVE:-2}"
export DOCTOR_DAEMON_PATH="${DOCTOR_DAEMON_PATH:-^apps/iris-hub/}"
export DOCTOR_HOT_PATH="${DOCTOR_HOT_PATH:-(waveform|codec|decode|encode|sample|frame|render|draw|input|panel|stream|tile)}"
export DOCTOR_DOM_API="${DOCTOR_DOM_API:-document|window|navigator|localStorage|sessionStorage|HTMLElement|HTMLCanvasElement|CanvasRenderingContext2D|requestAnimationFrame|cancelAnimationFrame|getElementById|querySelector|customElements|alert}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const maxRelative = Number(process.env.DOCTOR_MAX_RELATIVE)
const daemonRe = new RegExp(process.env.DOCTOR_DAEMON_PATH)
const hotRe = new RegExp(process.env.DOCTOR_HOT_PATH)
const domRe = new RegExp("(^|[^A-Za-z0-9_$.\"\x27])(" + process.env.DOCTOR_DOM_API + ")\\b", "g")
const fails = []
const warns = []
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const group = (spec) => (spec.startsWith("node:") ? 0 : spec.startsWith(".") ? 2 : 1)
const GROUPS = ["natif", "paquet", "relatif"]

const SPEC = /(?:\bfrom\s*|\brequire\s*\(\s*|\bimport\s*\(\s*|^[ \t]*import\s*)["\x60\x27]([^"\x60\x27\n]+)["\x60\x27]/gm
const HEAD = /^[ \t]*import[ \t][^\n]*?from[ \t]*["\x27]([^"\x27\n]+)["\x27]|^[ \t]*import[ \t]*["\x27]([^"\x27\n]+)["\x27]/gm

let seen = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }

  SPEC.lastIndex = 0
  for (const m of text.matchAll(SPEC)) {
    const depth = (m[1].match(/\.\.\//g) || []).length
    if (depth > maxRelative)
      fails.push(`58 ${file}:${lineAt(text, m.index)} — ${depth} niveaux de ../ (maximum ${maxRelative})`)
  }

  if (daemonRe.test(file)) {
    domRe.lastIndex = 0
    for (const m of text.matchAll(domRe))
      fails.push(`70 ${file}:${lineAt(text, m.index)} — API DOM "${m[2]}" dans le daemon`)
  }

  if (hotRe.test(file))
    for (const m of text.matchAll(/(^|[^A-Za-z0-9_$.])import\s*\(/g))
      warns.push(`73 ${file}:${lineAt(text, m.index)} — import dynamique dans un chemin temps réel`)

  HEAD.lastIndex = 0
  let previous = -1
  for (const m of text.matchAll(HEAD)) {
    const spec = m[1] || m[2]
    const rank = group(spec)
    seen += 1
    if (rank < previous) {
      warns.push(`71 ${file}:${lineAt(text, m.index)} — import ${GROUPS[rank]} "${spec}" après un import ${GROUPS[previous]}`)
      break
    }
    previous = rank
  }
}

for (const v of fails) console.log("FAIL: " + v)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length > 0) console.log(`OK: ${seen} import(s) sans violation bloquante (${warns.length} avertissement(s))`)
else console.log(`OK: ${seen} import(s) conformes`)
'
