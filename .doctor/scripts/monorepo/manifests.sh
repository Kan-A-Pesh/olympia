#!/usr/bin/env bash
# manifests.sh — 77 portée @olympia · 78 nom ↔ dossier · 79 protocole workspace
#                80 versions alignées · 81 apps privées · 82 exports · 83 files
#                84 type module · 91 scripts communs · 86/87/88 verrous
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
const path = require("node:path")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const manifests = all.filter((f) => /^(apps|packages)\/[^/]+\/package\.json$/.test(f))
  if (manifests.length === 0) { console.log("OK: aucun paquet à inspecter"); return }

  const violations = []
  const REQUIRED_SCRIPTS = ["build", "test", "typecheck"]
  const externalVersions = new Map()

  for (const file of manifests) {
    const dir = path.basename(path.dirname(file))
    const isApp = file.startsWith("apps/")
    let pkg
    try { pkg = JSON.parse(fs.readFileSync(file, "utf8")) } catch (e) {
      violations.push(`78 ${file} — JSON invalide: ${e.message}`); continue
    }

    if (!pkg.name?.startsWith("@olympia/")) violations.push(`77 ${file} — nom hors portée @olympia`)
    else if (pkg.name.slice("@olympia/".length) !== dir)
      violations.push(`78 ${file} — nom ${pkg.name} ne correspond pas au dossier ${dir}`)

    if (pkg.type !== "module") violations.push(`84 ${file} — "type": "module" absent`)
    if (isApp && pkg.private !== true) violations.push(`81 ${file} — une app doit être privée`)
    if (!isApp && !pkg.exports) violations.push(`82 ${file} — champ exports absent`)
    if (!isApp && !pkg.files) violations.push(`83 ${file} — champ files absent`)

    for (const s of REQUIRED_SCRIPTS)
      if (!pkg.scripts?.[s]) violations.push(`91 ${file} — script "${s}" manquant`)

    for (const field of ["dependencies", "devDependencies"]) {
      for (const [dep, range] of Object.entries(pkg[field] ?? {})) {
        if (dep.startsWith("@olympia/")) {
          if (range !== "workspace:*") violations.push(`79 ${file} — ${dep} doit être "workspace:*", trouvé "${range}"`)
          continue
        }
        const seen = externalVersions.get(dep)
        if (seen && seen.range !== range)
          violations.push(`80 ${file} — ${dep}@${range} diverge de ${seen.file}@${seen.range}`)
        else if (!seen) externalVersions.set(dep, { range, file })
      }
    }
  }

  if (all.includes("package-lock.json")) violations.push("86 package-lock.json versionné")
  if (all.includes("yarn.lock")) violations.push("87 yarn.lock versionné")
  const locks = all.filter((f) => f.endsWith("pnpm-lock.yaml"))
  if (locks.length !== 1 || locks[0] !== "pnpm-lock.yaml")
    violations.push(`88 verrou pnpm attendu à la racine uniquement, trouvé: ${locks.join(", ") || "aucun"}`)

  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${manifests.length} manifestes conformes`)
})
'
