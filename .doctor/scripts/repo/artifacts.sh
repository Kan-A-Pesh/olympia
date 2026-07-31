#!/usr/bin/env bash
# artifacts.sh — 210 fichier volumineux · 211 artefact de build versionné
#                212 sorties couvertes par gitignore · 90 node_modules versionné
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

MAX_BYTES="${MAX_FILE_BYTES:-1048576}"
ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)
[[ -z "$ALL" ]] && { echo "OK: dépôt vide"; exit 0; }

while IFS= read -r file; do
  case "$file" in
    */node_modules/*|node_modules/*) report "90 $file — node_modules versionné" ;;
    */dist/*|dist/*) report "211 $file — artefact de build versionné" ;;
    */.turbo/*|.turbo/*) report "211 $file — cache de build versionné" ;;
    *.tsbuildinfo) report "211 $file — information de compilation versionnée" ;;
    */.next/*|.next/*) report "211 $file — sortie Next versionnée" ;;
  esac
done <<< "$ALL"

SIZES=$(printf '%s\n' "$ALL" | tr '\n' '\0' | xargs -0 stat -f '%z %N' 2>/dev/null \
     || printf '%s\n' "$ALL" | tr '\n' '\0' | xargs -0 stat -c '%s %n' 2>/dev/null || true)
if [[ -n "$SIZES" ]]; then
  while read -r bytes file; do
    [[ -z "${file:-}" ]] && continue
    [[ "$bytes" -gt "$MAX_BYTES" ]] && report "210 $file — $bytes octets (max $MAX_BYTES)"
  done <<< "$SIZES"
fi

for required in "node_modules/" "dist/" ".turbo/"; do
  grep -qxF "$required" .gitignore 2>/dev/null || report "212 .gitignore — motif \"$required\" absent"
done

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucun artefact ni fichier volumineux versionné"
