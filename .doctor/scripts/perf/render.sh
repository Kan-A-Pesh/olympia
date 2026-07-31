#!/usr/bin/env bash
# render.sh — 382 tri par image · 383 disposition recalculée par image · 387 décimation avant tracé
#             388 plus de points que de pixels · 390 attente asynchrone dans le tracé
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const RENDER = new RegExp(process.env.DOCTOR_RENDER_FN || "^(render|draw|paint|blit|tick|repaint)|(Render|Draw|Paint|Frame|Tick)")
const LAYOUT = /(getBoundingClientRect|offsetWidth|offsetHeight|clientWidth|clientHeight|getComputedStyle|computeLayout|\blayout\()/
const DECIMATE = new RegExp(process.env.DOCTOR_DECIMATE || "(decimat|downsample|minMax|min_max|stride|bucket|subsample)", "i")
const PLOT = /(lineTo|moveTo|fillRect|putImageData|strokeRect)\s*\(/
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
let seen = 0

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

const bodies = (text, s, keep) => {
  const out = []
  const add = (name, idx) => {
    if (!name || !keep.test(name)) return
    const open = s.indexOf("(", idx)
    if (open < 0) return
    const close = matchPair(s, open, "(", ")")
    if (close < 0) return
    let j = close + 1
    const limit = Math.min(s.length, close + 200)
    while (j < limit && s[j] !== "{" && s[j] !== ";") j++
    if (j >= limit || s[j] !== "{") return
    const end = matchPair(s, j, "{", "}")
    out.push({ name: name, line: lineOf(text, idx), body: text.slice(j, (end < 0 ? s.length : end) + 1) })
  }
  const patterns = [
    /\bfunction\s+([A-Za-z_$][\w$]*)\s*\(/g,
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]*)?=\s*(?:async\s+)?\(/g,
    /^[ \t]+(?:async\s+)?(#?[A-Za-z_$][\w$]*)\s*\(/gm,
  ]
  for (const re of patterns) {
    let m
    while ((m = re.exec(s))) add(m[1], m.index)
  }
  return out
}

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  const s = scrub(text)

  for (const fn of bodies(text, s, RENDER)) {
    seen++
    const where = file + ":" + fn.line + " (" + fn.name + ")"
    if (/\.sort\(/.test(fn.body)) fails.push("382 " + where + " — tri effectué à chaque image")
    if (LAYOUT.test(fn.body)) fails.push("383 " + where + " — disposition recalculée à chaque image")
    if (/(samples|waveform)/i.test(fn.body) && !DECIMATE.test(fn.body))
      fails.push("387 " + where + " — formes d onde tracées sans décimation")
    if (PLOT.test(fn.body) && !/[Ww]idth/.test(fn.body))
      fails.push("388 " + where + " — tracé non borné par la largeur en pixels")
    if (/\bawait\b/.test(fn.body)) fails.push("390 " + where + " — attente asynchrone dans le tracé")
  }
}

for (const f of fails) console.log("FAIL: " + f)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + seen + " fonction(s) de tracé conformes")
'
