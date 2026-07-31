#!/usr/bin/env bash
# tsconfig.sh — 43 strict · 44 noUncheckedIndexedAccess · 45 verbatimModuleSyntax
#               94 extension de la base · 437 noEmitOnError · 439 rootDir · 440 outDir
#               441 tests exclus du build · 442 allowJs
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

"$DOCTOR_DIR/utils/list-files.sh" tscfg | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const files = input.split("\n").filter(Boolean)
  if (files.length === 0) { console.log("OK: aucun tsconfig à inspecter"); return }

  const violations = []
  const BASE = "tsconfig.base.json"

  for (const file of files) {
    let cfg
    try { cfg = JSON.parse(fs.readFileSync(file, "utf8")) } catch (e) {
      violations.push(`94 ${file} — JSON invalide: ${e.message}`); continue
    }
    const o = cfg.compilerOptions ?? {}
    const isBase = file === BASE

    if (isBase) {
      if (o.strict !== true) violations.push(`43 ${file} — strict absent ou désactivé`)
      if (o.noUncheckedIndexedAccess !== true) violations.push(`44 ${file} — noUncheckedIndexedAccess désactivé`)
      if (o.verbatimModuleSyntax !== true) violations.push(`45 ${file} — verbatimModuleSyntax désactivé`)
      continue
    }

    if (!cfg.extends || !String(cfg.extends).includes("tsconfig.base.json"))
      violations.push(`94 ${file} — n étend pas la configuration de base`)
    if (o.strict === false) violations.push(`43 ${file} — strict désactivé localement`)
    if (o.noUncheckedIndexedAccess === false) violations.push(`44 ${file} — noUncheckedIndexedAccess désactivé localement`)
    if (o.allowJs === true) violations.push(`442 ${file} — allowJs activé`)
    if (o.noEmitOnError === false) violations.push(`437 ${file} — noEmitOnError désactivé`)
    if (!o.rootDir) violations.push(`439 ${file} — rootDir non déclaré`)
    if (o.outDir !== "dist") violations.push(`440 ${file} — outDir doit être "dist", trouvé ${JSON.stringify(o.outDir)}`)
    const excludes = cfg.exclude ?? []
    if (!excludes.some((e) => String(e).includes(".test.")))
      violations.push(`441 ${file} — les fichiers de test ne sont pas exclus du build`)
  }

  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${files.length} tsconfig conformes`)
})
'
