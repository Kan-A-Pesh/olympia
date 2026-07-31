#!/usr/bin/env bash
# paths.sh — 57/58 import relatif profond · 61 import depuis dist · 62 import du src d un paquet
#            63 extension .js manquante · 66 import dupliqué · 67 import à effet de bord
#            68 préfixe node: · 72 require · 74 auto-import
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
scan() {
  local id="$1" pattern="$2" label="$3" hits
  hits=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -nE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    echo "FAIL: $id $hit — $label"
    ERRORS=$((ERRORS + 1))
  done <<< "$hits"
}

scan 57 'from[[:space:]]+"\.\./\.\./\.\./'  'import relatif de plus de deux niveaux'
scan 61 'from[[:space:]]+"[^"]*/dist/'      'import pointant vers dist'
scan 62 'from[[:space:]]+"@olympia/[^"]+/src' 'import du src interne d un paquet'
scan 68 'from[[:space:]]+"(fs|path|os|crypto|events|child_process|util|stream|url|http|https|net|tls|zlib|buffer)"' 'module natif sans préfixe node:'
scan 72 '(^|[^.[:alnum:]])require\('        'appel require'
scan 67 '^[[:space:]]*import[[:space:]]+"'  'import pour son seul effet de bord'

MISSING_EXT=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -nE 'from[[:space:]]+"\.{1,2}/[^"]*"' 2>/dev/null \
  | grep -vE '\.(js|json|css)"' || true)
if [[ -n "$MISSING_EXT" ]]; then
  while IFS= read -r hit; do
    echo "FAIL: 63 $hit — import relatif sans extension .js"
    ERRORS=$((ERRORS + 1))
  done <<< "$MISSING_EXT"
fi

DUPES=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -nE '^import .* from "' 2>/dev/null \
  | sed -E 's/^([^:]+):[0-9]+:.* from "([^"]+)".*$/\1 \2/' \
  | sort | uniq -d || true)
if [[ -n "$DUPES" ]]; then
  while IFS= read -r dupe; do
    echo "FAIL: 66 $dupe — module importé plusieurs fois"
    ERRORS=$((ERRORS + 1))
  done <<< "$DUPES"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: chemins d import conformes"
