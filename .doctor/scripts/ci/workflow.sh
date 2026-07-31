#!/usr/bin/env bash
# workflow.sh — 453 flux existant · 454 doctor · 455 types · 456 tests · 457 compilation
#               458 version de Node · 459 verrou figé · 460 actions épinglées
#               461 secret imprimé · 462 délai maximal · 463 avertissement ignoré
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

export DOCTOR_CI_REQUIRED="${DOCTOR_CI_REQUIRED:-454:doctor 455:typecheck 456:test 457:build}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const workflows = all.filter((f) => /^\.github\/workflows\/[^\/]+\.ya?ml$/.test(f))
  const violations = []
  const warnings = []

  if (workflows.length === 0) {
    console.log("FAIL: 453 aucun flux d integration dans .github/workflows")
    console.log("")
    console.log("TOTAL: 1 violation(s)")
    process.exit(1)
  }

  const REQUIRED = (process.env.DOCTOR_CI_REQUIRED ?? "").split(/[\s,]+/).filter(Boolean)
    .map((entry) => { const [id, word] = entry.split(":"); return { id, word } })
  const PINNED = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+(\/[A-Za-z0-9._\/-]+)?@[0-9a-f]{40}$/
  const indentOf = (line) => line.match(/^\s*/)[0].length

  const runs = []
  const nodeVersions = []

  for (const file of workflows) {
    let lines
    try { lines = fs.readFileSync(file, "utf8").split("\n") } catch { continue }

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]
      if (/^\s*#/.test(line)) continue

      const usesMatch = line.match(/^\s*(?:-\s*)?uses:\s*(\S+)/)
      if (usesMatch) {
        const value = usesMatch[1].replace(/^["]|["]$/g, "")
        if (!PINNED.test(value) && !value.startsWith("./") && !value.startsWith("docker://"))
          violations.push(`460 ${file}:${i + 1} — action ${value} non epinglee a une empreinte`)
        continue
      }

      const nodeMatch = line.match(/^\s*node-version:\s*["]?v?(\d+)/)
      if (nodeMatch) nodeVersions.push({ at: `${file}:${i + 1}`, major: Number(nodeMatch[1]) })

      if (/^\s*continue-on-error:\s*true\b/.test(line))
        warnings.push(`463 ${file}:${i + 1} — continue-on-error masque un echec`)

      const runMatch = line.match(/^(\s*)(?:-\s*)?run:\s*(.*)$/)
      if (!runMatch) continue
      const indent = runMatch[1].length
      let command = runMatch[2].trim()
      if (command === "" || /^[|>][-+0-9]*$/.test(command)) {
        command = ""
        for (let j = i + 1; j < lines.length; j += 1) {
          if (lines[j].trim() === "") continue
          if (indentOf(lines[j]) <= indent) break
          command += `${lines[j].trim()}\n`
          i = j
        }
      }
      runs.push({ at: `${file}:${i + 1}`, command })
    }

    const jobsAt = lines.findIndex((l) => /^jobs:\s*$/.test(l))
    if (jobsAt < 0) continue
    let jobIndent = null
    const jobs = []
    for (let i = jobsAt + 1; i < lines.length; i += 1) {
      const line = lines[i]
      if (line.trim() === "" || /^\s*#/.test(line)) continue
      const indent = indentOf(line)
      if (indent === 0) break
      if (jobIndent === null) jobIndent = indent
      if (indent === jobIndent && /^\s*[A-Za-z0-9_.-]+:\s*$/.test(line)) {
        if (jobs.length > 0) jobs[jobs.length - 1].end = i
        jobs.push({ name: line.trim().replace(/:$/, ""), start: i, end: lines.length })
      }
    }
    for (const job of jobs) {
      const body = lines.slice(job.start, job.end).join("\n")
      if (!/^\s*timeout-minutes:\s*\d+/m.test(body))
        warnings.push(`462 ${file} — la tache ${job.name} sans delai maximal`)
    }
  }

  const allCommands = runs.map((r) => r.command).join("\n")
  for (const { id, word } of REQUIRED)
    if (!new RegExp(`\\b${word}\\b`).test(allCommands))
      violations.push(`${id} aucune etape d integration ne lance ${word}`)

  for (const run of runs) {
    if (/\bpnpm\s+(install|i)\b/.test(run.command) && !/--frozen-lockfile/.test(run.command))
      violations.push(`459 ${run.at} — installation sans --frozen-lockfile`)
    if (/\$\{\{\s*secrets\./.test(run.command))
      violations.push(`461 ${run.at} — secret interpole dans une commande, il finira dans le journal`)
    if (/\|\|\s*true\s*$/m.test(run.command))
      warnings.push(`463 ${run.at} — echec de commande neutralise par || true`)
  }

  let rootPkg = null
  try { rootPkg = JSON.parse(fs.readFileSync("package.json", "utf8")) } catch { }
  const engine = String(rootPkg?.engines?.node ?? "").match(/(\d+)/)
  if (engine) {
    for (const version of nodeVersions)
      if (version.major !== Number(engine[1]))
        violations.push(`458 ${version.at} — Node ${version.major} alors que engines.node exige ${rootPkg.engines.node}`)
  }

  for (const w of warnings) console.log(`WARN: ${w}`)
  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${workflows.length} flux d integration complet(s), ${runs.length} etapes inspectees`)
})
'
