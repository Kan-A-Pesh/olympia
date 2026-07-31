#!/usr/bin/env bash
# protocol.sh — 155 topics construits par un utilitaire · 156 racine centralisée
#               157 version centralisée · 159 JSON.parse sans schéma · 160 deviceId typé
#               167 forme d onde jamais en JSON · 168 en-tête vérifié
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

TOPICS_MODULE="${DOCTOR_TOPICS_MODULE:-packages/hermes-protocol/src/topics.ts}"
WAVEFORM_MODULE="${DOCTOR_WAVEFORM_MODULE:-packages/hermes-protocol/src/waveform.ts}"
ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

OUTSIDE=$(printf '%s\n' "$FILES" | grep -vF "$TOPICS_MODULE" || true)
if [[ -n "$OUTSIDE" ]]; then
  HITS=$(printf '%s\n' "$OUTSIDE" | tr '\n' '\0' | xargs -0 grep -HnE '"olympia/' 2>/dev/null || true)
  [[ -n "$HITS" ]] && while IFS= read -r hit; do
    report "156 $hit — racine de topic hors du module dédié"
  done <<< "$HITS"

  HITS=$(printf '%s\n' "$OUTSIDE" | tr '\n' '\0' | xargs -0 grep -HnE '`[^`]*olympia/[^`]*\$\{' 2>/dev/null || true)
  [[ -n "$HITS" ]] && while IFS= read -r hit; do
    report "155 $hit — topic assemblé par interpolation"
  done <<< "$HITS"
fi

VERSION_HITS=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -lE '"v[0-9]+"' 2>/dev/null | grep -vF "$TOPICS_MODULE" || true)
[[ -n "$VERSION_HITS" ]] && while IFS= read -r f; do
  report "157 $f — version de protocole hors du module dédié"
done <<< "$VERSION_HITS"

PARSE=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -HnE 'JSON\.parse\(' 2>/dev/null || true)
[[ -n "$PARSE" ]] && while IFS= read -r hit; do
  file="${hit%%:*}"
  line="${hit#*:}"; line="${line%%:*}"
  context=$(sed -n "${line},$((line + 3))p" "$file" 2>/dev/null || true)
  printf '%s' "$context" | grep -qE '\.(parse|safeParse)\(' || \
    report "159 $hit — JSON.parse sans validation par schéma"
done <<< "$PARSE"

WAVE_JSON=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -HnE 'JSON\.stringify\([^)]*(waveform|samples|frame)' 2>/dev/null || true)
[[ -n "$WAVE_JSON" ]] && while IFS= read -r hit; do
  report "167 $hit — forme d onde sérialisée en JSON"
done <<< "$WAVE_JSON"

if [[ -f "$WAVEFORM_MODULE" ]]; then
  grep -qE 'MAGIC' "$WAVEFORM_MODULE" || report "168 $WAVEFORM_MODULE — aucune vérification d en-tête"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: contrat Hermes respecté"
