#!/usr/bin/env bash
# vocabulary.sh — 397 abréviation · 398 variable d une lettre · 399 suffixe vide de sens
#                 401 module helpers · 402 module common · 410 suffixe Id · 395 fonction
#                 asynchrone nommée par un nom · 396 suffixe Handler · 412 tableau au
#                 singulier · 413 événement hors participe passé · 414 préfixe get inutile
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

DOCTOR_FILES="$FILES" \
DOCTOR_ABBREVIATIONS="${DOCTOR_ABBREVIATIONS:-tmp|val|vals|res|resp|req|err|errs|msg|msgs|obj|arr|idx|cnt|num|str|cfg|conf|btn|elem|elems|evt|attr|impl|mgr|svc|usr|pwd|addr|cb|len|ret|curr|nxt|func}" \
DOCTOR_EMPTY_SUFFIXES="${DOCTOR_EMPTY_SUFFIXES:-info|manager|helper|helpers|util|utils|service|wrapper|processor|stuff|thing|object}" \
DOCTOR_NOUN_ASYNC="${DOCTOR_NOUN_ASYNC:-data|info|config|result|response|payload|state|status|metadata|value|list|item|items}" \
DOCTOR_EVENT_ALLOW="${DOCTOR_EVENT_ALLOW:-error|data|close|end|open|input|drain|finish|ready|message|abort|timeout|exit}" \
DOCTOR_COLLECTION_WORDS="${DOCTOR_COLLECTION_WORDS:-list|set|map|queue|all|series|matrix|buffer|index|data|each|pool|table}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const abbreviations = new Set(process.env.DOCTOR_ABBREVIATIONS.split("|"))
const emptySuffixes = new Set(process.env.DOCTOR_EMPTY_SUFFIXES.split("|"))
const nounAsync = new Set(process.env.DOCTOR_NOUN_ASYNC.split("|"))
const eventAllow = new Set(process.env.DOCTOR_EVENT_ALLOW.split("|"))
const collections = new Set(process.env.DOCTOR_COLLECTION_WORDS.split("|"))
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s
  .replace(/"(?:\\.|[^"\\\n])*"/g, blank)
  .replace(/\x27(?:\\.|[^\x27\\\n])*\x27/g, blank)
  .replace(/`(?:\\[\s\S]|[^`\\])*`/g, blank)
  .replace(/\/\*[\s\S]*?\*\//g, blank)
  .replace(/\/\/[^\n]*/g, blank)

const wordsOf = (name) => name
  .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
  .replace(/[_#$]/g, " ")
  .toLowerCase()
  .split(/\s+/)
  .filter(Boolean)

const DECL = /(?:^|[^A-Za-z0-9_$.])(?:const|let|var|readonly|function|class|type)[ \t]+(#?[A-Za-z0-9_$]+)/g
const ANNOTATED = /(?:^|[^A-Za-z0-9_$."\x27])([A-Za-z_$][A-Za-z0-9_$]*)[ \t]*\??[ \t]*:[ \t]*[A-Za-z0-9_$({[]/g
const CAUGHT = /catch[ \t]*\([ \t]*([A-Za-z0-9_$]+)/g
const SINGLE = /^[ \t]*(?:export[ \t]+)?(?:const|let)[ \t]+([a-z])[ \t]*[=:]/
const ASYNC_FN = /(?:^|[^A-Za-z0-9_$.])(?:async[ \t]+function[ \t]+([A-Za-z0-9_$]+)|(?:const|let)[ \t]+([A-Za-z0-9_$]+)[ \t]*(?::[^=\n]*)?=[ \t]*async\b|async[ \t]+(#?[A-Za-z0-9_$]+)[ \t]*\()/g
const COLLECTION = /^[ \t]*(?:(?:export|readonly|private|public|static)[ \t]+)*(?:const|let)?[ \t]*(#?[A-Za-z0-9_$]+)[ \t]*(?::[ \t]*[^=\n]*(?:\[\]|Array<[^=\n]*>)[ \t]*)?=[ \t]*\[|^[ \t]*(?:(?:export|readonly|private|public|static)[ \t]+)*(?:const|let)?[ \t]*(#?[A-Za-z0-9_$]+)[ \t]*:[ \t]*[^=\n]*(?:\[\]|Array<[^=\n]*>)[ \t]*=/
const EMITTED = /\.?emit[ \t]*\([ \t]*["\x27]([A-Za-z0-9_:.-]+)["\x27]/g
const GETTER = /^[ \t]*(?:export[ \t]+)?(?:async[ \t]+)?(?:function[ \t]+|(?:const|let)[ \t]+)?(get[A-Z][A-Za-z0-9_$]*)[ \t]*\([ \t]*\)[ \t]*(?::[^\n{=]*)?(?:=>[ \t]*)?\{/
const ID_SUFFIX = /[a-z0-9](ID|Identifier|_id)(?![a-z])/

const violations = []
const warnings = []
let inspected = 0

for (const file of files) {
  const path = file.toLowerCase()
  if (/(^|\/|-|_)helpers?(\/|-|_|\.)/.test(path) && !/\/helpers\.ts$/.test(path)) {
    violations.push(`401 ${file}:1 — module ou dossier "helpers"`)
  }
  if (/(^|\/|-|_)common(\/|-|_|\.)/.test(path) && !/\/common\.ts$/.test(path)) {
    violations.push(`402 ${file}:1 — module ou dossier "common"`)
  }

  const raw = read(file)
  const text = strip(raw)
  const rawLines = raw.split("\n")

  text.split("\n").forEach((line, index) => {
    const at = `${file}:${index + 1}`
    const names = new Set()
    for (const pattern of [DECL, ANNOTATED, CAUGHT]) {
      let match
      pattern.lastIndex = 0
      while ((match = pattern.exec(line)) !== null) names.add(match[1])
    }

    for (const name of names) {
      inspected += 1
      const words = wordsOf(name)
      const abbreviation = words.find((w) => abbreviations.has(w))
      if (abbreviation) violations.push(`397 ${at} — "${name}" contient l abréviation "${abbreviation}"`)
      if (words.length > 1 && emptySuffixes.has(words[words.length - 1])) {
        violations.push(`399 ${at} — "${name}" porte un suffixe vide de sens`)
      }
      if (ID_SUFFIX.test(name)) violations.push(`410 ${at} — "${name}" doit se terminer par Id`)
      if (/[A-Za-z0-9](Handler|Callback|Listener|Cb)(?![a-z])/.test(name)) {
        warnings.push(`396 ${at} — "${name}" devrait être préfixé on/handle`)
      }
    }

    const single = SINGLE.exec(line)
    if (single) violations.push(`398 ${at} — variable "${single[1]}" d une seule lettre`)

    const getter = GETTER.exec(line)
    if (getter) warnings.push(`414 ${at} — "${getter[1]}" préfixé get sans calcul`)

    const collection = COLLECTION.exec(line)
    if (collection) {
      const name = collection[1] || collection[2]
      const words = wordsOf(name)
      const last = words[words.length - 1]
      if (last && !last.endsWith("s") && !collections.has(last)) {
        warnings.push(`412 ${at} — le tableau "${name}" porte un nom singulier`)
      }
    }

    let match
    ASYNC_FN.lastIndex = 0
    while ((match = ASYNC_FN.exec(line)) !== null) {
      const name = match[1] || match[2] || match[3]
      if (!name) continue
      const words = wordsOf(name)
      const last = words[words.length - 1]
      if (nounAsync.has(last)) warnings.push(`395 ${at} — la fonction asynchrone "${name}" n est pas un verbe`)
    }

    EMITTED.lastIndex = 0
    while ((match = EMITTED.exec(rawLines[index] || "")) !== null) {
      const event = match[1]
      const words = wordsOf(event.replace(/[:.-]/g, " "))
      const last = words[words.length - 1]
      if (!last || eventAllow.has(last) || last.endsWith("ed")) continue
      warnings.push(`413 ${at} — l événement "${event}" n est pas au participe passé`)
    }
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
if (warnings.length > 0) console.log(`OK: aucun nom fautif (${warnings.length} avertissement(s))`)
else console.log(`OK: ${inspected} identifiant(s) conformes`)
'
