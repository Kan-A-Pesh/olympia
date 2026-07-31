#!/usr/bin/env bash
# discipline.sh — 135 paquet sans test · 136 .skip · 137 .only · 138 test sans assertion
#                 140 instantanés · 143 console dans un test · 144 réseau réel
#                 145 disque en unitaire · 146 temporisation · 152 noms dupliqués
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

TESTS=$("$DOCTOR_DIR/utils/list-files.sh" test)
[[ -z "$TESTS" ]] && { echo "OK: aucun fichier de test à inspecter"; exit 0; }

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
scan() {
  local id="$1" pattern="$2" label="$3" hits
  hits=$(printf '%s\n' "$TESTS" | tr '\n' '\0' | xargs -0 grep -HnE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do report "$id $hit — $label"; done <<< "$hits"
}

scan 136 '\b(describe|it|test)\.skip\b'        'test désactivé'
scan 137 '\b(describe|it|test)\.only\b'        'test isolé'
scan 140 'toMatchSnapshot|toMatchInlineSnapshot' 'test par instantané'
scan 143 'console\.'                            'trace laissée dans un test'
scan 144 '(fetch\(|new WebSocket\(|http\.request|axios\.)' 'appel réseau réel'
scan 145 '(readFileSync|writeFileSync|mkdirSync|rmSync)\(' 'accès disque en test unitaire'
scan 146 'setTimeout\([^,]*,[[:space:]]*[0-9]+' 'attente par temporisation'

while IFS= read -r file; do
  bodies=$(grep -cE '^\s*(it|test)\(' "$file" || true)
  asserts=$(grep -cE 'expect\(' "$file" || true)
  [[ "$bodies" -gt 0 && "$asserts" -lt "$bodies" ]] \
    && report "138/139 $file — $bodies tests pour seulement $asserts assertions"

  dupes=$(grep -oE '^\s*(it|test)\("[^"]+"' "$file" | sed -E 's/.*"([^"]+)"/\1/' | sort | uniq -d || true)
  [[ -n "$dupes" ]] && while IFS= read -r d; do
    report "152 $file — nom de test dupliqué: \"$d\""
  done <<< "$dupes"
done <<< "$TESTS"

while IFS= read -r pkg; do
  dir=$(dirname "$pkg")
  printf '%s\n' "$TESTS" | grep -q "^$dir/" || report "135 $dir — aucun test"
done <<< "$("$DOCTOR_DIR/utils/list-files.sh" pkg)"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: discipline de test respectée"
