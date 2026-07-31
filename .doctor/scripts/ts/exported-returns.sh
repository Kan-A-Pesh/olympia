#!/usr/bin/env bash
# exported-returns.sh — 34 retour annoté sur les fonctions exportées d un paquet
#                       (frontière de paquet uniquement : `packages/*/src`)
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

BOUNDARY="${DOCTOR_BOUNDARY:-^packages/}"
FILES=$("$DOCTOR_DIR/utils/list-files.sh" src | grep -E "$BOUNDARY" || true)
[[ -z "$FILES" ]] && { echo "OK: aucune frontière de paquet à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const DECL = /(^|\n)[ \t]*export[ \t]+(?:async[ \t]+)?function[ \t]*\*?[ \t]*([A-Za-z0-9_$]+)[ \t]*(?:<[^(]*>)?[ \t]*\(/g
const ARROW = /(^|\n)[ \t]*export[ \t]+const[ \t]+([A-Za-z0-9_$]+)[ \t]*=[ \t]*(?:async[ \t]+)?(?:<[^(=]*>)?[ \t]*\(/g

const violations = []
let exported = 0

const closingParen = (text, from) => {
  let depth = 0
  for (let i = from; i < text.length; i++) {
    if (text[i] === "(") depth += 1
    else if (text[i] === ")") { depth -= 1; if (depth === 0) return i }
  }
  return text.length
}

for (const file of files) {
  const text = strip(read(file))

  for (const [pattern, isArrow] of [[DECL, false], [ARROW, true]]) {
    let match
    pattern.lastIndex = 0
    while ((match = pattern.exec(text)) !== null) {
      const close = closingParen(text, pattern.lastIndex - 1)
      const rest = text.slice(close + 1, close + 40)
      if (isArrow && !/^[ \t]*(:|=>)/.test(rest)) continue

      exported += 1
      if (!/^[ \t]*:/.test(rest)) {
        const line = text.slice(0, match.index + match[1].length).split("\n").length
        violations.push(`34 ${file}:${line} — la fonction exportée "${match[2]}" n annote pas son retour`)
      }
    }
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${exported} fonction(s) exportée(s) annotée(s)`)
'
