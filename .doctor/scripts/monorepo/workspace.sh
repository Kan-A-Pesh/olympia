#!/usr/bin/env bash
# workspace.sh — 85 version de Node par paquet · 89 verrou synchrone des manifestes
#                92 tâche turbo déclarée · 93 sorties turbo déclarées
#                95 option déjà présente dans la base · 96 dossier couvert deux fois
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const has = (f) => all.includes(f)
  const readText = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
  const readJson = (f) => { try { return JSON.parse(readText(f)) } catch { return null } }
  const unquote = (s) => s.replace(/^["\x27]|["\x27]$/g, "")

  const manifests = all.filter((f) => /^(apps|packages)\/[^/]+\/package\.json$/.test(f))
  const turboFiles = all.filter((f) => f === "turbo.json" || /^(apps|packages)\/[^/]+\/turbo\.json$/.test(f))
  if (manifests.length === 0 && turboFiles.length === 0 && !has("pnpm-workspace.yaml")) {
    console.log("OK: aucun espace de travail à inspecter")
    return
  }

  const fails = []
  const warns = []
  const root = has("package.json") ? readJson("package.json") : null
  const packages = new Map()
  for (const file of manifests) {
    const pkg = readJson(file)
    if (pkg) packages.set(file, pkg)
  }

  const rootNode = root && root.engines ? root.engines.node : undefined
  for (const [file, pkg] of packages) {
    const node = pkg.engines ? pkg.engines.node : undefined
    if (!node && !rootNode) warns.push(`85 ${file} — aucune version de Node déclarée, ni ici ni à la racine`)
    else if (node && rootNode && node !== rootNode)
      warns.push(`85 ${file} — engines.node ${node} diverge de la racine ${rootNode}`)
  }

  if (has("pnpm-workspace.yaml")) {
    const patterns = []
    let inPackages = false
    for (const line of readText("pnpm-workspace.yaml").split("\n")) {
      if (/^packages:\s*$/.test(line)) { inPackages = true; continue }
      if (!inPackages) continue
      const entry = line.match(/^\s+-\s*(.+?)\s*$/)
      if (entry) { patterns.push(unquote(entry[1])); continue }
      if (/^\S/.test(line)) inPackages = false
    }
    const toRegex = (p) => {
      let out = "^"
      for (let i = 0; i < p.length; i += 1) {
        const ch = p[i]
        if (ch === "*" && p[i + 1] === "*") { out += ".*"; i += 1 }
        else if (ch === "*") out += "[^/]*"
        else if (/[A-Za-z0-9_/-]/.test(ch)) out += ch
        else out += "\\" + ch
      }
      return new RegExp(out + "$")
    }
    const positive = patterns.filter((p) => !p.startsWith("!"))
    const negative = patterns.filter((p) => p.startsWith("!")).map((p) => p.slice(1))
    for (const file of manifests) {
      const dir = file.replace(/\/package\.json$/, "")
      if (negative.some((p) => toRegex(p).test(dir))) continue
      const hits = positive.filter((p) => toRegex(p).test(dir))
      if (hits.length > 1)
        fails.push(`96 ${dir} — couvert par ${hits.length} entrées de pnpm-workspace.yaml: ${hits.join(", ")}`)
    }
    const dupes = new Set(positive.filter((p, i) => positive.indexOf(p) !== i))
    for (const p of dupes) fails.push(`96 pnpm-workspace.yaml — entrée "${p}" déclarée plusieurs fois`)
  }

  if (has("pnpm-lock.yaml")) {
    const importers = new Map()
    let inImporters = false
    let current = null
    let field = null
    let dep = null
    for (const line of readText("pnpm-lock.yaml").split("\n")) {
      if (/^importers:\s*$/.test(line)) { inImporters = true; continue }
      if (!inImporters) continue
      if (/^\S/.test(line)) break
      if (line.trim() === "") continue
      let m
      if ((m = line.match(/^ {2}(\S.*):\s*$/))) {
        current = unquote(m[1]); field = null; dep = null
        importers.set(current, new Map())
        continue
      }
      if ((m = line.match(/^ {4}([A-Za-z]+):\s*$/))) { field = m[1]; dep = null; continue }
      if ((m = line.match(/^ {6}(\S.*):\s*$/))) { dep = unquote(m[1]); continue }
      if ((m = line.match(/^ {8}specifier:\s*(.+?)\s*$/))) {
        if (current !== null && dep !== null && /^(dependencies|devDependencies|optionalDependencies)$/.test(field ?? ""))
          importers.get(current).set(dep, unquote(m[1]))
      }
    }

    if (importers.size > 0) {
      const declared = new Map()
      const collect = (file, pkg) => {
        const dir = file === "package.json" ? "." : file.replace(/\/package\.json$/, "")
        const deps = new Map()
        for (const f of ["dependencies", "devDependencies", "optionalDependencies"])
          for (const [name, range] of Object.entries(pkg[f] ?? {})) deps.set(name, String(range))
        declared.set(dir, deps)
      }
      if (root) collect("package.json", root)
      for (const [file, pkg] of packages) collect(file, pkg)

      for (const [dir, deps] of declared) {
        const lock = importers.get(dir)
        if (!lock) { fails.push(`89 ${dir} — absent de la section importers de pnpm-lock.yaml`); continue }
        for (const [name, range] of deps) {
          if (!lock.has(name)) fails.push(`89 ${dir} — ${name} déclaré dans le manifeste, absent du verrou`)
          else if (lock.get(name) !== range)
            fails.push(`89 ${dir} — ${name} en ${range} dans le manifeste, ${lock.get(name)} dans le verrou`)
        }
        for (const name of lock.keys())
          if (!deps.has(name)) fails.push(`89 ${dir} — ${name} verrouillé mais absent du manifeste`)
      }
      for (const dir of importers.keys())
        if (!declared.has(dir)) fails.push(`89 ${dir} — importer du verrou sans manifeste correspondant`)
    }
  }

  if (turboFiles.length > 0) {
    const tasks = new Map()
    for (const file of turboFiles) {
      const cfg = readJson(file)
      if (!cfg) { fails.push(`92 ${file} — JSON invalide`); continue }
      for (const [name, def] of Object.entries(cfg.tasks ?? cfg.pipeline ?? {}))
        tasks.set(name.includes("#") ? name.split("#")[1] : name, { file, def: def ?? {} })
    }

    const used = new Map()
    const owners = new Map()
    const scan = (file, pkg) => {
      for (const [name, raw] of Object.entries(pkg.scripts ?? {})) {
        const body = String(raw)
        if (!owners.has(name)) owners.set(name, [])
        owners.get(name).push({ file, body })
        for (const m of body.matchAll(/turbo(?:\s+run)?\s+([a-z][\w:.-]*(?:\s+[a-z][\w:.-]*)*)/g))
          for (const task of m[1].split(/\s+/))
            if (!used.has(task)) used.set(task, `${file} (${name})`)
      }
    }
    if (root) scan("package.json", root)
    for (const [file, pkg] of packages) scan(file, pkg)

    for (const [task, where] of used)
      if (!tasks.has(task)) fails.push(`92 ${where} — tâche "${task}" absente de turbo.json`)

    const PRODUCER = /(^|[\s;&|(])(tsc|tsup|rollup|esbuild|webpack|parcel|swc|babel|vite|next|astro|nest|dtc)\b/
    const NO_OUTPUT = /--noEmit|--dry-run|--version/
    for (const [task, entry] of tasks) {
      const outputs = entry.def.outputs
      if (Array.isArray(outputs) && outputs.length > 0) continue
      if (entry.def.cache === false) continue
      const producers = (owners.get(task) ?? []).filter((s) => PRODUCER.test(s.body) && !NO_OUTPUT.test(s.body))
      if (producers.length > 0)
        fails.push(`93 ${entry.file} — la tâche "${task}" produit des fichiers (${producers[0].file}) sans déclarer outputs`)
    }
  }

  const BASE = "tsconfig.base.json"
  if (has(BASE)) {
    const baseOptions = readJson(BASE)?.compilerOptions ?? {}
    for (const file of all.filter((f) => /tsconfig[^/]*\.json$/.test(f) && f !== BASE)) {
      const cfg = readJson(file)
      if (!cfg || !String(cfg.extends ?? "").includes(BASE)) continue
      for (const [key, value] of Object.entries(cfg.compilerOptions ?? {})) {
        if (!(key in baseOptions)) continue
        if (JSON.stringify(baseOptions[key]) === JSON.stringify(value))
          warns.push(`95 ${file} — "${key}" reprend la valeur de ${BASE}`)
      }
    }
  }

  for (const v of fails) console.log(`FAIL: ${v}`)
  for (const w of warns) console.log(`WARN: ${w}`)
  if (fails.length > 0) {
    console.log("")
    console.log(`TOTAL: ${fails.length} violation(s)`)
    process.exit(1)
  }
  if (warns.length > 0) console.log(`OK: espace de travail cohérent (${warns.length} avertissement(s))`)
  else console.log(`OK: ${manifests.length} paquet(s) alignés sur le verrou, turbo.json et la base TypeScript`)
})
'
