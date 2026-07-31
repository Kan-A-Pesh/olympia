#!/usr/bin/env bash
# dts.sh — 186 chaque .dts compile avec dtc
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" dts)
[[ -z "$FILES" ]] && { echo "OK: aucun device tree à compiler"; exit 0; }

COUNT=$(printf '%s\n' "$FILES" | grep -c . || true)

if ! command -v dtc >/dev/null 2>&1; then
  echo "OK: $COUNT device tree non compilés — dtc absent de cette machine"
  exit 0
fi

ERRORS=0
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if ! log=$(dtc -@ -I dts -O dtb -o "$OUT/$(basename "$file").dtbo" "$file" 2>&1); then
    echo "FAIL: 186 $file — ne compile pas"
    printf '%s\n' "$log" | sed 's/^/       /'
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$FILES"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: $COUNT device tree compilent"
