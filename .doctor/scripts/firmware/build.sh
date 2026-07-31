#!/usr/bin/env bash
# build.sh — 481 table de partitions versionnée · 482 configuration de compilation versionnée
#            483 secret en configuration · 484 partition de mise à jour · 485 version en carte
#            d identité · 486 type conforme au dossier · 487 topics conformes · 488 empreinte au flash
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

node -e '
const fs = require("node:fs")
const path = require("node:path")
const { execSync } = require("node:child_process")

const SKIP = new Set(["build", "node_modules", ".git", ".pio", "managed_components", "dist"])
const BINARY = /\.(bin|elf|uf2|a|o|img|zip|png|jpg|pdf|stl|step|f3d)$/i
const walk = (dir) => {
  const out = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue
    const p = path.join(dir, e.name)
    if (e.isDirectory()) out.push(...walk(p))
    else out.push(p)
  }
  return out
}

const done = (msg) => { console.log(`OK: ${msg}`); process.exit(0) }
if (!fs.existsSync("firmware")) done("aucun projet de firmware à inspecter")
const files = walk("firmware")
if (files.length === 0) done("aucun projet de firmware à inspecter")

let tracked = null
try {
  const out = execSync("git ls-files firmware", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
  tracked = new Set(out.split("\n").filter(Boolean))
} catch { tracked = null }
const isTracked = (f) => (tracked === null ? true : tracked.has(f))

const fails = []
const warns = []
const texts = new Map()
for (const f of files) {
  if (BINARY.test(f)) continue
  if (fs.statSync(f).size > 512 * 1024) continue
  texts.set(f, fs.readFileSync(f, "utf8"))
}

const projects = fs.readdirSync("firmware", { withFileTypes: true })
  .filter((e) => e.isDirectory() && !SKIP.has(e.name))
  .map((e) => ({ name: e.name, dir: path.join("firmware", e.name) }))

for (const project of projects) {
  const own = files.filter((f) => f.startsWith(`${project.dir}${path.sep}`))
  if (own.length === 0) continue

  const cmake = own.filter((f) => path.basename(f) === "CMakeLists.txt")
  const isIdf = own.some((f) => /(^|\/)sdkconfig(\.|$)/.test(f))
    || cmake.some((f) => /idf_component_register|IDF_PATH|esp_idf/.test(texts.get(f) || ""))
    || own.some((f) => /(^|\/)(idf_component|platformio)\.(yml|ini)$/.test(f))

  if (isIdf) {
    const partitions = own.filter((f) => /partitions?[\w.-]*\.csv$/i.test(path.basename(f)) && isTracked(f))
    if (partitions.length === 0) fails.push(`481 ${project.dir} — aucune table de partitions versionnée`)
    for (const f of partitions) {
      if (!/\bota_0\b/.test(texts.get(f) || ""))
        warns.push(`484 ${f} — aucune partition de mise à jour`)
    }

    const sdk = own.filter((f) => /^sdkconfig(\.defaults[\w.-]*)?$/.test(path.basename(f)) && isTracked(f))
    if (sdk.length === 0) fails.push(`482 ${project.dir} — aucun sdkconfig versionné`)
  }

  const kinds = new Set()
  for (const f of own) {
    const text = texts.get(f)
    if (!text) continue
    for (const m of text.matchAll(/\\?"kind\\?"\s*:\s*\\?"([\w-]+)\\?"/g)) kinds.add(m[1])
    for (const m of text.matchAll(/#\s*define\s+\w*(?:DEVICE_)?KIND\w*\s+"([\w-]+)"/g)) kinds.add(m[1])
  }
  for (const kind of kinds) {
    if (kind !== project.name)
      fails.push(`486 ${project.dir} — type déclaré ${kind}, dossier ${project.name}`)
  }
}

for (const [file, text] of texts) {
  if (/^sdkconfig|Kconfig/.test(path.basename(file))) {
    text.split("\n").forEach((line, i) => {
      const m = line.match(/^\s*(?:CONFIG_)?(\w*(?:PASSWORD|PASSPHRASE|PSK|SECRET|TOKEN|PRIVATE_KEY|API_KEY|CREDENTIAL)\w*)\s*=\s*"(.*)"/i)
      if (m && m[2].trim() !== "")
        fails.push(`483 ${file}:${i + 1} — ${m[1]} porte une valeur en clair`)
    })
  }

  if (/\\?"kind\\?"\s*:/.test(text) && !/\\?"firmware\\?"\s*:/.test(text))
    fails.push(`485 ${file} — carte d identité sans version de firmware`)

  for (const m of text.matchAll(/"([^"\n]*olympia\/[^"\n]*)"/g)) {
    const topic = m[1]
    const line = text.slice(0, m.index).split("\n").length
    const seg = topic.replace(/^\//, "").split("/")
    const bad = (why) => fails.push(`487 ${file}:${line} — ${topic} ${why}`)
    if (seg[0] !== "olympia") { bad("ne commence pas par la racine olympia"); continue }
    if (seg.length > 1 && !/^v\d+$/.test(seg[1])) { bad("sans segment de version"); continue }
    if (seg.length > 2 && !["devices", "quarantine"].includes(seg[2])) { bad("espace de noms inconnu"); continue }
    if (seg.length > 4) {
      const leaf = seg[4]
      const allowed = seg[2] === "quarantine" ? ["identity"] : ["identity", "status", "data", "cmd"]
      if (leaf !== "" && !allowed.includes(leaf)) bad(`feuille ${leaf} hors contrat`)
    }
  }

  if (/flash/i.test(path.basename(file)) && /\.(sh|py|mjs|cjs|js|ts|bash)$/.test(file)) {
    if (!/fingerprint|empreinte|sha256|SHA-256/i.test(text))
      fails.push(`488 ${file} — outil de flash sans impression de l empreinte`)
  }
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${projects.length} projet(s) de firmware conformes`)
'
