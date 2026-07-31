#!/usr/bin/env bash
# ui.sh — 365 frontière d erreur par tuile · 366 erreur d appareil visible dans sa tuile
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" all)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier à inspecter"; exit 0; }

printf '%s\n' "$FILES" | node -e '
const fs = require("node:fs")
const all = fs.readFileSync(0, "utf8").split("\n").filter(Boolean)

const TILE = new RegExp(process.env.DOCTOR_TILE_FILE || "(^|/)[\\w.-]*tile[\\w.-]*\\.(tsx|jsx)$", "i")
const BOUNDARY = new RegExp(process.env.DOCTOR_ERROR_BOUNDARY || "ErrorBoundary|componentDidCatch|errorElement")

const components = all.filter((f) => /^(apps|packages)\/[^/]+\/src\/.*\.(tsx|jsx)$/.test(f))
const tiles = components.filter((f) => TILE.test(f))
if (tiles.length === 0) { console.log("OK: aucune tuile à inspecter"); process.exit(0) }

const fails = []
const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch (e) { return "" } }
const rootOf = (f) => f.split("/").slice(0, 2).join("/")

for (const root of new Set(tiles.map(rootOf))) {
  const guarded = components.filter((f) => rootOf(f) === root).some((f) => BOUNDARY.test(read(f)))
  if (!guarded) fails.push("365 " + root + " — tuiles sans frontière d erreur, un plantage emporte l interface")
}

for (const file of tiles) {
  if (!/[Ee]rror/.test(read(file))) fails.push("366 " + file + " — tuile sans rendu d erreur d appareil")
}

for (const f of fails) console.log("FAIL: " + f)
if (fails.length > 0) {
  console.log("")
  console.log("TOTAL: " + fails.length + " violation(s)")
  process.exit(1)
}
console.log("OK: " + tiles.length + " tuile(s) protégées")
'
