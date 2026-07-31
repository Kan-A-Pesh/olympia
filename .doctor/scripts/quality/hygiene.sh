#!/usr/bin/env bash
# hygiene.sh — 104 fichier concentrant trop de symboles · 126 API Node dépréciée
#              127 horloge dans une fonction pure · 128 aléatoire dans le protocole
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_MAX_SYMBOLS="${DOCTOR_MAX_SYMBOLS:-20}" \
DOCTOR_PROTOCOL_SCOPE="${DOCTOR_PROTOCOL_SCOPE:-^packages/}" \
DOCTOR_CLOCK_FILES="${DOCTOR_CLOCK_FILES:-(^|/)(main|clock)\.ts$}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const maxSymbols = Number(process.env.DOCTOR_MAX_SYMBOLS || 20)
const protocolScope = new RegExp(process.env.DOCTOR_PROTOCOL_SCOPE)
const clockFiles = new RegExp(process.env.DOCTOR_CLOCK_FILES)

const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const mask = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const DEPRECATED = [
  [/\bnew\s+Buffer\s*\(/, "new Buffer(), remplacer par Buffer.from ou Buffer.alloc"],
  [/\brequire\s*\(\s*["\x27](?:node:)?(sys|punycode|domain|constants|querystring)["\x27]\s*\)/, "module Node déprécié"],
  [/\bfrom\s+["\x27](?:node:)?(sys|punycode|domain|constants)["\x27]/, "module Node déprécié"],
  [/\burl\.(parse|resolve)\s*\(/, "url.parse/url.resolve, remplacer par new URL()"],
  [/\bfs\.exists\s*\(/, "fs.exists(), remplacer par fs.access ou statSync"],
  [/\butil\.(isArray|isDate|isError|isRegExp|isString|isNumber|isBoolean|isObject|isPrimitive|isSymbol|isFunction|isBuffer|isNullOrUndefined|_extend|print|puts|debug|log)\s*\(/, "util.* déprécié"],
  [/\bcrypto\.(createCipher|createDecipher)\s*\(/, "createCipher/createDecipher sans vecteur initial"],
  [/\bprocess\.binding\s*\(/, "process.binding()"],
  [/\brequire\.extensions\b/, "require.extensions"],
  [/\bos\.tmpDir\s*\(/, "os.tmpDir(), remplacer par os.tmpdir()"],
  [/\bdomain\.create\s*\(/, "module domain"],
]

const CLOCK = /\b(Date\.now\s*\(\s*\)|performance\.now\s*\(\s*\)|new\s+Date\s*\(\s*\))/
const INJECTED = /[(,]\s*[A-Za-z0-9_$]+\s*(?::[^=,)]*)?=\s*(?:\(\s*\)\s*=>\s*)?(?:Date\.now|performance\.now)\b/
const RANDOM = /\bMath\.random\s*\(/

const SYMBOLS = [
  /(^|\n)(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z0-9_$]+)/g,
  /(^|\n)(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?class\s+([A-Za-z0-9_$]+)/g,
  /(^|\n)(?:export\s+)?(?:declare\s+)?type\s+([A-Za-z0-9_$]+)\s*[<=]/g,
  /(^|\n)(?:export\s+)?(?:declare\s+)?(?:const\s+)?enum\s+([A-Za-z0-9_$]+)/g,
  /(^|\n)(?:export\s+)?(?:const|let)\s+([A-Za-z0-9_$]+)\s*(?::[^=\n]*)?=\s*(?:async\s+)?(?:<[^(\n]*>)?\([^\n]*\)[^\n]*=>/g,
]

const fails = []
const warns = []
let scanned = 0

for (const file of files) {
  const text = read(file)
  const masked = mask(text)
  scanned += 1

  const names = new Set()
  for (const pattern of SYMBOLS) {
    pattern.lastIndex = 0
    let match
    while ((match = pattern.exec(masked)) !== null) names.add(match[2])
  }
  if (names.size > maxSymbols)
    warns.push(`104 ${file}:1 — ${names.size} symboles déclarés (seuil ${maxSymbols})`)

  const lines = masked.split("\n")
  for (let i = 0; i < lines.length; i += 1) {
    const at = `${file}:${i + 1}`
    for (const [pattern, label] of DEPRECATED)
      if (pattern.test(lines[i])) warns.push(`126 ${at} — ${label}`)
    if (CLOCK.test(lines[i]) && !INJECTED.test(lines[i]) && !clockFiles.test(file))
      warns.push(`127 ${at} — horloge lue sur place, la passer en paramètre`)
    if (RANDOM.test(lines[i]) && protocolScope.test(file))
      fails.push(`128 ${at} — Math.random dans le protocole, tirer un aléa explicite et injecté`)
  }
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const w of warns) console.log(`WARN: ${w}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length > 0) console.log(`OK: aucun manquement bloquant (${warns.length} avertissement(s))`)
else console.log(`OK: ${scanned} fichier(s) sans API dépréciée, horloge ni aléa implicite`)
'
