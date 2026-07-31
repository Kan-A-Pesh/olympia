#!/usr/bin/env bash
# settings.sh — 341 réglage sans valeur par défaut · 342 réglage relu sans validation
#               343 réglage inconnu fatal
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const fails = []
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const block = (t, from) => {
  const start = t.indexOf("{", from)
  if (start < 0) return ""
  let d = 0
  for (let i = start; i < t.length; i++) {
    if (t[i] === "{") d++
    else if (t[i] === "}") { d--; if (d === 0) return t.slice(start, i + 1) }
  }
  return t.slice(start)
}
const split = (text) => {
  const parts = []
  let cur = ""
  let d = 0
  for (const ch of text) {
    if (ch === "," && d === 0) { parts.push(cur); cur = ""; continue }
    if ("([{".includes(ch)) d++
    else if (")]}".includes(ch)) d--
    cur += ch
  }
  parts.push(cur)
  return parts.map((p) => p.trim()).filter(Boolean)
}

let seen = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  if (!/[Ss]ettings/.test(file) && !/[Ss]ettings(Schema|Table)/.test(text)) continue
  seen += 1

  for (const m of text.matchAll(/\b(?:const|let)\s+(\w*[Ss]ettings\w*)\s*(?::[^=\n]+)?=\s*z\s*\.\s*object\s*\(/g)) {
    const body = block(text, m.index + m[0].length - 1)
    for (const field of split(body.slice(1, -1))) {
      const name = field.match(/^([\w"\x60\x27]+)\s*:/)
      if (!name) continue
      if (!/\.default\s*\(/.test(field) && !/\.optional\s*\(/.test(field))
        fails.push(`341 ${file}:${lineAt(text, m.index)} — réglage ${name[1]} sans valeur par défaut`)
    }
  }

  for (const m of text.matchAll(/\.strict\s*\(/g))
    fails.push(`343 ${file}:${lineAt(text, m.index)} — schéma strict, un réglage inconnu deviendrait fatal`)
  for (const m of text.matchAll(/\b\w*[Ss]ettings\w*\.parse\s*\(/g))
    fails.push(`343 ${file}:${lineAt(text, m.index)} — lecture de réglages par parse, safeParse attendu`)

  if (/\bFROM\s+["\x60\x27]?settings/i.test(text) && !/(safeParse|\.parse)\s*\(/.test(text))
    fails.push(`342 ${file} — réglages relus sans validation par schéma`)
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} module(s) de réglages conformes`)
'
