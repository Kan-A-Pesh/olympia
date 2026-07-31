#!/usr/bin/env bash
# pointer-free.sh — 213 affordance au survol · 214 propriété cursor · 215 gestionnaires souris
#                   216 attribut title · 217 focus supprimé · 218 outline none · 220 tabIndex positif
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all | grep -E '\.(tsx|jsx|css|scss)$' || true)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier d interface à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")

const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)
const violations = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length
const add = (id, file, line, msg) => violations.push(`${id} ${file}:${line} — ${msg}`)

const NATIVELY_FOCUSABLE = new Set(["button", "a", "input", "select", "textarea", "summary", "label", "details"])
const TAG = /<([A-Za-z][\w.-]*)((?:"[^"]*"|'"'"'[^'"'"']*'"'"'|\{(?:[^{}]|\{[^{}]*\})*\}|[^<>])*?)\/?>/g

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }

  if (/\.(css|scss)$/.test(file)) {
    for (const m of text.matchAll(/([^{}]*)\{([^{}]*)\}/g)) {
      const selector = m[1]
      const body = m[2]
      const at = lineOf(text, m.index + m[0].indexOf("{"))
      const hidden = /(^|[^-\w])(display|visibility|opacity|content)\s*:/.test(body)
      if (/:hover/.test(selector) && hidden) add(213, file, at, "information révélée au seul survol")
      const dropped = /(^|[^-\w])outline\s*:\s*(none|0)/.test(body)
      if (/:focus/.test(selector)) {
        if (dropped || /box-shadow\s*:\s*none/.test(body)) add(217, file, at, "style de focus supprimé")
      } else if (dropped && !/(box-shadow|outline-offset|border)\s*:/.test(body)) {
        add(218, file, at, "outline: none sans remplacement")
      }
    }
    for (const m of text.matchAll(/(^|[^-\w])cursor\s*:/g)) add(214, file, lineOf(text, m.index), "propriété cursor")
    continue
  }

  for (const m of text.matchAll(/(^|[^-\w])cursor\s*:/g)) add(214, file, lineOf(text, m.index), "propriété cursor")
  for (const m of text.matchAll(/(^|[^-\w])cursor-(pointer|help|grab|zoom-in|zoom-out)(\b|["'"'"'\s])/g))
    add(214, file, lineOf(text, m.index), "classe de curseur")
  for (const m of text.matchAll(/(^|[^-\w])(group-)?hover:(opacity|block|hidden|visible|flex|grid|inline|underline)/g))
    add(213, file, lineOf(text, m.index), "information révélée au seul survol")

  for (const m of text.matchAll(TAG)) {
    const tag = m[1]
    const attrs = m[2] || ""
    const at = lineOf(text, m.index)
    const lower = /^[a-z]/.test(tag)

    if (/(^|\s)on(Mouse|Pointer)[A-Z]\w*\s*=/.test(attrs))
      add(215, file, at, `<${tag}> écoute un événement de pointeur`)
    if (lower && /(^|\s)title\s*=/.test(attrs))
      add(216, file, at, `<${tag}> porte une infobulle native`)
    if (/(^|\s)tab[Ii]ndex\s*=\s*\{?\s*["'"'"']?\s*[1-9]/.test(attrs))
      add(220, file, at, `<${tag}> impose un tabIndex positif`)
    if (lower && !NATIVELY_FOCUSABLE.has(tag) && /(^|\s)onClick\s*=/.test(attrs) && !/(^|\s)onKey(Down|Up|Press)\s*=/.test(attrs))
      add(215, file, at, `<${tag}> actionnable au clic sans équivalent clavier`)
    if (/(^|\s)(focus:outline-none|outline-none)(\b|["'"'"'\s])/.test(attrs) && !/(focus|focus-visible):(ring|outline|border|shadow)/.test(attrs))
      add(217, file, at, `<${tag}> supprime le style de focus`)
  }
}

for (const v of violations) console.log(`FAIL: ${v}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${files.length} fichier(s) d interface pilotables sans pointeur`)
'
