#!/usr/bin/env bash
# modules.sh — 403 aucun module « misc », quel que soit son extension ou son exportation
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

CATCH_ALL="${DOCTOR_MISC_NAMES:-misc|miscellaneous|divers}"

ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)
[[ -z "$ALL" ]] && { echo "OK: aucun fichier à inspecter"; exit 0; }

ERRORS=0
report() { echo "FAIL: 403 $1"; ERRORS=$((ERRORS + 1)); }

PATHS=$(printf '%s\n' "$ALL" | grep -iE "(^|/)($CATCH_ALL)(\.|/|$)" || true)
[[ -n "$PATHS" ]] && while IFS= read -r file; do
  report "$file — module fourre-tout « misc »"
done <<< "$PATHS"

SRC=$("$DOCTOR_DIR/utils/list-files.sh" src)
if [[ -n "$SRC" ]]; then
  HITS=$(printf '%s\n' "$SRC" | tr '\n' '\0' \
    | xargs -0 grep -HnE "^[[:space:]]*export[[:space:]]+(const|let|function|class|type|async)[[:space:]]+($CATCH_ALL)" 2>/dev/null || true)
  [[ -n "$HITS" ]] && while IFS= read -r hit; do
    report "$hit — exportation fourre-tout « misc »"
  done <<< "$HITS"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucun module fourre-tout « misc »"
