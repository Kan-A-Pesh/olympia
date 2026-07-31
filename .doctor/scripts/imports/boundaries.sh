#!/usr/bin/env bash
# boundaries.sh — 59 app vers app · 60 paquet vers app · 62 point d entrée
#                 69 API Node dans un paquet partagé · 74 auto-import · 97 relatif inter-paquets
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

FILES=$("$DOCTOR_DIR/utils/list-files.sh" ts)
[[ -z "$FILES" ]] && { echo "OK: aucun fichier source à inspecter"; exit 0; }

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

IMPORTS=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
  | xargs -0 grep -HnE '^[[:space:]]*(import|export)[^;]* from "' 2>/dev/null || true)
[[ -z "$IMPORTS" ]] && { echo "OK: aucun import à inspecter"; exit 0; }

while IFS= read -r line; do
  file="${line%%:*}"
  spec=$(printf '%s' "$line" | sed -E 's/.* from "([^"]+)".*/\1/')
  owner=$(printf '%s' "$file" | cut -d/ -f1-2)

  case "$file/$spec" in
    apps/*) ;;
  esac

  if [[ "$file" == apps/* && "$spec" == @olympia/* ]]; then
    target="${spec#@olympia/}"
    target="${target%%/*}"
    [[ -d "apps/$target" && "apps/$target" != "$owner" ]] && report "59 $file — une app en importe une autre ($spec)"
  fi

  if [[ "$file" == packages/* && "$spec" == @olympia/* ]]; then
    target="${spec#@olympia/}"
    target="${target%%/*}"
    [[ -d "apps/$target" ]] && report "60 $file — un paquet importe une app ($spec)"
  fi

  if [[ "$spec" == @olympia/* ]]; then
    target="${spec#@olympia/}"
    target="${target%%/*}"
    [[ "packages/$target" == "$owner" || "apps/$target" == "$owner" ]] && report "74 $file — le paquet s importe lui-même par son nom"
  fi

  if [[ "$spec" == ../../* && "$spec" != ../../../* ]]; then
    resolved=$(cd "$(dirname "$file")" 2>/dev/null && cd "$(dirname "$spec")" 2>/dev/null && pwd || echo "")
    if [[ -n "$resolved" ]]; then
      rel="${resolved#"$PWD"/}"
      [[ "$rel" == "$owner"* ]] || report "97 $file — import relatif franchissant un paquet ($spec)"
    fi
  fi
done <<< "$IMPORTS"

SHARED=$(printf '%s\n' "$FILES" | grep -E '^packages/hermes-protocol/' || true)
if [[ -n "$SHARED" ]]; then
  NODE_API=$(printf '%s\n' "$SHARED" | tr '\n' '\0' \
    | xargs -0 grep -HnE 'from "node:' 2>/dev/null || true)
  if [[ -n "$NODE_API" ]]; then
    while IFS= read -r hit; do
      report "69 $hit — API Node dans un paquet destiné aussi au navigateur"
    done <<< "$NODE_API"
  fi
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: frontières entre paquets respectées"
