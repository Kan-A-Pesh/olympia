#!/usr/bin/env bash
# lifecycle.sh — 251 signaux · 252 arrêt ferme les transports · 253 rejet non traité
#                254 exception non rattrapée · 259 minuteries annulées · 260 minuterie de fond
#                279 état exposé · 280 version au démarrage
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }
PKGS=$("$DOCTOR_DIR/utils/list-files.sh" pkg)

DOCTOR_FILES="$FILES" \
DOCTOR_PKGS="$PKGS" \
DOCTOR_DAEMON_ENTRY="${DOCTOR_DAEMON_ENTRY:-^apps/[^/]+/src/(main|daemon)\.ts$|^apps/iris-hub/src/index\.ts$}" \
node -e '
const fs = require("node:fs")

const files = (process.env.DOCTOR_FILES || "").split("\n").filter(Boolean)
const pkgs = (process.env.DOCTOR_PKGS || "").split("\n").filter(Boolean)
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }

const entryPattern = new RegExp(process.env.DOCTOR_DAEMON_ENTRY)
const entries = new Set(files.filter((f) => entryPattern.test(f)))

for (const manifest of pkgs) {
  if (!manifest.startsWith("apps/")) continue
  const dir = manifest.slice(0, manifest.lastIndexOf("/"))
  let json
  try { json = JSON.parse(read(manifest)) } catch { continue }
  const bin = typeof json.bin === "string" ? [json.bin] : Object.values(json.bin || {})
  for (const raw of [json.main, json.module, ...bin].filter((v) => typeof v === "string")) {
    const rel = raw.replace(/^\.\//, "").replace(/^dist\//, "").replace(/\.[cm]?js$/, ".ts")
    const guess = dir + "/src/" + rel
    if (files.includes(guess)) entries.add(guess)
  }
}

const violations = []
const warnings = []

for (const file of entries) {
  const text = read(file)
  const lines = text.split("\n")

  if (!/SIGTERM/.test(text)) violations.push(`251 ${file} — aucun traitement de SIGTERM`)
  if (!/SIGINT/.test(text)) violations.push(`251 ${file} — aucun traitement de SIGINT`)

  if (/SIGTERM|SIGINT/.test(text) && !/\.(close|end|destroy|stop|disconnect)\s*\(/.test(text))
    violations.push(`252 ${file} — arrêt qui ne ferme aucun transport`)

  if (!/unhandledRejection/.test(text))
    violations.push(`253 ${file} — aucun gestionnaire global de rejet`)

  const caught = lines.findIndex((l) => /uncaughtException/.test(l))
  if (caught === -1) {
    violations.push(`254 ${file} — aucun gestionnaire d exception non rattrapée`)
  } else {
    const body = lines.slice(caught, caught + 6).join("\n")
    if (!/(exit|log|logger|error|fatal|throw)/i.test(body.replace(/uncaughtException/g, "")))
      violations.push(`254 ${file}:${caught + 1} — exception non rattrapée ignorée`)
  }

  if (!/health|readiness|liveness/i.test(text))
    warnings.push(`279 ${file} — le daemon n expose pas son état`)
  if (!/version/i.test(text))
    warnings.push(`280 ${file} — le démarrage ne trace pas la version`)
}

for (const file of files) {
  const text = read(file)
  const lines = text.split("\n")

  lines.forEach((line, i) => {
    const where = `${file}:${i + 1}`
    if (/\bsetInterval\s*\(/.test(line)) {
      if (!/\bclearInterval\s*\(/.test(text)) violations.push(`259 ${where} — setInterval jamais annulé`)
      if (!/\.unref\s*\(\s*\)/.test(text)) warnings.push(`260 ${where} — minuterie de fond sans unref`)
    }
    if (/=\s*setTimeout\s*\(/.test(line) && !/\bclearTimeout\s*\(/.test(text))
      violations.push(`259 ${where} — minuterie mémorisée jamais annulée`)
  })
}

for (const v of violations) console.log(`FAIL: ${v}`)
for (const w of warnings) console.log(`WARN: ${w}`)
if (violations.length > 0) {
  console.log("")
  console.log(`TOTAL: ${violations.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: cycle de vie vérifié sur ${entries.size} point(s) d entrée`)
'
