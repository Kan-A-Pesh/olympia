#!/usr/bin/env bash
# codec.sh — 373 tampon réalloué au lieu d être réutilisé · 391 mesure de performance du codec
#            392 borne mesurée sur le chemin chaud
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SRC=$("$DOCTOR_DIR/utils/list-files.sh" src)
ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)
[[ -z "$SRC" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n===\n%s\n' "$SRC" "$ALL" | node -e '
const fs = require("node:fs")
const input = fs.readFileSync(0, "utf8").split("\n===\n")
const files = (input[0] || "").split("\n").filter(Boolean)
const all = (input[1] || "").split("\n").filter(Boolean)

const FRAME = new RegExp(process.env.DOCTOR_FRAME_FN || "^(render|draw|paint|blit|tick|repaint)|(Render|Draw|Paint|Frame|Tick)")
const CODEC = new RegExp(process.env.DOCTOR_CODEC_FILE || "(waveform|codec)\\.ts$")
const BENCH = new RegExp(process.env.DOCTOR_BENCH_FILE || "(\\.bench\\.(ts|js)$|(^|/)bench(es|marks)?/)")
const BUFFER = /new\s+(Uint8Array|Uint16Array|Int16Array|Int32Array|Float32Array|Float64Array|ArrayBuffer|SharedArrayBuffer)\s*\(|Buffer\.alloc(Unsafe)?\s*\(/
const BOUND = /(toBeLessThan|toBeLessThanOrEqual|toBeBelow|budgetMs|maxMs|threshold)/
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
const warns = []
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
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch (e) { return "" } }

for (const file of files) {
  const text = read(file)
  const s = scrub(text)
  const add = (name, idx) => {
    if (!name || !FRAME.test(name)) return
    const open = s.indexOf("(", idx)
    if (open < 0) return
    const close = matchPair(s, open, "(", ")")
    if (close < 0) return
    let j = close + 1
    const limit = Math.min(s.length, close + 200)
    while (j < limit && s[j] !== "{" && s[j] !== ";") j++
    if (j >= limit || s[j] !== "{") return
    const end = matchPair(s, j, "{", "}")
    seen++
    const body = text.slice(j, (end < 0 ? s.length : end) + 1)
    if (BUFFER.test(body))
      fails.push("373 " + file + ":" + lineOf(text, idx) + " (" + name + ") — tampon réalloué à chaque image")
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
}

const codecs = files.filter((f) => CODEC.test(f))
if (codecs.length > 0) {
  const benches = all.filter((f) => BENCH.test(f) || /(bench\(|performance\.now\()/.test(read(f)))
  if (benches.length === 0) warns.push("391 " + codecs[0] + " — codec binaire sans mesure de performance")
  else {
    const bounded = benches.some((f) => BOUND.test(read(f)))
    if (!bounded) warns.push("392 " + benches[0] + " — mesure sans borne vérifiée sur le chemin chaud")
  }
}

for (const f of fails) console.log("FAIL: " + f)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + seen + " fonction(s) par image sans réallocation")
'
