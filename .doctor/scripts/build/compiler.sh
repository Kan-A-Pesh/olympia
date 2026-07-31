#!/usr/bin/env bash
# compiler.sh — 433 cible ↔ Node · 434 DOM hors navigateur · 435 cartes de déclaration
#               436 sources embarquées · 438 compilation incrémentale (cache turbo)
#               444 configuration de test homogène · 445 option répétée d un paquet à l autre
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

export DOCTOR_TS_TARGET="${DOCTOR_TS_TARGET:-}"
export DOCTOR_DOM_PACKAGES="${DOCTOR_DOM_PACKAGES:-packages/hermes-protocol packages/tiles-ui apps/helios-server}"
export DOCTOR_CONFIG_DUP_MIN="${DOCTOR_CONFIG_DUP_MIN:-2}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
const path = require("node:path")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const configs = all.filter((f) => /^(apps|packages)\/[^\/]+\/tsconfig[^\/]*\.json$/.test(f))
  const violations = []
  const warnings = []

  const words = (name) => (process.env[name] ?? "").split(/[\s,]+/).filter(Boolean)
  const DOM_ALLOWED = words("DOCTOR_DOM_PACKAGES")
  const DUP_MIN = Number(process.env.DOCTOR_CONFIG_DUP_MIN) || 2
  const PATH_OPTIONS = new Set(["outDir", "rootDir", "rootDirs", "baseUrl", "paths", "typeRoots",
    "tsBuildInfoFile", "outFile", "declarationDir"])
  const TARGET_BY_NODE = { 18: "ES2022", 20: "ES2023", 22: "ES2023", 24: "ES2024" }

  const readJson = (file) => {
    try { return JSON.parse(fs.readFileSync(file, "utf8")) } catch { return null }
  }

  const effective = (file, cfg) => {
    const chain = []
    let current = cfg
    let currentFile = file
    for (let depth = 0; depth < 5 && current?.extends; depth += 1) {
      let parent = path.relative(process.cwd(), path.resolve(path.dirname(currentFile), String(current.extends)))
      let parentCfg = readJson(parent)
      if (!parentCfg && !parent.endsWith(".json")) { parent += ".json"; parentCfg = readJson(parent) }
      if (!parentCfg) break
      chain.unshift(parentCfg)
      current = parentCfg
      currentFile = parent
    }
    let options = {}
    for (const level of [...chain, cfg]) options = { ...options, ...(level.compilerOptions ?? {}) }
    return options
  }

  const rootPkg = readJson("package.json")
  const engine = String(rootPkg?.engines?.node ?? "").match(/(\d+)/)
  const expectedTarget = process.env.DOCTOR_TS_TARGET || (engine ? TARGET_BY_NODE[Number(engine[1])] : undefined)

  const optionCounts = new Map()

  for (const file of configs) {
    const cfg = readJson(file)
    if (!cfg) continue
    const dir = path.dirname(file)
    const options = effective(file, cfg)

    if (expectedTarget) {
      const target = String(options.target ?? "")
      if (target.toLowerCase() !== expectedTarget.toLowerCase())
        violations.push(`433 ${file} — cible ${target || "absente"}, attendu ${expectedTarget} pour Node ${engine ? engine[1] : "?"}`)
    }

    const libs = Array.isArray(options.lib) ? options.lib.map(String) : []
    if (libs.some((l) => /^dom/i.test(l)) && !DOM_ALLOWED.includes(dir))
      violations.push(`434 ${file} — bibliotheque DOM dans un paquet execute par Node`)

    if (options.declaration === true && options.declarationMap !== true)
      warnings.push(`435 ${file} — declarationMap absent, la navigation vers les sources sera cassee`)
    if (options.inlineSources === true || options.inlineSourceMap === true)
      warnings.push(`436 ${file} — sources embarquees dans la sortie publiee`)

    for (const [key, value] of Object.entries(cfg.compilerOptions ?? {})) {
      if (PATH_OPTIONS.has(key)) continue
      const signature = `${key}=${JSON.stringify(value)}`
      optionCounts.set(signature, (optionCounts.get(signature) ?? 0) + 1)
    }
  }

  for (const [signature, count] of optionCounts)
    if (count >= DUP_MIN)
      warnings.push(`445 ${signature} repete dans ${count} paquets, a remonter dans tsconfig.base.json`)

  const turbo = all.includes("turbo.json") ? readJson("turbo.json") : null
  if (turbo) {
    const build = turbo.tasks?.build ?? turbo.pipeline?.build
    if (!build) warnings.push("438 turbo.json — aucune tache build declaree, aucune mise en cache entre deux compilations")
    else if (build.cache === false) warnings.push("438 turbo.json — la tache build desactive le cache")
    else if (!Array.isArray(build.outputs) || build.outputs.length === 0)
      warnings.push("438 turbo.json — la tache build ne declare aucune sortie, le cache ne peut rien restituer")
  }

  const testPackages = all
    .filter((f) => /^(apps|packages)\/[^\/]+\/package\.json$/.test(f))
    .filter((f) => readJson(f)?.scripts?.test)
    .map((f) => path.dirname(f))
  const vitestConfigs = new Map()
  for (const file of all.filter((f) => /^(apps|packages)\/[^\/]+\/vitest\.config\.[cm]?[jt]s$/.test(f))) {
    try { vitestConfigs.set(path.dirname(file), fs.readFileSync(file, "utf8").replace(/\s+/g, " ").trim()) } catch { }
  }
  if (vitestConfigs.size > 0) {
    const missing = testPackages.filter((dir) => !vitestConfigs.has(dir))
    if (missing.length > 0)
      warnings.push(`444 configuration vitest absente de ${missing.join(", ")} alors que ${[...vitestConfigs.keys()].join(", ")} en declare une`)
    const shapes = new Set(vitestConfigs.values())
    if (shapes.size > 1)
      warnings.push(`444 ${vitestConfigs.size} configurations vitest divergentes: ${[...vitestConfigs.keys()].join(", ")}`)
  }

  if (configs.length === 0 && !turbo) { console.log("OK: aucune configuration de compilation a inspecter"); return }

  for (const w of warnings) console.log(`WARN: ${w}`)
  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${configs.length} configurations de compilation coherentes`)
})
'
