#!/usr/bin/env bash
# list-files.sh — énumère les fichiers du dépôt par catégorie
# Usage: list-files.sh [src|test|ts|pkg|tscfg|dts|json|all]
set -euo pipefail

ROOT="${DOCTOR_ROOT:-.}"
MODE="${1:-src}"

# La suite ne s'inspecte pas elle-même : ses scripts contiennent par nature les motifs
# qu'ils recherchent, et ses fixtures sont des violations délibérées.
EXCLUDE="${DOCTOR_EXCLUDE:-^\.doctor/}"

tracked() {
  raw_tracked | grep -vE "$EXCLUDE" || true
}

raw_tracked() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" ls-files
  else
    (cd "$ROOT" && find . -type f \
      -not -path '*/node_modules/*' -not -path '*/.git/*' \
      -not -path '*/dist/*' -not -path '*/.turbo/*' -not -path '*/.next/*' \
      | sed 's|^\./||')
  fi
}

case "$MODE" in
  src)   tracked | grep -E '^(apps|packages)/[^/]+/src/.*\.ts$' | grep -vE '\.(test|d)\.ts$' || true ;;
  test)  tracked | grep -E '\.test\.ts$' || true ;;
  ts)    tracked | grep -E '\.ts$' | grep -vE '\.d\.ts$' || true ;;
  pkg)   tracked | grep -E '^(apps|packages)/[^/]+/package\.json$' || true ;;
  tscfg) tracked | grep -E 'tsconfig[^/]*\.json$' || true ;;
  dts)   tracked | grep -E '\.dts$' || true ;;
  json)  tracked | grep -E '\.json$' || true ;;
  all)   tracked ;;
  *)     echo "mode inconnu: $MODE" >&2; exit 2 ;;
esac
