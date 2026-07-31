#!/usr/bin/env bash
# classes.sh — 48 classe abstraite · 49 héritage hors Error/EventEmitter
#              50 champs privés en # · 51 propriétés déclarées dans le constructeur
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ALLOWED_BASE="${DOCTOR_ALLOWED_BASE:-Error|EventEmitter}"
ERRORS=0

grep_all() { printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -HnE "$1" 2>/dev/null || true; }

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  echo "FAIL: 48 $hit — classe abstraite"
  ERRORS=$((ERRORS + 1))
done <<< "$(grep_all '^[[:space:]]*(export[[:space:]]+)?abstract[[:space:]]+class')"

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  printf '%s' "$hit" | grep -qE "extends[[:space:]]+($ALLOWED_BASE)\b" && continue
  echo "FAIL: 49 $hit — héritage hors $ALLOWED_BASE"
  ERRORS=$((ERRORS + 1))
done <<< "$(grep_all 'class[[:space:]]+[A-Za-z_]+[^{]*[[:space:]]extends[[:space:]]')"

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  echo "FAIL: 50 $hit — utiliser un champ # plutôt que private/protected"
  ERRORS=$((ERRORS + 1))
done <<< "$(grep_all '^[[:space:]]*(private|protected)[[:space:]]')"

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  echo "FAIL: 51 $hit — propriété déclarée dans le constructeur"
  ERRORS=$((ERRORS + 1))
done <<< "$(grep_all 'constructor[[:space:]]*\([^)]*\b(private|public|protected|readonly)[[:space:]]')"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: usage des classes conforme"
