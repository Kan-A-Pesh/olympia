#!/usr/bin/env bash
# obligations.sh — 149 codec avec test aller-retour · 150 parseur avec test d entrée malformée
#                  151 schéma avec test de rejet
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SOURCES=$("$DOCTOR_DIR/utils/list-files.sh" src)
TESTS=$("$DOCTOR_DIR/utils/list-files.sh" test)
[[ -z "$SOURCES" ]] && { echo "OK: aucune source à inspecter"; exit 0; }

DOCTOR_SOURCE_FILES="$SOURCES" \
DOCTOR_TEST_FILES="$TESTS" \
node -e '
const fs = require("node:fs")

const sources = (process.env.DOCTOR_SOURCE_FILES || "").split("\n").filter(Boolean)
const tests = (process.env.DOCTOR_TEST_FILES || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const mask = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const lineAt = (text, index) => text.slice(0, index).split("\n").length
const closeParen = (text, open) => {
  let depth = 0
  for (let i = open; i < text.length; i += 1) {
    if (text[i] === "(") depth += 1
    else if (text[i] === ")") { depth -= 1; if (depth === 0) return i }
  }
  return -1
}

const blocks = []
for (const file of tests) {
  const text = read(file)
  const masked = mask(text)
  const head = /(^|[^.\w$])(it|test)(\.[A-Za-z]+)?\s*\(/g
  let match
  while ((match = head.exec(masked)) !== null) {
    if (match[3] && !/^\.(concurrent|sequential|fails|extend|skipIf|runIf)$/.test(match[3])) continue
    const open = head.lastIndex - 1
    const shut = closeParen(masked, open)
    if (shut === -1) continue
    blocks.push({ file, body: text.slice(open + 1, shut) })
  }
}
const testText = tests.map(read).join("\n")

const ENCODERS = [
  ["encode", "decode"],
  ["serialize", "deserialize"],
  ["pack", "unpack"],
  ["marshal", "unmarshal"],
]
const REJECTION = /toThrow|toBeNull|toBeUndefined|\.rejects\b|success\s*:\s*false|toBeFalsy/

const exported = new Map()
const schemas = new Map()
for (const file of sources) {
  const masked = mask(read(file))
  const declared = /(^|\n)export\s+(?:async\s+)?function\s+([A-Za-z0-9_$]+)/g
  const arrow = /(^|\n)export\s+const\s+([A-Za-z0-9_$]+)\s*(?::[^=\n]*)?=\s*(?:async\s+)?(?:<[^(]*>)?\(/g
  const schema = /(^|\n)export\s+const\s+([A-Za-z0-9_$]*[Ss]chema)\s*(?::[^=\n]*)?=/g
  for (const pattern of [declared, arrow]) {
    let match
    while ((match = pattern.exec(masked)) !== null)
      if (!exported.has(match[2])) exported.set(match[2], { file, line: lineAt(masked, match.index + match[1].length) })
  }
  let match
  while ((match = schema.exec(masked)) !== null)
    if (!schemas.has(match[2])) schemas.set(match[2], { file, line: lineAt(masked, match.index + match[1].length) })
}

const fails = []
let codecs = 0
let parsers = 0
let checked = 0

for (const [name, where] of exported) {
  for (const [head, tail] of ENCODERS) {
    if (!name.startsWith(head)) continue
    const counterpart = tail + name.slice(head.length)
    if (!exported.has(counterpart)) continue
    codecs += 1
    const roundTrip = blocks.some((b) =>
      new RegExp(`\\b${name}\\s*\\(`).test(b.body) && new RegExp(`\\b${counterpart}\\s*\\(`).test(b.body))
    if (!roundTrip)
      fails.push(`149 ${where.file}:${where.line} — ${name}/${counterpart} sans test qui enchaîne les deux`)
  }
}

for (const [name, where] of exported) {
  if (!/^(parse|decode)([A-Z_].*)?$/.test(name)) continue
  parsers += 1
  const called = new RegExp(`\\b${name}\\s*\\(`)
  if (!blocks.some((b) => called.test(b.body) && REJECTION.test(b.body)))
    fails.push(`150 ${where.file}:${where.line} — ${name} sans test qui refuse une entrée malformée`)
}

for (const [name, where] of schemas) {
  const used = new RegExp(`\\b${name}\\b`)
  if (!used.test(testText)) continue
  checked += 1
  if (!blocks.some((b) => used.test(b.body) && REJECTION.test(b.body)))
    fails.push(`151 ${where.file}:${where.line} — ${name} exercé par un test sans cas de rejet`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${codecs} codec(s), ${parsers} parseur(s) et ${checked} schéma(s) couverts`)
'
