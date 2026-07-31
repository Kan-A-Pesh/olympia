#!/usr/bin/env bash
# render-loop.sh — 227 boucle d animation unique · 228 rendu par minuterie · 229 getContext par image
#                  230 redimensionnement par image · 231 conversion de texte par image
#                  232 allocation par image · 233 interrogation du DOM en boucle
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all \
  | grep -E '\.(ts|tsx|jsx|mjs)$' | grep -vE '\.(d|test|spec)\.tsx?$' || true)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier de rendu à inspecter"; exit 0; }

printf '%s\n' "$FILES" \
  | MAX_RAF_FILES="${DOCTOR_UI_MAX_RAF_FILES:-1}" \
    node -e '
const fs = require("node:fs")

const MAX_RAF_FILES = Number(process.env.MAX_RAF_FILES)

const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)
const fails = []
const warns = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length
const fail = (id, file, line, msg) => fails.push(`${id} ${file}:${line} — ${msg}`)
const warn = (id, file, line, msg) => warns.push(`${id} ${file}:${line} — ${msg}`)

const bodyAt = (text, from) => {
  const open = text.indexOf("{", from)
  if (open < 0) return null
  let depth = 0
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++
    else if (text[i] === "}") { depth--; if (depth === 0) return [open, i] }
  }
  return null
}

const FRAME_NAME = "\\w*(?:draw|render|paint|tick|frame)\\w*"
const FRAME_DECL = new RegExp(
  `(?:function\\s+${FRAME_NAME}\\s*\\([^()]*\\)|(?:const|let|var)\\s+${FRAME_NAME}\\s*=\\s*(?:function\\s*)?\\([^()]*\\)\\s*(?:=>)?)`,
  "gi",
)
const RAF_CALLBACK = /requestAnimationFrame\(\s*(?:\([^()]*\)|\w+)\s*=>/g
const LOOP_HEAD = /(^|[^.\w])(for|while)\s*\(/g

const rafFiles = []

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }

  const hasCanvas = /getContext\(|requestAnimationFrame\(/.test(text)
  if (/requestAnimationFrame\(/.test(text)) rafFiles.push(file)

  const regions = []
  for (const m of [...text.matchAll(FRAME_DECL), ...text.matchAll(RAF_CALLBACK)]) {
    const span = bodyAt(text, m.index + m[0].length - 1)
    if (span) regions.push(span)
  }
  const loops = []
  for (const m of text.matchAll(LOOP_HEAD)) {
    const span = bodyAt(text, m.index)
    if (span) loops.push(span)
  }

  const inAny = (spans, index) => spans.some((s) => index > s[0] && index < s[1])

  const flag = (pattern, spans, report) => {
    for (const m of text.matchAll(pattern)) {
      if (!inAny(spans, m.index)) continue
      report(lineOf(text, m.index), m[0].trim())
    }
  }

  for (const m of text.matchAll(/(^|[^.\w])setInterval\(/g)) {
    const near = text.slice(m.index, m.index + 400)
    if (!hasCanvas && !/(draw|render|repaint|redraw|paint)/i.test(near)) continue
    fail(228, file, lineOf(text, m.index), "rendu piloté par minuterie")
  }

  flag(/getContext\(/g, regions, (line) => fail(229, file, line, "contexte de dessin obtenu par image"))
  flag(/\w*[Cc]anvas\w*\.(width|height)\s*=[^=]/g, regions, (line, hit) =>
    fail(230, file, line, `canevas redimensionné par image (${hit.replace(/\s+/g, " ")})`))
  flag(/(devicePixelRatio|resizeCanvas\(|setTransform\()/g, regions, (line, hit) =>
    fail(230, file, line, `géométrie du canevas recalculée par image (${hit})`))
  flag(/(\.toFixed\(|\.toString\(|\.toLocaleString\(|(^|[^.\w])String\()/g, regions, (line, hit) =>
    warn(231, file, line, `conversion de texte dans la boucle de tracé (${hit.trim()})`))
  flag(/(new (Array|Float32Array|Float64Array|Int16Array|Uint8Array)\(|Array\.from\(|\.map\(|\.filter\(|\.slice\(|\.concat\(|\.split\(|=\s*\[\]|\.\.\.)/g, regions, (line, hit) =>
    fail(232, file, line, `allocation par image (${hit.trim()})`))
  flag(/document\.(querySelector|querySelectorAll|getElementById|getElementsByClassName|getElementsByTagName)\(/g,
    regions.concat(loops), (line, hit) => fail(233, file, line, `interrogation du DOM en boucle (${hit})`))
}

if (rafFiles.length > MAX_RAF_FILES)
  fails.push(`227 ${rafFiles.join(", ")} — ${rafFiles.length} boucles d animation, une seule est admise`)

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length === 0) console.log(`OK: ${files.length} fichier(s) sans travail superflu par image`)
'
