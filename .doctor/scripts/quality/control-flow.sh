#!/usr/bin/env bash
# control-flow.sh — 130 else après return · 133 switch sans cas par défaut ni garde
#                   d exhaustivité · 134 chute entre deux cas
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

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

const lineAt = (text, index) => text.slice(0, index).split("\n").length
const close = (text, open, a, b) => {
  let depth = 0
  for (let i = open; i < text.length; i++) {
    if (text[i] === a) depth += 1
    else if (text[i] === b) { depth -= 1; if (depth === 0) return i }
  }
  return -1
}

const SWITCH = /(^|[^A-Za-z0-9_$])switch[ \t]*\(/g
const EXIT = /^[ \t]*(return|throw|continue|break)\b/
const NEVER = /(never|assertNever|exhaustive|unreachable)/
const LABEL = /^[ \t]*(case[ \t][^\n]*|default)[ \t]*:/

const violations = []
const warnings = []
let switches = 0

for (const file of files) {
  const text = strip(read(file))
  const lines = text.split("\n")

  lines.forEach((raw, index) => {
    if (!/^[ \t]*\}?[ \t]*else\b/.test(raw)) return
    let previous = index - 1
    while (previous >= 0 && lines[previous].trim() === "") previous -= 1
    if (previous >= 0 && EXIT.test(lines[previous])) {
      warnings.push(`130 ${file}:${index + 1} — else après une sortie anticipée`)
    }
  })

  let match
  SWITCH.lastIndex = 0
  while ((match = SWITCH.exec(text)) !== null) {
    const paren = text.indexOf("(", match.index)
    const shut = close(text, paren, "(", ")")
    if (shut === -1) continue
    const open = text.indexOf("{", shut)
    const end = open === -1 ? -1 : close(text, open, "{", "}")
    if (end === -1) continue
    switches += 1
    const at = lineAt(text, match.index) + (match[1] === "\n" ? 1 : 0)
    const body = text.slice(open + 1, end)

    if (!/^[ \t]*default[ \t]*:/m.test(body) && !NEVER.test(body)) {
      violations.push(`133 ${file}:${at} — switch sans cas par défaut ni garde d exhaustivité`)
    }

    const bodyLines = body.split("\n")
    const bodyAt = lineAt(text, open + 1)
    let depth = 0
    let current = null
    const segments = []
    bodyLines.forEach((raw, offset) => {
      if (depth === 0 && LABEL.test(raw)) {
        current = { line: bodyAt + offset, body: [raw.replace(LABEL, "")] }
        segments.push(current)
      } else if (current) {
        current.body.push(raw)
      }
      for (const ch of raw) {
        if (ch === "{" || ch === "(" || ch === "[") depth += 1
        else if (ch === "}" || ch === ")" || ch === "]") depth -= 1
      }
    })
    segments.forEach((segment, index) => {
      if (index === segments.length - 1) return
      const content = segment.body.join("\n")
      if (content.trim() === "") return
      if (!/\b(break|return|throw|continue)\b/.test(content)) {
        violations.push(`134 ${file}:${segment.line} — chute vers le cas suivant`)
      }
    })
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
if (warnings.length > 0) console.log(`OK: aucun switch fautif (${warnings.length} avertissement(s))`)
else console.log(`OK: ${switches} switch(s) complet(s)`)
'
