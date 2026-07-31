#!/usr/bin/env bash
# identifiers.sh — 393 booléens préfixés · 394 booléens non négatifs · 400-403 modules fourre-tout
#                  404 constantes en majuscules · 405 types en casse Pascal
#                  406 suffixe Type · 407 préfixe I · 410 suffixe Id · 411 code en anglais
#
# Les fichiers de schéma sont exclus de 393 : `online` décrit un format JSON partagé avec
# des firmwares C, il ne suit pas les conventions TypeScript.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

SCHEMA_FILES="${DOCTOR_SCHEMA_FILES:-identity.ts}"
FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
grep_in() { printf '%s\n' "$2" | tr '\n' '\0' | xargs -0 grep -nE "$1" 2>/dev/null || true; }

while IFS= read -r file; do
  base="${file##*/}"
  case "$base" in
    utils.ts|helpers.ts|common.ts|misc.ts|shared.ts) report "400 $file — module fourre-tout" ;;
  esac
  dir=$(dirname "$file")
  case "${dir##*/}" in
    utils|helpers|common|misc) report "400 $file — dossier fourre-tout" ;;
  esac
done <<< "$FILES"

NON_SCHEMA=$(printf '%s\n' "$FILES" | grep -vE "/($SCHEMA_FILES)$" || true)
if [[ -n "$NON_SCHEMA" ]]; then
  BOOLS=$(grep_in '^[[:space:]]*(readonly[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[?]?:[[:space:]]*boolean' "$NON_SCHEMA")
  [[ -n "$BOOLS" ]] && while IFS= read -r hit; do
    name=$(printf '%s' "$hit" | sed -E 's/.*[^a-zA-Z0-9_]([a-zA-Z_][a-zA-Z0-9_]*)[?]?:[[:space:]]*boolean.*/\1/')
    printf '%s' "$name" | grep -qE '^(is|has|can|should|allow|enable)' \
      || report "393 $hit — booléen \"$name\" sans préfixe is/has/can/should"
    printf '%s' "$name" | grep -qE '^(no|not|dis|un)[A-Z]' \
      && report "394 $hit — booléen formulé négativement"
  done <<< "$BOOLS"
fi

TYPES=$(grep_in '^[[:space:]]*(export[[:space:]]+)?type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$FILES")
[[ -n "$TYPES" ]] && while IFS= read -r hit; do
  name=$(printf '%s' "$hit" | sed -E 's/.*type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/')
  printf '%s' "$name" | grep -qE '^[A-Z][A-Za-z0-9]*$' || report "405 $hit — type \"$name\" hors casse Pascal"
  printf '%s' "$name" | grep -qE '(Type|Interface)$' && report "406 $hit — suffixe redondant sur \"$name\""
  printf '%s' "$name" | grep -qE '^I[A-Z]' && report "407 $hit — préfixe I sur \"$name\""
done <<< "$TYPES"

ACCENTS=$(grep_in '(const|let|function|type)[[:space:]]+[a-zA-Z0-9_]*[éèêàçùôîï]' "$FILES")
[[ -n "$ACCENTS" ]] && while IFS= read -r hit; do
  report "411 $hit — identifiant non anglais"
done <<< "$ACCENTS"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: conventions de nommage respectées"
