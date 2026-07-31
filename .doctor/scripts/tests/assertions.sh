#!/usr/bin/env bash
# assertions.sh — 139 au moins une assertion par test · 141 nom qui décrit un comportement
#                 142 nom commençant par « should » · 147 délai d attente en dur
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

TESTS=$("$DOCTOR_DIR/utils/list-files.sh" test)
[[ -z "$TESTS" ]] && { echo "OK: aucun fichier de test à inspecter"; exit 0; }

DOCTOR_TEST_FILES="$TESTS" \
DOCTOR_MIN_TEST_WORDS="${DOCTOR_MIN_TEST_WORDS:-3}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_TEST_FILES || "").split("\n").filter(Boolean)
const minWords = Number(process.env.DOCTOR_MIN_TEST_WORDS || 3)
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
const endOfString = (text, start, quote) => {
  for (let i = start; i < text.length; i += 1) {
    if (text[i] === "\\") { i += 1; continue }
    if (text[i] === quote) return i
  }
  return -1
}
const topLevelArgs = (masked) => {
  const parts = []
  let depth = 0
  let current = ""
  for (const ch of masked) {
    if (ch === "(" || ch === "[" || ch === "{") depth += 1
    else if (ch === ")" || ch === "]" || ch === "}") depth -= 1
    if (ch === "," && depth === 0) { parts.push(current); current = "" } else current += ch
  }
  parts.push(current)
  return parts
}

const PLAIN = /^(concurrent|sequential|fails|extend|skipIf|runIf|runsIf)$/
const blocks = []
for (const file of files) {
  const text = read(file)
  const masked = mask(text)
  const head = /(^|[^.\w$])(it|test|describe)(\.[A-Za-z]+)?\s*\(/g
  let match
  while ((match = head.exec(masked)) !== null) {
    const modifier = match[3] ? match[3].slice(1) : ""
    if (modifier && !PLAIN.test(modifier)) continue
    const open = head.lastIndex - 1
    const shut = closeParen(masked, open)
    if (shut === -1) continue
    const quoted = /^\s*(["\x27`])/.exec(text.slice(open + 1, shut))
    if (!quoted) continue
    const start = open + 1 + quoted[0].length
    const stop = endOfString(text, start, quoted[1])
    if (stop === -1 || stop > shut) continue
    blocks.push({
      file,
      kind: match[2],
      name: text.slice(start, stop),
      literal: quoted[1] !== "`",
      line: lineAt(text, open),
      body: text.slice(stop + 1, shut),
      args: masked.slice(open + 1, shut),
    })
  }
}

if (blocks.length === 0) { console.log("OK: aucun bloc de test à inspecter"); process.exit(0) }

const ASSERT = /expect\s*\(|expect\.\w|\bassert(?:\.\w+)?\s*\(|\.(?:rejects|resolves)\b|\.toThrow/
const PLACEHOLDER = /^(test|tests|works?|ok|okay|basic|simple|sanity|todo|tbd|case|foo|bar|baz|misc|stuff|thing|x|y)\b/i
const SINGLE = /^[A-Za-z_$][\w$]*(\(\))?$/
const NAMED_TIMEOUT = /\b(testTimeout|hookTimeout|teardownTimeout)\s*:\s*\d+/
const OPTION_TIMEOUT = /\btimeout\s*:\s*\d+/
const METHOD_TIMEOUT = /\.(setTimeout|timeout)\s*\(\s*\d+/

const fails = []
const warns = []

for (const block of blocks) {
  const at = `${block.file}:${block.line}`
  if (block.kind !== "describe") {
    if (!ASSERT.test(block.body)) fails.push(`139 ${at} — "${block.name}" ne contient aucune assertion`)

    if (block.literal) {
      const name = block.name.trim()
      if (/^should\b/i.test(name)) warns.push(`142 ${at} — "${name}" commence par should`)
      const words = name.split(/\s+/).filter(Boolean)
      if (words.length < minWords || SINGLE.test(name) || PLACEHOLDER.test(name))
        warns.push(`141 ${at} — "${name}" ne décrit pas un comportement`)
    }
  }

  if (OPTION_TIMEOUT.test(block.args)) warns.push(`147 ${at} — délai passé en option au bloc de test`)
  const args = topLevelArgs(block.args)
  const last = args[args.length - 1].trim()
  if (args.length > 1 && /^[0-9][0-9_]*$/.test(last))
    warns.push(`147 ${at} — délai ${last} passé en dernier argument`)
}

for (const file of files) {
  read(file).split("\n").forEach((line, index) => {
    if (NAMED_TIMEOUT.test(line) || METHOD_TIMEOUT.test(line))
      warns.push(`147 ${file}:${index + 1} — délai fixé en dur pour le lanceur de tests`)
  })
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const w of warns) console.log(`WARN: ${w}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length > 0) console.log(`OK: ${blocks.length} bloc(s) assertés (${warns.length} avertissement(s))`)
else console.log(`OK: ${blocks.length} bloc(s) de test assertés et nommés`)
'
