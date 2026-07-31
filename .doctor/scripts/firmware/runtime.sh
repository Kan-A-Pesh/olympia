#!/usr/bin/env bash
# runtime.sh — 201 temporisation bloquante · 202 classe String · 203 allocation en boucle
#              204 chien de garde · 205 génération RSA · 206 broker en dur
#              207 chiffrement du stockage · 208 débit série · 209 sortie formatée
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DAEMON_FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)

DOCTOR_DAEMON_FILES="$DAEMON_FILES" \
DOCTOR_MAX_BUSY_WAIT_US="${DOCTOR_MAX_BUSY_WAIT_US:-1000}" \
node -e '
const fs = require("node:fs")
const path = require("node:path")

const done = (msg) => { console.log(`OK: ${msg}`); process.exit(0) }
const SKIP = new Set(["build", "node_modules", ".git", ".pio", "managed_components", "dist"])
const walk = (dir) => {
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(entry.name)) continue
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(p))
    else out.push(p)
  }
  return out
}

if (!fs.existsSync("firmware")) done("aucune source de firmware à inspecter")
const tree = walk("firmware")
const sourceFiles = tree.filter((f) => /\.(c|h|cpp|hpp|cc|ino)$/.test(f))
if (sourceFiles.length === 0) done("aucune source de firmware à inspecter")

const maxBusyWait = Number(process.env.DOCTOR_MAX_BUSY_WAIT_US || 1000)
const blank = (m) => m.replace(/[^\n]/g, " ")
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, blank).replace(/\/\/[^\n]*/g, blank)
const lineAt = (text, index) => text.slice(0, index).split("\n").length
const bodyFrom = (text, open) => {
  let depth = 0
  for (let i = open; i < text.length; i += 1) {
    if (text[i] === "{") depth += 1
    else if (text[i] === "}") { depth -= 1; if (depth === 0) return text.slice(open + 1, i) }
  }
  return text.slice(open + 1)
}

const sources = sourceFiles.map((f) => ({ file: f, text: strip(fs.readFileSync(f, "utf8")) }))
const fails = []
const warns = []

const BLOCKING = /\b(delay|sleep|usleep|sleep_ms|busy_wait_ms)\s*\(/
const BUSY_US = /\b(delayMicroseconds|busy_wait_us|sleep_us)\s*\(\s*(\d+)/g
const ALLOCATION = /\b(malloc|calloc|realloc|strdup|ps_malloc|heap_caps_malloc|heap_caps_calloc)\s*\(|\bnew\s+[A-Za-z_]/
const FED = /\b(esp_task_wdt_reset|esp_task_wdt_feed|watchdog_update|taskYIELD|vTaskDelay|vTaskDelayUntil|yield|rtc_wdt_feed|wdt_reset|delay)\s*\(/
const FORMATTED = /\b(printf|sprintf|snprintf|vsnprintf|Serial\d?\.print(?:f|ln)?|ESP_LOG[EWIDV]|log_[eiwd])\s*\(/
const ISR = /\b(IRAM_ATTR|ICACHE_RAM_ATTR)\b/
const HOT = /(sample|capture|render|draw|tick|poll|stream)/i
const ARDUINO_STRING = /(^|[^:.\w])String\s*[&*]?\s*[A-Za-z_(]/
const RSA = /\b(mbedtls_rsa_gen_key|RSA_generate_key(?:_ex)?|rsa_generate_key|esp_rsa_gen_key|crypto_rsa_keygen)\s*\(/g
const NVS = /\b(nvs_flash_init|nvs_open|nvs_set_[a-z0-9_]+|nvs_get_[a-z0-9_]+)\s*\(|\bPreferences\b/
const BAUD = [
  /\bSerial\d?\.begin\s*\(\s*(\d{3,7})/g,
  /\buart_set_baudrate\s*\([^,;]*,\s*(\d{3,7})/g,
  /\buart_init\s*\([^,;]*,\s*(\d{3,7})/g,
  /\bstdio_uart_init_full\s*\([^,;]*,\s*(\d{3,7})/g,
  /\.baud_rate\s*=\s*(\d{3,7})/g,
  /#\s*define\s+\w*BAUD\w*\s+(\d{3,7})/g,
]

let loopCount = 0
const firmwareBauds = new Map()

for (const { file, text } of sources) {
  const regions = []
  for (const match of text.matchAll(/(^|\n)[^\n;{}]*\bloop\s*\(\s*(?:void\s*)?\)\s*\{/g)) {
    const open = match.index + match[0].length - 1
    regions.push({ kind: "loop", label: "loop()", line: lineAt(text, open), body: bodyFrom(text, open) })
  }
  for (const match of text.matchAll(/\b(?:while\s*\(\s*(?:1|true)\s*\)|for\s*\(\s*;\s*;\s*\))\s*\{/g)) {
    const open = match.index + match[0].length - 1
    regions.push({ kind: "forever", label: "boucle infinie", line: lineAt(text, open), body: bodyFrom(text, open) })
  }

  for (const region of regions) {
    loopCount += 1
    const at = `${file}:${region.line}`
    if (region.kind === "loop") {
      if (BLOCKING.test(region.body)) fails.push(`201 ${at} — temporisation bloquante dans ${region.label}`)
      let match
      BUSY_US.lastIndex = 0
      while ((match = BUSY_US.exec(region.body)) !== null)
        if (Number(match[2]) > maxBusyWait)
          fails.push(`201 ${at} — ${match[1]}(${match[2]}) au-delà de ${maxBusyWait} µs dans ${region.label}`)
      if (ALLOCATION.test(region.body)) fails.push(`203 ${at} — allocation dans ${region.label}`)
      if (FORMATTED.test(region.body)) warns.push(`209 ${at} — sortie formatée dans ${region.label}`)
    } else if (!FED.test(region.body)) {
      warns.push(`204 ${at} — ${region.label} sans réarmement du chien de garde ni cession de la main`)
    }
  }

  for (const match of text.matchAll(/(^|\n)([^\n;{}]*?)\b(\w+)\s*\(([^;{}()]*)\)\s*\{/g)) {
    if (/\b(if|for|while|switch|return|else|do)$/.test(match[3])) continue
    if (ISR.test(match[2]) || /(isr|irq|interrupt)/i.test(match[3])) continue
    if (!HOT.test(match[3])) continue
    const open = match.index + match[0].length - 1
    const body = bodyFrom(text, open)
    const found = body.match(FORMATTED)
    if (found) warns.push(`209 ${file}:${lineAt(text, open)} — ${found[1]} dans ${match[3]}, chemin temps réel`)
  }

  for (const match of text.matchAll(/(^|[^:.\w])String\s*[&*]?\s*[A-Za-z_(]/g))
    fails.push(`202 ${file}:${lineAt(text, match.index + match[1].length)} — classe String Arduino, fragmente le tas`)

  for (const match of text.matchAll(RSA))
    fails.push(`205 ${file}:${lineAt(text, match.index)} — ${match[1]} génère une clé RSA sur l appareil`)

  for (const match of text.matchAll(/"([^"\n]*)"/g)) {
    const value = match[1]
    const at = `${file}:${lineAt(text, match.index)}`
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(value)) {
      if (value === "0.0.0.0" || /^255\./.test(value)) continue
      fails.push(`206 ${at} — adresse ${value} en dur`)
    } else if (/^(mqtts?|ssl|tcp|wss?):\/\/\S+/.test(value)) {
      fails.push(`206 ${at} — adresse de broker ${value} en dur`)
    }
  }
  for (const match of text.matchAll(/#\s*define\s+(\w*(?:BROKER|MQTT_HOST|MQTT_SERVER)\w*)\s+"([^"]+)"/gi))
    fails.push(`206 ${file}:${lineAt(text, match.index)} — ${match[1]} figé sur "${match[2]}"`)

  for (const pattern of BAUD) {
    pattern.lastIndex = 0
    let match
    while ((match = pattern.exec(text)) !== null)
      if (!firmwareBauds.has(match[1])) firmwareBauds.set(match[1], `${file}:${lineAt(text, match.index)}`)
  }
}

if (sources.some(({ text }) => NVS.test(text))) {
  const configs = tree.filter((f) => /(^|\/)sdkconfig[^/]*$/.test(f))
  const encrypted = configs.some((f) => /^\s*CONFIG_NVS_ENCRYPTION\s*=\s*y\s*$/m.test(fs.readFileSync(f, "utf8")))
  if (!encrypted)
    fails.push(`207 firmware — stockage NVS utilisé sans CONFIG_NVS_ENCRYPTION=y (${configs.length} sdkconfig trouvé(s))`)
}

const daemonBauds = new Map()
for (const file of (process.env.DOCTOR_DAEMON_FILES || "").split("\n").filter(Boolean)) {
  let text
  try { text = fs.readFileSync(file, "utf8") } catch { continue }
  for (const match of text.matchAll(/\bbaud(?:Rate|rate|_rate)?\s*[:=]\s*(\d{3,7})/g))
    if (!daemonBauds.has(match[1])) daemonBauds.set(match[1], `${file}:${lineAt(text, match.index)}`)
}
if (firmwareBauds.size > 0 && daemonBauds.size > 0) {
  for (const [rate, where] of firmwareBauds)
    if (!daemonBauds.has(rate))
      fails.push(`208 ${where} — débit ${rate} absent du daemon (${[...daemonBauds.keys()].join(", ")})`)
}

for (const v of fails) console.log(`FAIL: ${v}`)
for (const w of warns) console.log(`WARN: ${w}`)
if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}
if (warns.length > 0) console.log(`OK: aucun manquement bloquant (${warns.length} avertissement(s))`)
else console.log(`OK: ${sourceFiles.length} source(s) de firmware, ${loopCount} boucle(s) conformes`)
'
