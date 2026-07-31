#!/usr/bin/env bash
# queries.sh — 333 SQL hors couche de stockage · 334 SQL concaténé · 335 requête paramétrée
#              336 écritures transactionnelles · 337 entrée-sortie dans une transaction
#              338 sélection de toutes les colonnes · 339 colonne de recherche indexée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

SQL_FILES=$("$DOCTOR_DIR/utils/list-files.sh" all | grep -E '\.sql$' || true)

export DOCTOR_FILES="$FILES"
export DOCTOR_SQL_FILES="$SQL_FILES"
export DOCTOR_STORE_PATH="${DOCTOR_STORE_PATH:-(^|/)(store|db|database|migrations)([/.]|$)}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const sqlFiles = (process.env.DOCTOR_SQL_FILES || "").split("\n").filter(Boolean)
const storeRe = new RegExp(process.env.DOCTOR_STORE_PATH)
const fails = []
const warns = []
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch (e) { return "" } }
const lineAt = (t, i) => t.slice(0, i).split("\n").length
const paren = (t, from) => {
  let d = 0
  for (let i = from; i < t.length; i++) {
    if (t[i] === "(") d++
    else if (t[i] === ")") { d--; if (d === 0) return t.slice(from, i + 1) }
  }
  return t.slice(from)
}

const STATEMENT = /\b(SELECT|INSERT\s+INTO|REPLACE\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|CREATE\s+INDEX)\b/i
const WRITE = /\b(INSERT|REPLACE|UPDATE|DELETE)\b/i
let schema = sqlFiles.map(read).join("\n")
let seen = 0

for (const file of files) {
  const text = read(file)
  if (!STATEMENT.test(text)) continue

  let writes = 0
  for (const m of text.matchAll(/(["\x60])((?:[^"\x60\\]|\\.)*)\1/g)) {
    const sql = m[2]
    if (!STATEMENT.test(sql)) continue
    const at = `${file}:${lineAt(text, m.index)}`
    seen += 1
    schema += "\n" + sql

    if (!storeRe.test(file)) fails.push(`333 ${at} — SQL hors de la couche de stockage`)
    if (/\$\{/.test(sql) || /^\s*\+/.test(text.slice(m.index + m[0].length, m.index + m[0].length + 8)))
      fails.push(`334 ${at} — requête assemblée par interpolation`)
    if (/\b(VALUES|SET)\b/i.test(sql) && !/(\?|:[a-zA-Z_]|@[a-zA-Z_]|\$[a-zA-Z_])/.test(sql))
      fails.push(`335 ${at} — écriture sans paramètre lié`)
    if (/SELECT\s+\*/i.test(sql)) warns.push(`338 ${at} — sélection de toutes les colonnes`)
    if (WRITE.test(sql)) writes += 1
  }

  if (writes > 1 && !/\btransaction\s*\(/.test(text))
    fails.push(`336 ${file} — ${writes} écritures hors transaction`)

  for (const m of text.matchAll(/\btransaction\s*\(/g)) {
    const span = paren(text, m.index + m[0].length - 1)
    if (/\bawait\b|\bfetch\(|readFile|writeFile|\.publish\(/.test(span))
      warns.push(`337 ${file}:${lineAt(text, m.index)} — entrée-sortie dans une transaction`)
  }
}

if (/CREATE\s+TABLE/i.test(schema)) {
  const indexed = new Set()
  for (const m of schema.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX[^(]*\(([^)]*)\)/gi))
    for (const col of m[1].split(",")) indexed.add(col.trim().split(/\s+/)[0].replace(/["\x60\x27]/g, "").toLowerCase())
  for (const m of schema.matchAll(/(\w+)[^,(]*\b(PRIMARY\s+KEY|UNIQUE)\b/gi)) indexed.add(m[1].toLowerCase())
  for (const m of schema.matchAll(/\b(?:PRIMARY\s+KEY|UNIQUE)\s*\(([^)]*)\)/gi))
    for (const col of m[1].split(",")) indexed.add(col.trim().split(/\s+/)[0].replace(/["\x60\x27]/g, "").toLowerCase())
  indexed.add("rowid")

  for (const m of schema.matchAll(/\bWHERE\s+([A-Za-z_][\w.]*)\s*(=|<|>|LIKE|IN)/gi)) {
    const col = m[1].split(".").pop().toLowerCase()
    if (!indexed.has(col)) warns.push(`339 colonne de recherche "${col}" sans index`)
  }
}

for (const v of fails) console.log("FAIL: " + v)
for (const w of [...new Set(warns)]) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${seen} requête(s) SQL conformes`)
'
