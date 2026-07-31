#!/usr/bin/env bash
# docs.sh — 22 chaque paquet a un README.md (absent : avertissement, squelette : échec)
#
# Un README réduit à son titre est pire qu absent : il éteint l avertissement sans rien
# documenter, d où l échec au-dessous du seuil de lignes.
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

MIN_LINES="${DOCTOR_README_MIN_LINES:-3}"
README_NAME="${DOCTOR_README_NAME:-README.md}"

PACKAGES=$("$DOCTOR_DIR/utils/list-files.sh" pkg)
[[ -z "$PACKAGES" ]] && { echo "OK: aucun paquet à inspecter"; exit 0; }

ERRORS=0
WARNINGS=0
PRESENT=""

while IFS= read -r manifest; do
  [[ -z "$manifest" ]] && continue
  dir="${manifest%/package.json}"
  if [[ -f "$dir/$README_NAME" ]]; then
    PRESENT+="$dir/$README_NAME"$'\n'
  else
    echo "WARN: 22 $dir — aucun $README_NAME"
    WARNINGS=$((WARNINGS + 1))
  fi
done <<< "$PACKAGES"

if [[ -n "$PRESENT" ]]; then
  COUNTS=$(printf '%s' "$PRESENT" | tr '\n' '\0' | xargs -0 wc -l | grep -vE '[[:space:]]total$' || true)
  while read -r lines file; do
    [[ -z "${file:-}" ]] && continue
    if [[ "$lines" -lt "$MIN_LINES" ]]; then
      echo "FAIL: 22 $file — $lines ligne(s), README squelette (minimum $MIN_LINES)"
      ERRORS=$((ERRORS + 1))
    fi
  done <<< "$COUNTS"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
[[ "$WARNINGS" -gt 0 ]] && echo "OK: aucun README squelette ($WARNINGS avertissement(s))" \
                        || echo "OK: chaque paquet est documenté"
