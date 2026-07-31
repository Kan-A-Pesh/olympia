#!/usr/bin/env bash
# naming.sh — 1 kebab-case fichiers · 2 kebab-case dossiers · 15 extensions minuscules
#             16 pas d'espace · 18 pas de suffixe numéroté · 19 pas de nom provisoire
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

while IFS= read -r file; do
  base="${file##*/}"
  stem="${base%%.*}"
  [[ "$stem" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || report "1 $file — nom hors kebab-case"
  [[ "$base" =~ \.[A-Z] ]] && report "15 $file — extension en majuscules"
  [[ "$stem" =~ -[0-9]+$ ]] && report "18 $file — suffixe numéroté"
  [[ "$stem" =~ (^|-)(tmp|temp|copy|backup|old|new|wip|test2|final)($|-) ]] && report "19 $file — nom provisoire"
done <<< "$FILES"

while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  [[ "$dir" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || report "2 $dir — dossier hors kebab-case"
done <<< "$(printf '%s\n' "$FILES" | tr '/' '\n' | grep -vE '\.ts$' | sort -u)"

while IFS= read -r path; do
  [[ "$path" == *" "* ]] && report "16 $path — espace dans le chemin"
done <<< "$("$DOCTOR_DIR/utils/list-files.sh" all)"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: nommage des fichiers et dossiers conforme"
