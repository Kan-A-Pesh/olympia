#!/usr/bin/env bash
# hardening.sh — 180 empreinte comparée à temps constant · 183 chemin issu d une entrée
#                non validée · 184 variable d environnement validée par un schéma
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

SECRET_WORDS="${DOCTOR_SECRET_WORDS:-[Ff]ingerprint[A-Za-z0-9_]*|[Tt]humbprint[A-Za-z0-9_]*|[Dd]igest|[Hh]mac|HMAC}"
PATH_CALLS="${DOCTOR_PATH_CALLS:-join|resolve|readFile|readFileSync|writeFile|writeFileSync|appendFile|createReadStream|createWriteStream|readdir|readdirSync|unlink|rm|rmSync|mkdir|open|opendir|stat}"
UNTRUSTED="${DOCTOR_UNTRUSTED:-(req|request|params|query|body|searchParams|argv|userInput|formData|payload|topic|deviceId|env)}"

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

scan 180 "($SECRET_WORDS)[^A-Za-z0-9_=!][^=!]*[=!]==" 'empreinte comparée avec ==, timingSafeEqual attendu'
scan 183 "($PATH_CALLS)\\([^)]*\\\$\\{[[:space:]]*$UNTRUSTED" 'chemin construit depuis une entrée non validée'

ENV_FILES=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -lE 'process\.env' 2>/dev/null || true)
if [[ -n "$ENV_FILES" ]]; then
  UNVALIDATED=$(printf '%s\n' "$ENV_FILES" | tr '\n' '\0' \
    | xargs -0 grep -LE '\.(safeParse|parse)\(' 2>/dev/null || true)
  [[ -n "$UNVALIDATED" ]] && while IFS= read -r file; do
    echo "FAIL: 184 $file — variables d environnement lues sans schéma de validation"
    ERRORS=$((ERRORS + 1))
  done <<< "$UNVALIDATED"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: comparaisons, chemins et environnement sous contrôle"
