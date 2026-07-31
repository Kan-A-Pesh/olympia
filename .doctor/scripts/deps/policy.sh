#!/usr/bin/env bash
# policy.sh — 415 borne majeure · 416 dépôt git · 417 chemin local · 418 préversion
#             426 dépendance lourde partagée · 427 correctif de plateforme · 428 utilitaire
#             généraliste · 429 dates obsolètes · 430 script d installation · 431 outil · 432 veille
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

export DOCTOR_SHARED_PACKAGES="${DOCTOR_SHARED_PACKAGES:-packages/hermes-protocol packages/tiles-ui}"
export DOCTOR_HEAVY_DEPS="${DOCTOR_HEAVY_DEPS:-express fastify koa hapi mqtt aedes serialport usb node-hid sqlite3 better-sqlite3 drizzle-orm prisma @prisma/client react react-dom next pino winston bunyan axios ws socket.io sharp canvas puppeteer playwright rxjs}"
export DOCTOR_POLYFILL_DEPS="${DOCTOR_POLYFILL_DEPS:-core-js core-js-pure regenerator-runtime babel-polyfill @babel/polyfill whatwg-fetch isomorphic-fetch cross-fetch node-fetch es6-promise promise-polyfill object-assign array-flat-polyfill url-polyfill abortcontroller-polyfill es5-shim es6-shim setimmediate}"
export DOCTOR_TOOLING_DEPS="${DOCTOR_TOOLING_DEPS:-typescript turbo vitest @vitest/coverage-v8 @vitest/ui eslint prettier tsx ts-node esbuild vite rimraf nodemon husky lint-staged npm-run-all concurrently}"
export DOCTOR_ALLOWED_INSTALL_SCRIPTS="${DOCTOR_ALLOWED_INSTALL_SCRIPTS:-}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const all = input.split("\n").filter(Boolean)
  const manifests = all.filter((f) => /^(package\.json|(apps|packages)\/[^\/]+\/package\.json)$/.test(f))
  if (manifests.length === 0) { console.log("OK: aucun manifeste a inspecter"); return }

  const words = (name) => (process.env[name] ?? "").split(/[\s,]+/).filter(Boolean)
  const SHARED = words("DOCTOR_SHARED_PACKAGES")
  const HEAVY = new Set(words("DOCTOR_HEAVY_DEPS"))
  const POLYFILLS = new Set(words("DOCTOR_POLYFILL_DEPS"))
  const TOOLING = new Set(words("DOCTOR_TOOLING_DEPS"))
  const ALLOWED = new Set(words("DOCTOR_ALLOWED_INSTALL_SCRIPTS"))
  const INSTALL_SCRIPTS = ["preinstall", "install", "postinstall", "prepare", "prepublish"]
  const AUTOMATION = /^(\.github\/)?(renovate\.json5?|\.renovaterc(\.json5?)?|dependabot\.ya?ml)$/

  const bounded = (r) =>
    /^[\^~]?\d+(\.\d+){0,2}([-+][0-9A-Za-z.-]+)?$/.test(r) ||
    /^\d+(\.\d+)?\.?[xX*]$/.test(r) ||
    r.includes("<")

  const violations = []
  const warnings = []

  for (const file of manifests) {
    const dir = file === "package.json" ? "." : file.replace(/\/package\.json$/, "")
    let pkg
    try { pkg = JSON.parse(fs.readFileSync(file, "utf8")) } catch (e) {
      violations.push(`415 ${file} — JSON invalide: ${e.message}`); continue
    }

    for (const script of INSTALL_SCRIPTS) {
      if (pkg.scripts?.[script] && !ALLOWED.has(`${dir}:${script}`))
        violations.push(`430 ${file} — script ${script} non autorise, ajouter "${dir}:${script}" a DOCTOR_ALLOWED_INSTALL_SCRIPTS`)
    }

    for (const field of ["dependencies", "devDependencies", "optionalDependencies"]) {
      const runtime = field !== "devDependencies"
      for (const [dep, raw] of Object.entries(pkg[field] ?? {})) {
        const range = String(raw)

        if (POLYFILLS.has(dep))
          violations.push(`427 ${file} — ${dep} comble une lacune deja couverte par Node 22 et les navigateurs courants`)
        if (/^(lodash|lodash-es|underscore)$/.test(dep) || /^lodash\./.test(dep))
          violations.push(`428 ${file} — ${dep} bibliotheque utilitaire generaliste`)
        if (/^moment(-timezone)?$/.test(dep))
          violations.push(`429 ${file} — ${dep} bibliotheque de dates obsolete`)
        if (runtime && (TOOLING.has(dep) || dep.startsWith("@types/")))
          violations.push(`431 ${file} — ${dep} est un outil, il reste en devDependencies`)
        if (runtime && SHARED.includes(dir) && HEAVY.has(dep))
          violations.push(`426 ${file} — ${dep} alourdit un paquet partage qui doit rester importable par le navigateur`)

        if (/^(workspace|catalog):/.test(range)) continue
        if (/^(git\+|git:|git@|github:|gitlab:|bitbucket:)/.test(range) || /github\.com|\.git#|\.git$/.test(range)) {
          violations.push(`416 ${file} — ${dep} pointe un depot git (${range})`); continue
        }
        if (/^(file:|link:|portal:)/.test(range) || /^(\.{1,2}\/|\/|~\/)/.test(range)) {
          violations.push(`417 ${file} — ${dep} pointe un chemin local (${range})`); continue
        }

        const clean = range.replace(/^npm:.*@/, "")
        if (!bounded(clean))
          violations.push(`415 ${file} — ${dep}@${range} sans borne majeure`)
        if (/\d-[0-9A-Za-z.]*(alpha|beta|rc|next|canary|nightly|experimental|preview)/i.test(clean) || /^(next|canary|beta|alpha|nightly)$/.test(clean))
          violations.push(`418 ${file} — ${dep}@${range} est une preversion`)
      }
    }
  }

  if (!all.some((f) => AUTOMATION.test(f)))
    warnings.push("432 aucune configuration renovate ni dependabot: la mise a jour des dependances reste manuelle")

  for (const w of warnings) console.log(`WARN: ${w}`)
  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log(`OK: ${manifests.length} manifestes conformes a la politique de dependances`)
})
'
