#!/usr/bin/env bash
# style.sh — 28 assertion non nulle hors tests · 31 enum · 33 export par défaut dans un paquet
#            38 let jamais réassigné · 55 union avec any ou unknown
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SRC=$("$DOCTOR_DIR/utils/list-files.sh" src)
ALL=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$ALL" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

PACKAGE_DIR="${DOCTOR_PACKAGE_DIR:-^packages/}"
PACKAGES=$(printf '%s\n' "$ALL" | grep -E "$PACKAGE_DIR" || true)

ERRORS=0
scan() {
  local id="$1" list="$2" pattern="$3" label="$4" hits
  [[ -z "$list" ]] && return 0
  hits=$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 grep -HnE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    echo "FAIL: $id $hit — $label"
    ERRORS=$((ERRORS + 1))
  done <<< "$hits"
}

scan 28 "$SRC"      '[]A-Za-z0-9_)]!([].,;)]|$)'                            'assertion non nulle hors test'
scan 31 "$ALL"      '^[[:space:]]*(export[[:space:]]+)?(declare[[:space:]]+)?(const[[:space:]]+)?enum[[:space:]]+' 'enum, utiliser une union littérale'
scan 33 "$PACKAGES" '^[[:space:]]*export[[:space:]]+default[[:space:]]'     'export par défaut dans un paquet'
scan 55 "$ALL"      '\|[[:space:]]*(any|unknown)([^A-Za-z0-9_]|$)'          'union absorbée par any ou unknown'
scan 55 "$ALL"      '[^A-Za-z0-9_](any|unknown)[[:space:]]*\|'              'union absorbée par any ou unknown'

WARNINGS=0
if [[ -n "$SRC" ]]; then
  MUTABLES=$(DOCTOR_FILES="$SRC" node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)
const lineAt = (t, i) => t.slice(0, i).split("\n").length

for (const file of files) {
  let text
  try { text = strip(fs.readFileSync(file, "utf8")) } catch (e) { continue }

  for (const m of text.matchAll(/(^|[^A-Za-z0-9_$.])let\s+([A-Za-z_$][\w$]*)/g)) {
    const head = text.slice(0, m.index + m[1].length)
    if (/for\s*\(\s*$/.test(head)) continue
    const name = m[2]
    const line = lineAt(text, m.index + m[1].length)
    const write = new RegExp("(^|[^A-Za-z0-9_$.])" + name + "\\s*(\\+\\+|--|(\\+|-|\\*|/|%|&|\\||\\^|\\?\\?|<<|>>)?=[^=])", "g")
    let mutated = false
    for (const w of text.matchAll(write)) {
      if (lineAt(text, w.index) === line) continue
      mutated = true
      break
    }
    if (!mutated) console.log(`${file}:${line} ${name}`)
  }
}
')
  [[ -n "$MUTABLES" ]] && while IFS= read -r hit; do
    echo "WARN: 38 ${hit% *} — \"${hit##* }\" jamais réassigné, utiliser const"
    WARNINGS=$((WARNINGS + 1))
  done <<< "$MUTABLES"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
[[ "$WARNINGS" -gt 0 ]] && echo "OK: aucune syntaxe interdite ($WARNINGS avertissement(s))" \
                        || echo "OK: style TypeScript conforme"
