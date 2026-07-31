#!/usr/bin/env bash
# regex.sh — 379 expression compilée en boucle · 380 expression hissée au niveau module
#            381 retour arrière exponentiel
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const HOT = new RegExp(process.env.DOCTOR_HOT_PATH || "(waveform|codec|decimat|render|draw|plot|canvas)")
const BACKTRACK = /\([^)]*(\+|\*|\{\d+,\d*\})[^)]*\)\s*(\+|\*|\{\d+,\d*\})/
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
let found = 0

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
const literal = () => /(^|[(,=:{&|?]|\breturn\b|=>)\s*(\/(?![\/*])(?:\\.|\[[^\]\n]*\]|[^\/\n\\])+\/[gimsuy]*)/g

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  const s = scrub(text)
  const at = (idx) => file + ":" + lineOf(text, idx)
  let m

  const fnRanges = []
  for (let i = 0; i < s.length; i++) {
    if (s[i] !== "{") continue
    const before = s.slice(Math.max(0, i - 200), i).replace(/\s+$/, "")
    if (!/(=>$|\)$|\)\s*:\s*[\w<>\[\]|&,.\s]*$|\bfunction\b[^{;]*$)/.test(before)) continue
    const close = matchPair(s, i, "{", "}")
    fnRanges.push([i, close < 0 ? s.length : close])
  }

  const loopRanges = []
  const loopRe = /\b(for|while)\s*\(/g
  while ((m = loopRe.exec(s))) {
    const open = m.index + m[0].length - 1
    const close = matchPair(s, open, "(", ")")
    if (close < 0) continue
    let j = close + 1
    while (j < s.length && /\s/.test(s[j])) j++
    let end
    if (s[j] === "{") end = matchPair(s, j, "{", "}")
    else { end = s.indexOf("\n", j); if (end < 0) end = s.length }
    loopRanges.push([j, end < 0 ? s.length : end])
    if (/new\s+RegExp\s*\(/.test(s.slice(j, end + 1)))
      fails.push("379 " + at(m.index) + " — expression régulière compilée dans une boucle")
  }

  const rxRe = literal()
  while ((m = rxRe.exec(s))) {
    const idx = m.index + m[0].indexOf(m[2])
    found++
    if (loopRanges.some((r) => idx > r[0] && idx < r[1]))
      fails.push("379 " + at(idx) + " — expression régulière littérale dans une boucle")
    else if (HOT.test(file) && fnRanges.some((r) => idx > r[0] && idx < r[1]))
      fails.push("380 " + at(idx) + " — expression régulière non hissée au niveau module")
    if (BACKTRACK.test(m[2])) fails.push("381 " + at(idx) + " — quantificateurs imbriqués, retour arrière exponentiel")
  }

  const ctorRe = new RegExp("new\\s+RegExp\\s*\\(\\s*[" + QUOTES + "]([^" + QUOTES + "\\n]*)[" + QUOTES + "]", "g")
  while ((m = ctorRe.exec(text))) {
    found++
    if (BACKTRACK.test(m[1])) fails.push("381 " + at(m.index) + " — quantificateurs imbriqués, retour arrière exponentiel")
  }
}

for (const f of fails) console.log("FAIL: " + f)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + found + " expression(s) régulière(s) conformes")
'
