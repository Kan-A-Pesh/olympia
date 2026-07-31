#!/usr/bin/env bash
# hot-loops.sh — 376 clé construite en boucle · 377 allocation par échantillon
#                378 fermeture créée en boucle · 386 calcul cryptographique en boucle
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const HOT = new RegExp(process.env.DOCTOR_HOT_LOOP || "(sample|waveform|pixel|channel[Dd]ata|points?\\b)", "i")
const ALLOC = /(new\s+[A-Z][\w$]*\s*\(|\.push\(\s*\{|\.concat\(|=\s*\{[^}]*:)/
const CRYPTO = /(createHash|createHmac|randomBytes|pbkdf2Sync|scryptSync|subtle\.digest|\.digest\()/
const KEY = /(`[^`]*\$\{|\.set\(\s*`|\[\s*`)/
const CLOSURE = /(=>|\bfunction\s*\()/
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
const warns = []
let hot = 0

const scrub = (text) => {
  const out = text.split("")
  const n = text.length
  const blank = (i) => { if (i >= 0 && i < n && text[i] !== "\n") out[i] = " " }
  let i = 0
  while (i < n) {
    const c = text[i]
    if (c === "/" && text[i + 1] === "/") { while (i < n && text[i] !== "\n") { blank(i); i++ } ; continue }
    if (c === "/" && text[i + 1] === "*") {
      while (i < n && !(text[i] === "*" && text[i + 1] === "/")) { blank(i); i++ }
      blank(i); blank(i + 1); i += 2; continue
    }
    if (QUOTES.includes(c)) {
      i++
      while (i < n && text[i] !== c) {
        if (text[i] === "\\") { blank(i); blank(i + 1); i += 2; continue }
        blank(i); i++
      }
      i++; continue
    }
    i++
  }
  return out.join("")
}

const matchPair = (s, open, o, c) => {
  let d = 0
  for (let i = open; i < s.length; i++) {
    if (s[i] === o) d++
    else if (s[i] === c) { d--; if (d === 0) return i }
  }
  return -1
}

const lineOf = (text, idx) => text.slice(0, idx).split("\n").length

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  const s = scrub(text)
  let m

  const loopRe = /\b(for|while)\s*\(/g
  while ((m = loopRe.exec(s))) {
    const open = m.index + m[0].length - 1
    const close = matchPair(s, open, "(", ")")
    if (close < 0) continue
    if (!HOT.test(text.slice(open, close + 1))) continue

    let j = close + 1
    while (j < s.length && /\s/.test(s[j])) j++
    let end
    if (s[j] === "{") end = matchPair(s, j, "{", "}")
    else { end = s.indexOf("\n", j); if (end < 0) end = s.length }
    if (end < 0) continue

    hot++
    const body = text.slice(j, end + 1)
    const where = file + ":" + lineOf(text, m.index)

    if (ALLOC.test(body)) fails.push("377 " + where + " — objet alloué à chaque échantillon")
    if (CRYPTO.test(body)) fails.push("386 " + where + " — calcul cryptographique répété en boucle")
    if (KEY.test(body)) warns.push("376 " + where + " — clé construite par concaténation en boucle chaude")
    if (CLOSURE.test(body)) warns.push("378 " + where + " — fonction créée dans une boucle chaude")
  }
}

for (const f of fails) console.log("FAIL: " + f)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + hot + " boucle(s) chaude(s) sans allocation")
'
