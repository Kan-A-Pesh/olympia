#!/usr/bin/env bash
# exceptions.sh — 345 classe de base · 346 code stable · 347 codes uniques · 348 codes répertoriés
#                 349 secret en message · 350 pile affichée · 351 capture restreinte
#                 352 capture générique · 353 relance avec cause · 354 nul sur erreur · 355 style unique
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const BASE = process.env.DOCTOR_ERROR_BASE || ""
const TABLE = new RegExp(process.env.DOCTOR_ERROR_CODES || "error-codes\\.ts$")
const TRANSPORT = new RegExp(process.env.DOCTOR_TRANSPORT_PATH || "(transport|mqtt|serial|usb|socket|broker)")
const SECRET = /(token|secret|password|passwd|passphrase|credential|api_?key|private_?key|bearer)/i
const NARROW = /(instanceof|typeof\s|safeParse|isError|ZodError|\.name\s*===)/
const QUOTES = [34, 39, 96].map((c) => String.fromCharCode(c)).join("")

const fails = []
const warns = []

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

const roots = []
const codes = []
const tables = []

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch (e) { continue }
  if (TABLE.test(file)) { tables.push(text); continue }

  const s = scrub(text)
  const at = (idx) => file + ":" + lineOf(text, idx)
  let m

  const classRe = /\bclass\s+([A-Za-z_$][\w$]*)(?:\s+extends\s+([A-Za-z_$][\w$.]*))?/g
  while ((m = classRe.exec(s))) {
    const name = m[1]
    const parent = m[2]
    const open = s.indexOf("{", m.index)
    const end = open < 0 ? -1 : matchPair(s, open, "{", "}")
    const body = end < 0 ? "" : text.slice(open, end)
    if (!(/Error$/.test(name) || (parent && /Error$/.test(parent)) || (BASE && parent === BASE))) continue
    if (!parent) fails.push("345 " + at(m.index) + " — la classe " + name + " ne dérive d aucune classe d erreur")
    if (parent === "Error") roots.push({ name: name, where: at(m.index) })
    if (!/\bcode\b/.test(body)) fails.push("346 " + at(m.index) + " — la classe " + name + " ne porte aucun code stable")
  }

  const codeRe = new RegExp("\\bcode\\s*[:=]\\s*[" + QUOTES + "]([A-Z][A-Z0-9_]{2,})[" + QUOTES + "]", "g")
  while ((m = codeRe.exec(text))) codes.push({ code: m[1], where: at(m.index) })

  const throwRe = /\bthrow\s+new\s+[A-Za-z_$][\w$.]*\s*\(/g
  while ((m = throwRe.exec(s))) {
    const open = m.index + m[0].length - 1
    const close = matchPair(s, open, "(", ")")
    if (close < 0) continue
    const parts = text.slice(open, close + 1).match(/\$\{[^}]*\}/g) || []
    if (parts.some((p) => SECRET.test(p)))
      fails.push("349 " + at(m.index) + " — secret interpolé dans un message d erreur")
  }

  const stackRe = /(\$\{[^}]*\.stack\b|\{\s*[\w$.]*\.stack\s*\}|\+\s*[\w$.]*\.stack\b)/g
  while ((m = stackRe.exec(text))) fails.push("350 " + at(m.index) + " — pile d appel insérée dans un texte affiché")

  const catchRe = /\bcatch\s*\(\s*([A-Za-z_$][\w$]*)[^)]*\)\s*\{/g
  while ((m = catchRe.exec(s))) {
    const open = m.index + m[0].length - 1
    const end = matchPair(s, open, "{", "}")
    if (end < 0) continue
    const body = text.slice(open, end + 1)
    const used = new RegExp("\\b" + m[1] + "\\.(message|stack|name|code|errno|cause)\\b").test(body)
    if (used && !NARROW.test(body)) fails.push("351 " + at(m.index) + " — capture utilisée sans restriction de type")
    if (/\bthrow\s+new\s/.test(body) && !/\bcause\b/.test(body))
      fails.push("353 " + at(m.index) + " — relance sans cause d origine")
    if (/\breturn\s+(null|undefined|false)\b/.test(body))
      warns.push("354 " + at(m.index) + " — erreur signalée par une valeur nulle")
    if (TRANSPORT.test(file) && !/(\bthrow\b|\bemit\(|\breject\(|\bcause\b)/.test(body))
      warns.push("352 " + at(m.index) + " — capture générique dans un transport")
  }

  const resultRe = /(\btype\s+[\w$]*\s*(?:<[^>]*>)?\s*=[^;\n]{0,120}\bok\s*:\s*(?:true|false)\b|(?:^|[^\w$])(?:Result|Either)\s*<|\{\s*ok\s*:\s*(?:true|false)\s*[,;}])/g
  while ((m = resultRe.exec(s))) fails.push("355 " + at(m.index) + " — type résultat au lieu d une exception")
}

if (BASE) {
  for (const r of roots) if (r.name !== BASE)
    fails.push("345 " + r.where + " — " + r.name + " dérive de Error au lieu de " + BASE)
} else if (roots.length > 1) {
  for (const r of roots)
    fails.push("345 " + r.where + " — " + r.name + " dérive directement de Error, une seule classe de base attendue")
}

const seen = new Map()
for (const c of codes) {
  if (seen.has(c.code)) fails.push("347 " + c.where + " — code " + c.code + " déjà déclaré en " + seen.get(c.code))
  else seen.set(c.code, c.where)
}

if (codes.length > 0) {
  if (tables.length === 0) fails.push("348 — " + seen.size + " code(s) émis mais aucune table de codes")
  else for (const c of codes) if (!tables.some((t) => t.includes(c.code)))
    fails.push("348 " + c.where + " — code " + c.code + " absent de la table des codes")
}

const unique = (list) => [...new Set(list)]
const hard = unique(fails)
for (const f of hard) console.log("FAIL: " + f)
for (const w of unique(warns)) console.log("WARN: " + w)
if (hard.length > 0) {
  console.log("")
  console.log("TOTAL: " + hard.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + seen.size + " code(s) d erreur, exceptions conformes")
'
