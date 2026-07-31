#!/usr/bin/env bash
# banned-syntax.sh — 23 `any` · 24 `as any` · 25 double conversion · 26 ts-ignore
#                    27 ts-expect-error sans raison · 30 mot-clé interface · 32 namespace
#                    37 export let · 39 var · 40 type Object · 41 type Function
#                    42 enveloppes primitives · 47 directive triple slash · 54 type vide
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

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

scan 23 ':[[:space:]]*any([[:space:]]*[,);=>}]|$)' 'annotation any'
scan 24 '\bas any\b'                                'conversion vers any'
scan 25 '\bas unknown as\b'                         'double conversion'
scan 26 '@ts-ignore'                                'suppression d erreur non tracée'
scan 27 '@ts-expect-error[[:space:]]*$'             'suppression sans explication'
scan 30 '^[[:space:]]*(export[[:space:]]+)?interface[[:space:]]'  'mot-clé interface, utiliser type'
scan 32 '^[[:space:]]*(export[[:space:]]+)?namespace[[:space:]]'  'namespace'
scan 37 '^[[:space:]]*export[[:space:]]+let[[:space:]]'           'export mutable'
scan 39 '^[[:space:]]*var[[:space:]]'                             'déclaration var'
scan 40 ':[[:space:]]*(Object|\{\})([[:space:]]*[,);=>}]|$)'      'type Object ou {}'
scan 41 ':[[:space:]]*Function([[:space:]]*[,);=>}]|$)'           'type Function'
scan 42 ':[[:space:]]*(String|Number|Boolean|Symbol)([[:space:]]*[,);=>}]|$)' 'enveloppe primitive'
scan 47 '^///[[:space:]]*<reference'                              'directive triple slash'
scan 54 '=[[:space:]]*\{[[:space:]]*\}[[:space:]]*$'              'type vide'

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucune syntaxe interdite"
