#!/usr/bin/env bash
# usage.sh — 422 dépendance déclarée jamais importée · 423 import non déclaré
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

export DOCTOR_DEPS_ALWAYS_USED="${DOCTOR_DEPS_ALWAYS_USED:-}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const manifests = all.filter((f) => /^(apps|packages)\/[^\/]+\/package\.json$/.test(f))
  if (manifests.length === 0) { console.log("OK: aucun paquet a inspecter"); return }

  const ALWAYS_USED = new Set((process.env.DOCTOR_DEPS_ALWAYS_USED ?? "").split(/[\s,]+/).filter(Boolean))
  const BUILTINS = new Set(["assert", "async_hooks", "buffer", "child_process", "cluster", "console", "constants",
    "crypto", "dgram", "diagnostics_channel", "dns", "domain", "events", "fs", "http", "http2", "https", "inspector",
    "module", "net", "os", "path", "perf_hooks", "process", "punycode", "querystring", "readline", "repl", "stream",
    "string_decoder", "sys", "timers", "tls", "trace_events", "tty", "url", "util", "v8", "vm", "worker_threads", "zlib"])
  const SPEC = /from\s*"([^"]+)"|import\s*\(?\s*"([^"]+)"\s*\)?|require\s*\(\s*"([^"]+)"\s*\)/g

  const sources = all.filter((f) =>
    /^(apps|packages)\/[^\/]+\/.*\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/.test(f) && !/\.d\.ts$/.test(f))

  const importsByPackage = new Map()
  for (const file of sources) {
    const owner = file.split("/").slice(0, 2).join("/")
    let text
    try { text = fs.readFileSync(file, "utf8") } catch { continue }
    const found = importsByPackage.get(owner) ?? new Set()
    for (const match of text.matchAll(SPEC)) {
      const spec = match[1] ?? match[2] ?? match[3]
      if (!spec || /^[.\/]/.test(spec) || spec.startsWith("node:")) continue
      const name = spec.startsWith("@") ? spec.split("/").slice(0, 2).join("/") : spec.split("/")[0]
      if (BUILTINS.has(name)) continue
      found.add(name)
    }
    importsByPackage.set(owner, found)
  }

  const violations = []
  let inspected = 0

  for (const file of manifests) {
    const dir = file.replace(/\/package\.json$/, "")
    const imported = importsByPackage.get(dir)
    if (!imported) continue
    inspected += 1

    let pkg
    try { pkg = JSON.parse(fs.readFileSync(file, "utf8")) } catch { continue }
    const declared = new Set([
      ...Object.keys(pkg.dependencies ?? {}),
      ...Object.keys(pkg.devDependencies ?? {}),
      ...Object.keys(pkg.peerDependencies ?? {}),
      ...Object.keys(pkg.optionalDependencies ?? {}),
    ])

    for (const name of [...imported].sort())
      if (!declared.has(name))
        violations.push(`423 ${dir} — ${name} importe sans etre declare dans ${file}`)

    for (const dep of Object.keys(pkg.dependencies ?? {})) {
      if (dep.startsWith("@types/") || ALWAYS_USED.has(dep)) continue
      if (!imported.has(dep))
        violations.push(`422 ${file} — ${dep} declare mais jamais importe`)
    }
  }

  if (inspected === 0) { console.log("OK: aucun paquet avec des sources a inspecter"); return }
  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: dependances declarees et importees alignees sur ${inspected} paquets`)
})
'
