#!/usr/bin/env bash
# encoding.sh — 8 espaces en fin de ligne · 9 retour final · 10 CRLF · 11 tabulations
#               12 UTF-8 · 13 marqueur d'ordre d'octets
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

"$DOCTOR_DIR/utils/list-files.sh" all | node -e '
const fs = require("node:fs")
let input = ""
process.stdin.on("data", (c) => (input += c))
process.stdin.on("end", () => {
  const TEXT = /\.(ts|tsx|js|json|md|sh|dts|yaml|yml|snippet|txt)$/
  const TABS_EXEMPT = /\.(dts|snippet)$/
  const violations = []

  for (const file of input.split("\n").filter((f) => f && TEXT.test(f))) {
    let buf
    try { buf = fs.readFileSync(file) } catch { continue }
    if (buf.length === 0) continue

    if (buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf)
      violations.push(`13 ${file} — marqueur d'\''ordre d'\''octets`)

    if (buf.includes(0x0d)) violations.push(`10 ${file} — fin de ligne CRLF`)
    if (buf[buf.length - 1] !== 0x0a) violations.push(`9 ${file} — pas de retour à la ligne final`)

    const text = buf.toString("utf8")
    if (text.includes(String.fromCharCode(0xfffd))) violations.push(`12 ${file} — encodage non UTF-8`)

    const lines = text.split("\n")
    lines.forEach((line, i) => {
      if (/[ \t]+$/.test(line)) violations.push(`8 ${file}:${i + 1} — espaces en fin de ligne`)
      if (!TABS_EXEMPT.test(file) && /^\t/.test(line)) violations.push(`11 ${file}:${i + 1} — indentation par tabulation`)
    })
  }

  for (const v of violations) console.log(`FAIL: ${v}`)
  if (violations.length > 0) {
    console.log("")
    console.log(`TOTAL: ${violations.length} violation(s)`)
    process.exit(1)
  }
  console.log("OK: encodage et fins de ligne conformes")
})
'
