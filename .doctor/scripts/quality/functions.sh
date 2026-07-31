#!/usr/bin/env bash
# functions.sh — 99 longueur de fonction · 100 nombre de paramètres
#                103 symboles exportés par fichier · 118 async sans await
#                131 paramètre booléen positionnel
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_MAX_FUNCTION_LINES="${DOCTOR_MAX_FUNCTION_LINES:-60}" \
DOCTOR_MAX_PARAMS="${DOCTOR_MAX_PARAMS:-4}" \
DOCTOR_MAX_EXPORTS="${DOCTOR_MAX_EXPORTS:-10}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const maxLines = Number(process.env.DOCTOR_MAX_FUNCTION_LINES || 60)
const maxParams = Number(process.env.DOCTOR_MAX_PARAMS || 4)
const maxExports = Number(process.env.DOCTOR_MAX_EXPORTS || 10)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const KEYWORD = /^(if|for|while|switch|catch|return|new|typeof|await|function|do|else|with|yield|import|export|case|delete|void|in|of|throw)$/
const HEAD = [
  /(^|\n)([ \t]*)(?:export[ \t]+)?(?:default[ \t]+)?(?:(async)[ \t]+)?function[ \t]*\*?[ \t]*([A-Za-z0-9_$]*)[ \t]*(?:<[^(]*>)?[ \t]*\(/g,
  /(^|\n)([ \t]*)(?:export[ \t]+)?(?:const|let)[ \t]+([A-Za-z0-9_$]+)[ \t]*(?::[^=\n]*)?=[ \t]*(?:(async)[ \t]+)?(?:<[^(]*>)?[ \t]*\(/g,
  /(^|\n)([ \t]+)(?:(?:public|private|protected|static|readonly|override)[ \t]+)*(?:(async)[ \t]+)?(#?[A-Za-z0-9_$]+)[ \t]*(?:<[^(]*>)?[ \t]*\(/g,
]
const EXPORTED = /(^|\n)[ \t]*export[ \t]+(?:(?:async|declare)[ \t]+)?(?:type|class|function|const[ \t]+[A-Za-z0-9_$]+[ \t]*(?::[^=\n]*)?=[ \t]*(?:async[ \t]+)?(?:<[^(]*>)?\([^\n]*=>)/g

const lineAt = (text, index) => text.slice(0, index).split("\n").length
const close = (text, open, a, b) => {
  let depth = 0
  for (let i = open; i < text.length; i++) {
    if (text[i] === a) depth += 1
    else if (text[i] === b) { depth -= 1; if (depth === 0) return i }
  }
  return -1
}

const splitParams = (raw) => {
  const parts = []
  let depth = 0
  let current = ""
  for (const ch of raw) {
    if (ch === "(" || ch === "[" || ch === "{" || ch === "<") depth += 1
    else if (ch === ")" || ch === "]" || ch === "}" || ch === ">") depth -= 1
    if (ch === "," && depth === 0) { parts.push(current); current = "" } else current += ch
  }
  parts.push(current)
  return parts.map((p) => p.trim()).filter(Boolean)
}

const violations = []
const warnings = []
let scanned = 0

for (const file of files) {
  const text = strip(read(file))
  const seen = new Set()

  for (const pattern of HEAD) {
    let match
    pattern.lastIndex = 0
    while ((match = pattern.exec(text)) !== null) {
      const isMethod = pattern === HEAD[2]
      const name = isMethod ? match[4] : (pattern === HEAD[0] ? match[4] : match[3])
      const isAsync = isMethod ? Boolean(match[3]) : Boolean(pattern === HEAD[0] ? match[3] : match[4])
      if (!name || KEYWORD.test(name)) continue
      const open = pattern.lastIndex - 1
      const shut = close(text, open, "(", ")")
      if (shut === -1) continue
      const nl = text.indexOf("\n", shut)
      const head = text.slice(shut + 1, nl === -1 ? text.length : nl)
      if (!/^[^;=]*(=>|\{)/.test(head)) continue
      if (seen.has(open)) continue
      seen.add(open)
      scanned += 1

      const line = lineAt(text, match.index + match[1].length)
      const params = splitParams(text.slice(open + 1, shut))
      if (params.length > maxParams) {
        violations.push(`100 ${file}:${line} — "${name}" prend ${params.length} paramètres (max ${maxParams})`)
      }
      for (const param of params) {
        if (/:[ \t]*boolean(\b|[^A-Za-z0-9_$])/.test(param) || /^[A-Za-z0-9_$]+[ \t]*=[ \t]*(true|false)[ \t]*$/.test(param)) {
          warnings.push(`131 ${file}:${line} — "${name}" prend un booléen positionnel`)
          break
        }
      }

      const arrowAt = head.indexOf("=>")
      const braceAt = head.indexOf("{")
      let body = -1
      if (arrowAt !== -1 && (braceAt === -1 || arrowAt < braceAt)) {
        const block = /^[ \t\n]*\{/.exec(text.slice(shut + 3 + arrowAt))
        if (block) body = shut + 3 + arrowAt + block[0].length - 1
      } else if (braceAt !== -1) {
        body = shut + 1 + braceAt
      }
      while (body !== -1) {
        const bodyEnd = close(text, body, "{", "}")
        if (bodyEnd === -1) break
        const after = text.slice(bodyEnd + 1).match(/^[ \t]*(.)/)
        if (after && after[1] === "{") { body = text.indexOf("{", bodyEnd + 1); continue }
        const span = lineAt(text, bodyEnd) - line + 1
        if (span > maxLines) {
          violations.push(`99 ${file}:${line} — "${name}" fait ${span} lignes (max ${maxLines})`)
        }
        if (isAsync && !/\bawait\b/.test(text.slice(body, bodyEnd))) {
          warnings.push(`118 ${file}:${line} — "${name}" est async sans await`)
        }
        break
      }
    }
  }

  let count = 0
  let match
  EXPORTED.lastIndex = 0
  while ((match = EXPORTED.exec(text)) !== null) count += 1
  if (count > maxExports) {
    warnings.push(`103 ${file}:1 — ${count} symboles exportés (seuil ${maxExports})`)
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
if (warnings.length > 0) console.log(`OK: aucun dépassement bloquant (${warnings.length} avertissement(s))`)
else console.log(`OK: ${scanned} fonction(s) dans les limites`)
'
