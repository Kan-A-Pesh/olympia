#!/usr/bin/env bash
# logging.sh — 356 trace structurée · 357 niveau obligatoire · 358 chemin chaud · 359 charge utile
#              360 secret tracé · 361 empreinte tronquée · 362 journal injecté · 363 objet en message
#              364 décoration
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const HOT = new RegExp(process.env.DOCTOR_HOT_PATH || "(waveform|codec|decimat|render|draw|plot|canvas)")
const SECRET = /(token|secret|password|passwd|passphrase|credential|api_?key|private_?key|bearer)/i
const PAYLOAD = /\b(payload|samples|frame|frames|rawBody|body|chunk|packet|buffer)\b/
const TRUNCATED = /(slice|substring|substr|truncate|short|head|prefix)/
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{2139}]/u
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
const warns = []
let calls = 0

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

const matchParen = (s, open) => {
  let d = 0
  for (let i = open; i < s.length; i++) {
    if (s[i] === "(") d++
    else if (s[i] === ")") { d--; if (d === 0) return i }
  }
  return -1
}

const firstArg = (raw, masked) => {
  let d = 0
  for (let i = 0; i < masked.length; i++) {
    const c = masked[i]
    if (c === "(" || c === "[" || c === "{") d++
    else if (c === ")" || c === "]" || c === "}") d--
    else if (c === "," && d === 0) return raw.slice(0, i)
  }
  return raw
}

const lineOf = (text, idx) => text.slice(0, idx).split("\n").length
const CONCAT = new RegExp("[" + QUOTES + "][^" + QUOTES + "]*[" + QUOTES + "]\\s*\\+|\\+\\s*[" + QUOTES + "]")

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  const s = scrub(text)
  const at = (idx) => file + ":" + lineOf(text, idx)
  let m

  const impRe = new RegExp("^[ \\t]*import\\s+([^;\\n]*?)\\s+from\\s+[" + QUOTES + "]", "gm")
  while ((m = impRe.exec(text))) {
    const clause = m[1]
    if (/^type\b/.test(clause)) continue
    const names = clause.replace(/[{}]/g, " ").split(",").map((x) => x.trim().split(/\s+as\s+/).pop().trim())
    if (names.some((n) => /^(logger|log)$/.test(n)))
      warns.push("362 " + at(m.index) + " — journal importé globalement au lieu d être passé en paramètre")
  }

  const callRe = /(#?[A-Za-z_$][\w$]*)\s*\.\s*(trace|debug|info|warn|error|fatal|log|print)\s*\(/g
  while ((m = callRe.exec(s))) {
    const recv = m[1]
    const level = m[2]
    if (!(/^#?(log|logger)$/i.test(recv) || /(Logger|Log)$/.test(recv))) continue
    const open = m.index + m[0].length - 1
    const close = matchParen(s, open)
    if (close < 0) continue
    calls++
    const args = text.slice(open + 1, close)
    const head = firstArg(args, s.slice(open + 1, close))
    const where = at(m.index)

    if (level === "log" || level === "print") fails.push("357 " + where + " — trace sans niveau")
    if (CONCAT.test(head)) fails.push("356 " + where + " — message assemblé par concaténation")
    if (/\$\{/.test(head)) fails.push("363 " + where + " — variable interpolée dans le texte du message")
    if (HOT.test(file)) fails.push("358 " + where + " — trace dans le chemin des formes d onde")
    if (PAYLOAD.test(args)) fails.push("359 " + where + " — charge utile complète tracée")
    if (SECRET.test(args)) fails.push("360 " + where + " — secret tracé")
    if (EMOJI.test(args)) fails.push("364 " + where + " — décoration dans une trace machine")
    if (/fingerprint/i.test(args) && !TRUNCATED.test(args))
      warns.push("361 " + where + " — empreinte tracée sans troncature")
  }
}

for (const f of fails) console.log("FAIL: " + f)
for (const w of warns) console.log("WARN: " + w)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + calls + " appel(s) de journal conformes")
'
