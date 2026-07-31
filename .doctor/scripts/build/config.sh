#!/usr/bin/env bash
# config.sh — 446 schéma d environnement · 447 process.env hors configuration
#             448 configuration figée · 449 secret par défaut · 450 adresse locale
#             451 port en dur
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

export DOCTOR_CONFIG_PATTERN="${DOCTOR_CONFIG_PATTERN:-(^|/)(config|env)\.ts$|(^|/)(config|env)/[^/]+\.ts$|\.config\.[cm]?ts$}"

"$DOCTOR_DIR/utils/list-files.sh" ts | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const files = input.split("\n").filter(Boolean)
  if (files.length === 0) { console.log("OK: aucune source a inspecter"); return }

  const IS_CONFIG = new RegExp(process.env.DOCTOR_CONFIG_PATTERN)
  const IS_APP_CONFIG = /(^|\/)(config|env)\.[cm]?ts$|(^|\/)(config|env)\/[^\/]+\.[cm]?ts$/
  const IS_TEST = /\.(test|spec)\.[cm]?ts$/
  const ENV_READ = /process\.env\b/
  const SECRET_DEFAULT = /(SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIAL)[A-Z_]*\s*("|\])?\s*(\?\?|\|\|)\s*"[^"]+"/
  const LOCAL_ADDRESS = /(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])/
  const PORT_LITERAL = /\bport[A-Za-z0-9_]*\s*[:=]\s*\d{2,5}\b/i
  const PORT_CONSTANT = /[A-Z][A-Z0-9]*_PORT\s*[:=]\s*\d{2,5}\b/
  const PORT_URL = /\/\/[A-Za-z0-9._-]+:\d{2,5}/
  const PORT_LISTEN = /\.listen\s*\(\s*\d{2,5}/
  const SCHEMA = /(z|schema)\.object\s*\(|safeParse\s*\(|\.parse\s*\(/

  const violations = []
  const warnings = []
  const configFiles = files.filter((f) => IS_CONFIG.test(f))
  let envReaders = 0
  let schemaFound = false

  for (const file of files) {
    const isConfig = IS_CONFIG.test(file)
    const isTest = IS_TEST.test(file)
    let text
    try { text = fs.readFileSync(file, "utf8") } catch { continue }
    if (isConfig && SCHEMA.test(text)) schemaFound = true
    if (IS_APP_CONFIG.test(file) && !/Object\.freeze|as const/.test(text))
      warnings.push(`448 ${file} — configuration modifiable apres chargement, figer avec Object.freeze ou as const`)

    const lines = text.split("\n")
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]
      const at = `${file}:${i + 1}`
      if (ENV_READ.test(line)) {
        envReaders += 1
        if (!isConfig && !isTest) violations.push(`447 ${at} — process.env lu hors du point de configuration`)
      }
      if (isTest) continue
      if (SECRET_DEFAULT.test(line)) violations.push(`449 ${at} — valeur secrete par defaut`)
      if (LOCAL_ADDRESS.test(line) && !isConfig) violations.push(`450 ${at} — adresse locale en dur`)
      if (PORT_LITERAL.test(line) || PORT_CONSTANT.test(line) || PORT_URL.test(line) || PORT_LISTEN.test(line))
        violations.push(`451 ${at} — numero de port en dur`)
    }
  }

  if (envReaders > 0 && !schemaFound)
    violations.push(`446 aucun schema de variables d environnement, ${envReaders} lecture(s) de process.env sans validation`)

  for (const w of warnings) console.log(`WARN: ${w}`)
  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${files.length} sources sans configuration en dur (${configFiles.length} point(s) de configuration)`)
})
'
