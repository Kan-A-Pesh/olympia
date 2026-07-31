#!/usr/bin/env bash
# banned-calls.sh — 107 code en commentaire · 110 console · 111 debugger · 112 alert
#                   113 catch vide · 115 throw non-Error · 121 API synchrone · 122 process.exit
#                   129 ternaire imbriqué · 181 eval · 385 copie par sérialisation
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
scan() {
  local id="$1" pattern="$2" label="$3" hits
  hits=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -HnE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    echo "FAIL: $id $hit — $label"
    ERRORS=$((ERRORS + 1))
  done <<< "$hits"
}

scan 107 '^[[:space:]]*//[[:space:]]*(const|let|function|return|if|for|while|import|export)[[:space:]]' 'code laissé en commentaire'
scan 110 '(^|[^.[:alnum:]])console\.'          'appel console'
scan 111 '(^|[^.[:alnum:]])debugger([^[:alnum:]]|$)' 'instruction debugger'
scan 112 '(^|[^.[:alnum:]])(alert|confirm|prompt)\(' 'boîte de dialogue bloquante'
scan 113 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}' 'bloc catch vide'
scan 115 'throw[[:space:]]+["'"'"'`{[]'         'valeur lancée qui n est pas une Error'
scan 121 '(readFileSync|writeFileSync|existsSync|mkdirSync|readdirSync|execSync)\(' 'API synchrone hors outillage'
scan 122 'process\.exit\('                      'process.exit hors point d entrée'
scan 181 '(^|[^.[:alnum:]])(eval|new[[:space:]]+Function)\(' 'évaluation dynamique'
scan 385 'JSON\.parse\([[:space:]]*JSON\.stringify' 'copie par sérialisation'

NESTED=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -HnE '\?[^?:]*\?[^?:]*:' 2>/dev/null | grep -vE '\?\.' || true)
if [[ -n "$NESTED" ]]; then
  while IFS= read -r hit; do
    echo "FAIL: 129 $hit — ternaire imbriqué"
    ERRORS=$((ERRORS + 1))
  done <<< "$NESTED"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucun appel interdit"
