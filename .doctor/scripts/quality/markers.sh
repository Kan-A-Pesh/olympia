#!/usr/bin/env bash
# markers.sh — 108 TODO · 109 FIXME
#
# Le check 106 (nombres magiques) a été retiré de ce lot : sur du code qui manipule un
# protocole binaire et des schémas de validation, il ne distingue pas un littéral
# arithmétique d'une borne de schéma ou d'un décalage de structure. Repoussé au lot AST.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
MARKERS=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -HnE '(TODO|FIXME|XXX|HACK)' 2>/dev/null || true)

if [[ -n "$MARKERS" ]]; then
  while IFS= read -r hit; do
    echo "FAIL: 108 $hit — marqueur interdit, ouvrir une issue"
    ERRORS=$((ERRORS + 1))
  done <<< "$MARKERS"
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucun marqueur de travail en attente"
