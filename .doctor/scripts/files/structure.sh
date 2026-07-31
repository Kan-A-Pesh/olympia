#!/usr/bin/env bash
# structure.sh — 3 pas de baril dans apps · 4 baril à la racine des paquets seulement
#                20 test colocalisé · 21 test sans source
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    apps/*/src/index.ts) report "3 $file — baril interdit dans une app" ;;
    packages/*/src/index.ts) ;;
    */index.ts) report "4 $file — baril autorisé uniquement à la racine d'un paquet" ;;
  esac
done <<< "$("$DOCTOR_DIR/utils/list-files.sh" src)"

while IFS= read -r test; do
  [[ -z "$test" ]] && continue
  source="${test%.test.ts}.ts"
  [[ -f "$source" ]] || report "21 $test — aucun fichier source correspondant ($source)"
done <<< "$("$DOCTOR_DIR/utils/list-files.sh" test)"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: structure des fichiers conforme"
