#!/usr/bin/env bash
# size.sh — 5 taille de fichier · 7 fichier vide · 148 taille des fichiers de test
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FAIL_AT="${MAX_FILE_FAIL:-500}"
WARN_AT="${MAX_FILE_WARN:-350}"
TEST_WARN_AT="${MAX_TEST_WARN:-400}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

COUNTS=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 wc -l | grep -vE ' total$' || true)

ERRORS=0
WARNINGS=0
while read -r lines file; do
  [[ -z "${file:-}" ]] && continue
  if [[ "$lines" -eq 0 ]]; then
    echo "FAIL: 7 $file — fichier vide"
    ERRORS=$((ERRORS + 1))
  elif [[ "$file" == *.test.ts ]]; then
    if [[ "$lines" -gt "$TEST_WARN_AT" ]]; then
      echo "WARN: 148 $file — $lines lignes (seuil $TEST_WARN_AT)"
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [[ "$lines" -gt "$FAIL_AT" ]]; then
    echo "FAIL: 5 $file — $lines lignes (max $FAIL_AT)"
    ERRORS=$((ERRORS + 1))
  elif [[ "$lines" -gt "$WARN_AT" ]]; then
    echo "WARN: 5 $file — $lines lignes (seuil $WARN_AT)"
    WARNINGS=$((WARNINGS + 1))
  fi
done <<< "$COUNTS"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
[[ "$WARNINGS" -gt 0 ]] && echo "OK: aucun dépassement bloquant ($WARNINGS avertissement(s))" \
                        || echo "OK: tous les fichiers dans les limites"
