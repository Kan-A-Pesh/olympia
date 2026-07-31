#!/usr/bin/env bash
# react-hygiene.sh — 235 objet de style en ligne · 236 liste sans clé · 237 index comme clé
#                    239 effet sans nettoyage · 240 écouteur non retiré · 241 état écrit pendant le rendu
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all \
  | grep -E '\.(ts|tsx|jsx)$' | grep -vE '\.(d|test|spec)\.tsx?$' || true)
[[ -z "$FILES" ]] && { echo "OK: aucun composant à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")

const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)
const fails = []
const warns = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length
const fail = (id, file, line, msg) => fails.push(`${id} ${file}:${line} — ${msg}`)
const warn = (id, file, line, msg) => warns.push(`${id} ${file}:${line} — ${msg}`)

const spanAt = (text, from, open, close) => {
  const start = text.indexOf(open, from)
  if (start < 0) return null
  let depth = 0
  for (let i = start; i < text.length; i++) {
    if (text[i] === open) depth++
    else if (text[i] === close) { depth--; if (depth === 0) return [start, i] }
  }
  return null
}

const INDEX_KEY = /^\s*[`"]?\$?\{?\s*(i|j|idx|index|\w+Index)\s*\}?[`"]?\s*$/
const SUBSCRIPTION = /(addEventListener\(|\.subscribe\(|setInterval\(|setTimeout\(|new WebSocket\(|\.on\(|\.watch\(|\.connect\()/
const NESTED_FN = /((\([^()]*\)|\w+)\s*=>\s*\{|function\s*\w*\s*\([^()]*\)\s*\{)/g
const COMPONENT = /(?:function\s+[A-Z]\w*\s*(?=\()|(?:const|let)\s+[A-Z]\w*\s*=\s*(?:function\s*)?(?=\())/g

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }
  const isJsx = /\.(tsx|jsx)$/.test(file)

  if (isJsx) {
    for (const m of text.matchAll(/(^|\s)style\s*=\s*\{\{/g))
      warn(235, file, lineOf(text, m.index), "objet de style recréé à chaque rendu")

    for (const m of text.matchAll(/key\s*=\s*\{([^{}]*)\}/g))
      if (INDEX_KEY.test(m[1]) || /(^|[^\w.])index(Of)?\b/.test(m[1]))
        fail(237, file, lineOf(text, m.index), `clé de liste dérivée de l index (${m[1].trim()})`)

    for (const m of text.matchAll(/\.map\s*\(/g)) {
      const span = spanAt(text, m.index, "(", ")")
      if (!span) continue
      const body = text.slice(span[0], span[1])
      if (!/<[A-Za-z]/.test(body)) continue
      if (!/\skey\s*=/.test(body))
        fail(236, file, lineOf(text, m.index), "liste rendue sans clé stable")
    }
  }

  const added = [...text.matchAll(/addEventListener\(/g)].filter((m) => {
    const span = spanAt(text, m.index, "(", ")")
    return !span || !/signal\s*:/.test(text.slice(span[0], span[1]))
  }).length
  const removed = [...text.matchAll(/removeEventListener\(/g)].length
  if (added > removed)
    fail(240, file, lineOf(text, text.indexOf("addEventListener(")), `${added} écouteur(s) ajouté(s) pour ${removed} retiré(s)`)

  for (const m of text.matchAll(/useEffect\s*\(/g)) {
    const span = spanAt(text, m.index, "{", "}")
    if (!span) continue
    const body = text.slice(span[0], span[1])
    if (!SUBSCRIPTION.test(body)) continue
    if (!/(^|[^\w.])return(\s|\()/.test(body))
      fail(239, file, lineOf(text, m.index), "effet abonné sans fonction de nettoyage")
  }

  for (const c of text.matchAll(COMPONENT)) {
    const params = spanAt(text, c.index + c[0].length, "(", ")")
    if (!params) continue
    const span = spanAt(text, params[1], "{", "}")
    if (!span) continue
    const body = text.slice(span[0], span[1])
    const setters = [...body.matchAll(/const\s*\[\s*\w+\s*,\s*(set[A-Z]\w*)\s*\]\s*=\s*useState/g)].map((s) => s[1])
    if (setters.length === 0) continue

    const nested = []
    for (const n of body.matchAll(NESTED_FN)) {
      const s = spanAt(body, n.index + n[0].length - 1, "{", "}")
      if (s) nested.push(s)
    }
    const call = new RegExp(`(^|[^\\w.])(${setters.join("|")})\\s*\\(`, "g")
    for (const s of body.matchAll(call)) {
      if (nested.some((n) => s.index > n[0] && s.index < n[1])) continue
      const before = body.slice(Math.max(0, s.index - 60), s.index)
      if (/=>\s*$/.test(before) || /\breturn\s*$/.test(before)) continue
      fail(241, file, lineOf(text, span[0] + s.index), `${s[2]} appelé pendant le rendu`)
    }
  }
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length === 0) console.log(`OK: ${files.length} fichier(s) de composants sans effet de bord de rendu`)
'
