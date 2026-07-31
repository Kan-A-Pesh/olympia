#!/usr/bin/env bash
# sqlite.sh — 323 journalisation anticipée · 324 clés étrangères · 325 délai sur verrou
#             326 synchronisation explicite · 327 base hors partition en recouvrement
#             328 chemin issu de la configuration · 344 base illisible recréée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

export DOCTOR_FILES="$FILES"
export DOCTOR_DB_CONFIG="${DOCTOR_DB_CONFIG:-(^|/)(config|settings|env)[^/]*\.ts$}"
export DOCTOR_DB_PERSIST="${DOCTOR_DB_PERSIST:-^/(data|mnt|media|srv|boot)/}"

node -e '
const fs = require("node:fs")
const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const configRe = new RegExp(process.env.DOCTOR_DB_CONFIG)
const persistRe = new RegExp(process.env.DOCTOR_DB_PERSIST)
const fails = []
const lineAt = (t, i) => t.slice(0, i).split("\n").length

let opened = 0
for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }

  for (const m of text.matchAll(/["\x60]([^"\x60\n]*\.(?:db|sqlite|sqlite3))["\x60]/g)) {
    const at = `${file}:${lineAt(text, m.index)}`
    if (!configRe.test(file)) fails.push(`328 ${at} — chemin de base en dur hors configuration: ${m[1]}`)
    if (m[1].startsWith("/") && !persistRe.test(m[1]))
      fails.push(`327 ${at} — base sur la partition en recouvrement: ${m[1]}`)
  }

  if (!/(better-sqlite3|node:sqlite|DatabaseSync|new Database\s*\()/.test(text)) continue
  opened += 1

  if (!/journal_mode[^a-zA-Z]*wal/i.test(text))
    fails.push(`323 ${file} — journalisation par écriture anticipée non activée`)
  if (!/foreign_keys[^a-zA-Z]*(on|true|1)/i.test(text))
    fails.push(`324 ${file} — clés étrangères non activées`)
  if (!/busy_timeout/i.test(text))
    fails.push(`325 ${file} — aucun délai d attente sur verrou`)
  if (!/\bsynchronous\b/i.test(text))
    fails.push(`326 ${file} — mode de synchronisation non déclaré`)
  if (!/\btry\s*\{/.test(text) || !/(unlinkSync|rmSync|renameSync|recreate|recover)/i.test(text))
    fails.push(`344 ${file} — ouverture sans reprise sur base illisible`)
}

for (const v of fails) console.log("FAIL: " + v)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${opened} ouverture(s) de base conformes`)
'
