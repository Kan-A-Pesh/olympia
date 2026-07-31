#!/usr/bin/env bash
# readability.sh — 221 taille de texte minimale · 222 dimensions en pixels · 224 état signalé
#                  par la seule couleur · 225 animation permanente · 226 préférence de mouvement réduit
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all | grep -E '\.(tsx|jsx|css|scss)$' || true)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier d interface à inspecter"; exit 0; }

printf '%s\n' "$FILES" \
  | MIN_FONT_PX="${DOCTOR_UI_MIN_FONT_PX:-14}" \
    ROOT_FONT_PX="${DOCTOR_UI_ROOT_FONT_PX:-16}" \
    MAX_LAYOUT_PX="${DOCTOR_UI_MAX_LAYOUT_PX:-2}" \
    node -e '
const fs = require("node:fs")

const MIN_FONT = Number(process.env.MIN_FONT_PX)
const ROOT_FONT = Number(process.env.ROOT_FONT_PX)
const MAX_LAYOUT = Number(process.env.MAX_LAYOUT_PX)

const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)
const fails = []
const warns = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length
const fail = (id, file, line, msg) => fails.push(`${id} ${file}:${line} — ${msg}`)
const warn = (id, file, line, msg) => warns.push(`${id} ${file}:${line} — ${msg}`)

const COLOR_ONLY = /^(color|background|background-color|border-color|fill|stroke|opacity|box-shadow)$/
const STATUS_SELECTOR = /(^|[.\-_])(status|state|online|offline|stale|degraded|relayed|ok|error|warning|alert|success|danger|failed|connected|disconnected)([.\-_:\s]|$)/i
const TAILWIND_FONT = [["text-xs", 12], ["text-2xs", 10], ["text-tiny", 10]]

let hasMotion = false
let hasReducedMotion = false

const fontPx = (value, unit) => {
  if (unit === "px") return value
  if (unit === "rem" || unit === "em") return value * ROOT_FONT
  if (unit === "pt") return value * (96 / 72)
  return null
}

for (const file of files) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }

  if (/prefers-reduced-motion/.test(text)) hasReducedMotion = true
  if (/(^|[^-\w])(animation|transition)(-duration|-name|-iteration-count)?\s*:/.test(text)) hasMotion = true

  for (const m of text.matchAll(/(^|[^-\w])font-?[sS]ize\s*:\s*["'"'"']?\s*([0-9.]+)(px|rem|em|pt)/g)) {
    const px = fontPx(Number(m[2]), m[3])
    if (px !== null && px < MIN_FONT)
      fail(221, file, lineOf(text, m.index), `texte à ${px} px, minimum ${MIN_FONT} px`)
  }
  for (const entry of TAILWIND_FONT) {
    if (entry[1] >= MIN_FONT) continue
    for (const m of text.matchAll(new RegExp(`(^|[^-\\w])${entry[0]}(\\b|["'"'"'\\s])`, "g")))
      fail(221, file, lineOf(text, m.index), `classe ${entry[0]} sous ${MIN_FONT} px`)
  }
  for (const m of text.matchAll(/(^|[^-\w])text-\[([0-9.]+)(px|rem|pt)\]/g)) {
    const px = fontPx(Number(m[2]), m[3])
    if (px !== null && px < MIN_FONT)
      fail(221, file, lineOf(text, m.index), `texte à ${px} px, minimum ${MIN_FONT} px`)
  }

  for (const m of text.matchAll(/(^|[^-\w])(min-|max-)?(width|height)\s*:\s*["'"'"']?\s*([0-9.]+)px/g)) {
    if (Number(m[4]) <= MAX_LAYOUT) continue
    warn(222, file, lineOf(text, m.index), `dimension figée à ${m[4]}px, préférer une unité relative`)
  }

  for (const m of text.matchAll(/(^|[^-\w])animation(-iteration-count)?\s*:[^;{}]*infinite/g))
    warn(225, file, lineOf(text, m.index), "animation permanente concurrente du tracé")

  if (!/\.(css|scss)$/.test(file)) continue

  for (const m of text.matchAll(/([^{}]*)\{([^{}]*)\}/g)) {
    const selector = m[1].trim()
    const body = m[2]
    if (selector.startsWith("@") || !STATUS_SELECTOR.test(selector)) continue
    const props = [...body.matchAll(/(^|[;{\s])([a-z-]+)\s*:/g)].map((p) => p[2])
    if (props.length === 0) continue
    if (props.every((p) => COLOR_ONLY.test(p)))
      fail(224, file, lineOf(text, m.index + m[0].indexOf("{")), `"${selector}" ne se distingue que par la couleur`)
  }
}

if (hasMotion && !hasReducedMotion)
  warns.push("226 — des animations sont déclarées sans requête prefers-reduced-motion")

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length === 0) console.log(`OK: ${files.length} fichier(s) d interface lisibles à distance`)
'
