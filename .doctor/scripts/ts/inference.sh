#!/usr/bin/env bash
# inference.sh — 53 satisfies plutôt que conversion · 505 forme dérivée non réutilisée
#                506 forme d objet déclarée deux fois · 507 annotation redondante
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_MIN_SHARED_PROPS="${DOCTOR_MIN_SHARED_PROPS:-2}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const minProps = Number(process.env.DOCTOR_MIN_SHARED_PROPS || 2)
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

const TYPE = /(^|\n)[ \t]*(?:export[ \t]+)?type[ \t]+([A-Za-z0-9_$]+)[ \t]*(?:<[^=]*>)?[ \t]*=[ \t]*\{/g
const PROP = /^[ \t]*(?:readonly[ \t]+)?([A-Za-z0-9_$]+)[ \t]*\??[ \t]*[:(]/
const CAST = /[\]}][ \t]*\bas[ \t]+([A-Za-z_$][A-Za-z0-9_$.<>[\]]*)/g
const REDUNDANT = [
  [/\b(?:const|let)[ \t]+([A-Za-z0-9_$]+)[ \t]*:[ \t]*string[ \t]*=[ \t]*["\x27`]/, "string"],
  [/\b(?:const|let)[ \t]+([A-Za-z0-9_$]+)[ \t]*:[ \t]*number[ \t]*=[ \t]*-?[0-9]/, "number"],
  [/\b(?:const|let)[ \t]+([A-Za-z0-9_$]+)[ \t]*:[ \t]*boolean[ \t]*=[ \t]*(?:true|false)\b/, "boolean"],
]

const shapes = []
const violations = []
const warnings = []

for (const file of files) {
  const raw = read(file)
  const text = strip(raw)
  const lines = raw.split("\n")

  let match
  TYPE.lastIndex = 0
  while ((match = TYPE.exec(text)) !== null) {
    const open = text.indexOf("{", match.index + match[1].length)
    const end = close(text, open, "{", "}")
    if (end === -1) continue
    const body = text.slice(open + 1, end)
    const props = []
    let depth = 0
    let flat = true
    for (const raw of body.split("\n")) {
      if (depth === 0) {
        const hit = PROP.exec(raw)
        if (hit) props.push(hit[1])
        else if (/^[ \t]*\[/.test(raw)) flat = false
      }
      for (const ch of raw) {
        if (ch === "{" || ch === "(" || ch === "[") depth += 1
        else if (ch === "}" || ch === ")" || ch === "]") depth -= 1
      }
    }
    if (flat && props.length >= minProps) {
      shapes.push({ name: match[2], file, line: lineAt(text, match.index + match[1].length), props: new Set(props) })
    }
  }

  CAST.lastIndex = 0
  while ((match = CAST.exec(text)) !== null) {
    if (match[1] === "const") continue
    warnings.push(`53 ${file}:${lineAt(text, match.index)} — conversion "as ${match[1]}" sur un littéral, préférer satisfies`)
  }

  lines.forEach((raw, index) => {
    for (const [pattern, kind] of REDUNDANT) {
      const hit = pattern.exec(raw)
      if (hit) warnings.push(`507 ${file}:${index + 1} — annotation ${kind} redondante sur "${hit[1]}"`)
    }
  })
}

const subset = (a, b) => [...a].every((p) => b.has(p))

for (let i = 0; i < shapes.length; i++) {
  for (let j = i + 1; j < shapes.length; j++) {
    const a = shapes[i]
    const b = shapes[j]
    const ab = subset(a.props, b.props)
    const ba = subset(b.props, a.props)
    if (ab && ba) {
      violations.push(`506 ${b.file}:${b.line} — "${b.name}" redéclare la forme de "${a.name}" (${a.file}:${a.line})`)
    } else if (ab) {
      violations.push(`505 ${a.file}:${a.line} — "${a.name}" reprend une partie de "${b.name}", utiliser Pick/Omit/Partial`)
    } else if (ba) {
      violations.push(`505 ${b.file}:${b.line} — "${b.name}" reprend une partie de "${a.name}", utiliser Pick/Omit/Partial`)
    }
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
if (warnings.length > 0) console.log(`OK: aucune forme dupliquée (${warnings.length} avertissement(s))`)
else console.log(`OK: ${shapes.length} forme(s) d objet distincte(s)`)
'
