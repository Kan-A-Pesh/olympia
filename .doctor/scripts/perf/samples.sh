#!/usr/bin/env bash
# samples.sh — 369 tableaux typés · 370 conversion en tableau ordinaire · 371 étalement
#              372 parcours fonctionnel · 374 copie au lieu d une vue · 384 copie profonde
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" src)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

SAMPLE_IDS="${DOCTOR_SAMPLE_IDS:-samples|sampleBuffer|channelData|waveform|pixels}"
ERRORS=0

grep_all() {
  printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -nE "$1" /dev/null 2>/dev/null || true
}

scan() {
  local id="$1" pattern="$2" label="$3" level="$4" hits
  hits=$(grep_all "$pattern")
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    echo "$level: $id $hit — $label"
    if [[ "$level" == "FAIL" ]]; then ERRORS=$((ERRORS + 1)); fi
  done <<< "$hits"
  return 0
}

scan 369 "($SAMPLE_IDS)\??[[:space:]]*:[[:space:]]*(readonly[[:space:]]+)?(number\[\]|Array<number>)" \
  'échantillons en tableau ordinaire au lieu d un tableau typé' FAIL
scan 370 "Array\.from\([^)]*($SAMPLE_IDS)" \
  'tableau typé converti en tableau ordinaire' FAIL
scan 371 "\.\.\.[[:space:]]*[A-Za-z_$.#]*($SAMPLE_IDS)([^A-Za-z0-9_]|$)" \
  'étalement sur un tableau d échantillons' FAIL
scan 372 "($SAMPLE_IDS)\.(map|filter|reduce|reduceRight|forEach|flatMap|some|every|find)\(" \
  'parcours fonctionnel sur les échantillons' WARN
scan 374 "($SAMPLE_IDS)\.slice\(" \
  'copie là où une vue subarray suffit' WARN
scan 384 "(structuredClone|cloneDeep|klona|deepClone)\(" \
  'copie profonde d objet volumineux' WARN

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: échantillons manipulés en tableaux typés"
