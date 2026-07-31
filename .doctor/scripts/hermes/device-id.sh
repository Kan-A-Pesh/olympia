#!/usr/bin/env bash
# device-id.sh — 161 identifiant d appareil jamais construit à la volée
#
# Le module dédié est seul autorisé à fabriquer un DeviceId : ailleurs, l identifiant
# se valide par le schéma, il ne s écrit ni en dur ni par interpolation.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

DEVICE_ID_MODULE="${DOCTOR_DEVICE_ID_MODULE:-packages/hermes-protocol/src/device-id.ts}"
ID_ALPHABET="${DOCTOR_ID_ALPHABET:-0-9abcdefghjkmnpqrstvwxyz}"
ID_LENGTH="${DOCTOR_ID_LENGTH:-16}"
ID_TYPE="${DOCTOR_ID_TYPE:-DeviceId}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src | grep -vF "$DEVICE_ID_MODULE" || true)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
scan() {
  local pattern="$1" label="$2" hits
  hits=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -HnE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    echo "FAIL: 161 $hit — $label"
    ERRORS=$((ERRORS + 1))
  done <<< "$hits"
}

scan "\"[a-z][a-z0-9]{0,15}-[$ID_ALPHABET]{$ID_LENGTH}\"" 'identifiant d appareil en dur'
scan "\\bas[[:space:]]+$ID_TYPE\\b"                        "identifiant converti en $ID_TYPE sans validation"
scan 'device[Ii]d[[:space:]]*[:=][[:space:]]*`'            'identifiant assemblé par interpolation'
scan 'device[Ii]d[[:space:]]*[:=][[:space:]]*[^`"]*\+[[:space:]]*"' 'identifiant assemblé par concaténation'

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: tout identifiant d appareil passe par son constructeur"
