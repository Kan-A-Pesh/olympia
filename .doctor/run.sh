#!/usr/bin/env bash
# run.sh — exécute tous les checks, imprime un récapitulatif, sort en 1 si l'un échoue
set -uo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR_ROOT="$(cd "$DOCTOR_DIR/.." && pwd)"
export DOCTOR_ROOT

CI_MODE=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=1 ;;
    *) FILTER="$arg" ;;
  esac
done

if [[ "$CI_MODE" -eq 1 || ! -t 1 ]]; then
  RED="" GREEN="" YELLOW="" DIM="" RESET=""
else
  RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' DIM=$'\033[2m' RESET=$'\033[0m'
fi

FAILED=()
WARNED=()
PASSED=0

while IFS= read -r script; do
  name="${script#"$DOCTOR_DIR"/scripts/}"
  name="${name%.sh}"
  [[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue

  output=$(bash "$script" 2>&1)
  status=$?

  if [[ "$status" -ne 0 ]]; then
    FAILED+=("$name")
    printf '%s✗%s %s\n' "$RED" "$RESET" "$name"
    printf '%s\n' "$output" | sed 's/^/    /'
  elif printf '%s' "$output" | grep -q '^WARN:'; then
    WARNED+=("$name")
    printf '%s!%s %s\n' "$YELLOW" "$RESET" "$name"
    printf '%s\n' "$output" | grep '^WARN:' | sed 's/^/    /'
  else
    PASSED=$((PASSED + 1))
    printf '%s✓%s %s%s%s\n' "$GREEN" "$RESET" "$DIM" "$name" "$RESET"
  fi
done < <(find "$DOCTOR_DIR/scripts" -name '*.sh' -type f | sort)

TOTAL=$((PASSED + ${#WARNED[@]} + ${#FAILED[@]}))
printf '\n%d/%d checks passés' "$PASSED" "$TOTAL"
[[ ${#WARNED[@]} -gt 0 ]] && printf ', %d avec avertissement' "${#WARNED[@]}"
[[ ${#FAILED[@]} -gt 0 ]] && printf ', %s%d en échec%s' "$RED" "${#FAILED[@]}" "$RESET"
printf '\n'

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '\nÉchecs : %s\n' "${FAILED[*]}"
  exit 1
fi
