#!/usr/bin/env bash
# realtime.sh — 473 connexion réseau bloquante · 474 taille de pile littérale · 475 flottant en interruption
#               476 interruption trop longue · 477 partage non volatile · 478 sortie série en interruption
#               479 broches hors en-tête unique · 480 numéro de broche littéral
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DOCTOR_ISR_MAX_LINES="${DOCTOR_ISR_MAX_LINES:-20}" \
node -e '
const fs = require("node:fs")
const path = require("node:path")

const SKIP = new Set(["build", "node_modules", ".git", ".pio", "managed_components", "dist"])
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
if (!fs.existsSync("firmware")) done("aucune source de firmware à inspecter")
const files = walk("firmware").filter((f) => /\.(c|h|cpp|hpp|cc|ino)$/.test(f))
if (files.length === 0) done("aucune source de firmware à inspecter")

const MAX_ISR_LINES = Number(process.env.DOCTOR_ISR_MAX_LINES)
const fails = []
const warns = []
const lineOf = (text, index) => text.slice(0, index).split("\n").length

const bodyFrom = (text, open) => {
  let depth = 0
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++
    else if (text[i] === "}") { depth--; if (depth === 0) return text.slice(open + 1, i) }
  }
  return text.slice(open + 1)
}

const sources = files.map((f) => ({ file: f, text: fs.readFileSync(f, "utf8") }))

const registered = new Set()
for (const { text } of sources) {
  for (const m of text.matchAll(/\b(?:attachInterrupt|gpio_isr_handler_add|esp_intr_alloc|timer_isr_callback_add|timerAttachInterrupt)\s*\(([^;]*?)\)\s*;/g)) {
    for (const arg of m[1].split(",")) {
      const name = arg.trim().replace(/^&/, "")
      if (/^\w+$/.test(name) && !/^(NULL|nullptr|true|false|\d+)$/.test(name)) registered.add(name)
    }
  }
}

const DECL = /^(static\s+)?(volatile\s+)?(static\s+)?(const\s+)?(unsigned\s+|signed\s+)?(uint(?:8|16|32|64)_t|int(?:8|16|32|64)_t|int|long|short|char|bool|float|double|size_t)\s+(\*\s*)?(\w+)\s*(\[[^\]]*\])?\s*(=[^;]*)?;\s*$/

let isrCount = 0
let pinConst = 0

for (const { file, text } of sources) {
  const globals = []
  text.split("\n").forEach((line, i) => {
    const m = line.match(DECL)
    if (!m) return
    globals.push({ name: m[8], isVolatile: Boolean(m[2]), line: i + 1 })
  })

  for (const m of text.matchAll(/(^|\n)([^\n;{}]*?)\b(\w+)\s*\(([^;{}()]*)\)\s*\{/g)) {
    const signature = m[2]
    const name = m[3]
    if (/\b(if|for|while|switch|return|else)$/.test(name)) continue
    const isIsr = /\b(IRAM_ATTR|ICACHE_RAM_ATTR)\b/.test(signature)
      || /(isr|irq|interrupt)/i.test(name)
      || registered.has(name)
    if (!isIsr) continue
    isrCount++

    const open = m.index + m[0].length - 1
    const body = bodyFrom(text, open)
    const where = `${file}:${lineOf(text, open)}:${name}`

    if (/\b(float|double)\b/.test(body) || /\b\d+\.\d+[fF]?\b/.test(body))
      fails.push(`475 ${where} — calcul flottant en interruption`)

    const printers = body.match(/\b(Serial\d?\.(?:print|println|write|printf)|printf|vprintf|puts|ESP_LOG[EWIDV]|log_[eiwd])\b/)
    if (printers) fails.push(`478 ${where} — sortie ${printers[1]} en interruption`)

    const bodyLines = body.split("\n").filter((l) => l.trim() !== "" && !/^\s*\/\//.test(l)).length
    if (bodyLines > MAX_ISR_LINES)
      warns.push(`476 ${where} — ${bodyLines} lignes, au-delà de ${MAX_ISR_LINES}`)

    for (const g of globals) {
      if (g.isVolatile) continue
      if (new RegExp(`\\b${g.name}\\b`).test(body))
        fails.push(`477 ${file}:${g.line} — ${g.name} partagé avec ${name} sans volatile`)
    }
  }

  for (const m of text.matchAll(/\bwhile\s*\(([^)]*)\)/g)) {
    if (/WiFi\.status\s*\(|WiFi\.isConnected\s*\(|esp_wifi_sta_get_ap_info/.test(m[1]))
      fails.push(`473 ${file}:${lineOf(text, m.index)} — attente active de la connexion réseau`)
  }
  for (const m of text.matchAll(/\bWiFi\.waitForConnectResult\s*\(/g))
    fails.push(`473 ${file}:${lineOf(text, m.index)} — waitForConnectResult bloque la boucle`)
  for (const m of text.matchAll(/\bxEventGroupWaitBits\s*\(([^;]*?)\)\s*;/g)) {
    if (/WIFI|wifi/.test(m[1]) && /portMAX_DELAY/.test(m[1]))
      fails.push(`473 ${file}:${lineOf(text, m.index)} — attente réseau sans expiration`)
  }

  for (const m of text.matchAll(/\bxTaskCreate(?:PinnedToCore|Static)?\s*\(([^;]*?)\)\s*;/g)) {
    const args = m[1].split(",").map((a) => a.trim())
    if (args.length < 3) continue
    if (/^\d+$/.test(args[2]))
      warns.push(`474 ${file}:${lineOf(text, m.index)} — pile ${args[2]} littérale, attendue depuis une constante`)
  }

  const isPinHeader = /(pins|pinmap|board)\.(h|hpp)$/i.test(file)
  const pinDefs = [...text.matchAll(/^\s*#\s*define\s+(\w*(?:PIN|GPIO)\w*)\s+\(?\s*(?:GPIO_NUM_)?(\d+)/gim)]
  pinConst += pinDefs.length
  if (!isPinHeader) {
    for (const m of pinDefs)
      fails.push(`479 ${file}:${lineOf(text, m.index)} — ${m[1]} déclaré hors de l en-tête de broches`)
  }

  const CALLS = /\b(pinMode|digitalWrite|digitalRead|analogRead|analogWrite|digitalPinToInterrupt|gpio_set_direction|gpio_set_level|gpio_get_level|gpio_reset_pin|gpio_pad_select_gpio|gpio_isr_handler_add|gpio_set_pull_mode|gpio_pullup_en|gpio_pulldown_en|adc1_config_channel_atten)\s*\(\s*(?:\(\s*gpio_num_t\s*\)\s*)?(?:GPIO_NUM_)?(\d+)\s*[,)]/g
  for (const m of text.matchAll(CALLS))
    fails.push(`480 ${file}:${lineOf(text, m.index)} — ${m[1]} appelé avec la broche littérale ${m[2]}`)
}

const byProject = new Map()
for (const f of files.filter((x) => /(pins|pinmap|board)\.(h|hpp)$/i.test(x))) {
  const project = f.split(path.sep).slice(0, 2).join(path.sep)
  byProject.set(project, (byProject.get(project) || 0) + 1)
}
for (const [project, count] of byProject) {
  if (count > 1) fails.push(`479 ${project} — ${count} en-têtes de broches, un seul attendu`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const v of warns) console.log(`WARN: ${v}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
console.log(`OK: ${isrCount} interruption(s) et ${pinConst} constante(s) de broche conformes`)
'
