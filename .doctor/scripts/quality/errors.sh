#!/usr/bin/env bash
# errors.sh — 114 réencapsulation sans cause · 116 message d erreur générique
#             120 new Promise autour de code déjà asynchrone
#             123 effet de bord au chargement du module
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

ENTRYPOINTS="${DOCTOR_ENTRYPOINTS:-main.ts|cli.ts|bin.ts|server.ts|daemon.ts}"
FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_ENTRY="$ENTRYPOINTS" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const entry = new RegExp("/(" + process.env.DOCTOR_ENTRY + ")$")
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
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

const CATCH = /(^|[^A-Za-z0-9_$])catch[ \t]*\([^)]*\)[ \t]*\{/g
const THROW = /throw[ \t]+new[ \t]+[A-Za-z0-9_$.]*Error[ \t]*\(/g
const MESSAGE = /new[ \t]+[A-Za-z0-9_$.]*Error[ \t]*\(/g
const GENERIC = /^(|error|errors|failed|failure|fail|oops|invalid|unexpected|unknown|unknown error|bad|wrong|something went wrong|an error occurred|not ok|nope|todo)[.!\s]*$/i
const PROMISE = /new[ \t]+Promise[ \t]*\(/g
const SIDE_EFFECT = /^([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z0-9_$]+)*)[ \t]*(\(|=[^=>])/
const SAFE_CALL = /^(describe|declare|export|import|type|const|let|class|function|enum)$/

const violations = []
const warnings = []
let rethrows = 0

for (const file of files) {
  const raw = read(file)
  const text = strip(raw)
  let match

  CATCH.lastIndex = 0
  while ((match = CATCH.exec(text)) !== null) {
    const open = text.indexOf("{", match.index)
    const end = close(text, open, "{", "}")
    if (end === -1) continue
    const body = text.slice(open, end)
    let thrown
    THROW.lastIndex = 0
    while ((thrown = THROW.exec(body)) !== null) {
      rethrows += 1
      const args = close(body, body.indexOf("(", thrown.index + 5), "(", ")")
      const call = body.slice(thrown.index, args === -1 ? body.length : args)
      if (!/\bcause\b/.test(call)) {
        violations.push(`114 ${file}:${lineAt(text, open + thrown.index)} — réencapsulation sans cause`)
      }
    }
  }

  MESSAGE.lastIndex = 0
  while ((match = MESSAGE.exec(text)) !== null) {
    const open = text.indexOf("(", match.index)
    const shut = close(text, open, "(", ")")
    if (shut === -1) continue
    const first = raw.slice(open + 1, shut).split(",")[0].trim()
    const quoted = /^(["\x27])([\s\S]*)\1$/.exec(first)
    if (first === "" || (quoted && GENERIC.test(quoted[2]))) {
      warnings.push(`116 ${file}:${lineAt(text, match.index)} — message d erreur générique`)
    }
  }

  PROMISE.lastIndex = 0
  while ((match = PROMISE.exec(text)) !== null) {
    const open = text.indexOf("(", match.index)
    const shut = close(text, open, "(", ")")
    if (shut === -1) continue
    const body = text.slice(open, shut)
    if (/\basync\b/.test(body) || /\bawait\b/.test(body) || /\.then[ \t]*\(/.test(body)) {
      warnings.push(`120 ${file}:${lineAt(text, match.index)} — new Promise autour de code déjà asynchrone`)
    }
  }

  if (!entry.test(file)) {
    text.split("\n").forEach((line, index) => {
      const hit = SIDE_EFFECT.exec(line)
      if (!hit) return
      if (SAFE_CALL.test(hit[1].split(".")[0])) return
      violations.push(`123 ${file}:${index + 1} — effet de bord au chargement du module`)
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
if (warnings.length > 0) console.log(`OK: aucune erreur mal formée (${warnings.length} avertissement(s))`)
else console.log(`OK: ${rethrows} réencapsulation(s) tracée(s)`)
'
