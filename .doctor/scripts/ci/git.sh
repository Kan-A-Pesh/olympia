#!/usr/bin/env bash
# git.sh — 464 crochet de pré-validation · 465 le crochet lance doctor · 467 message conventionnel
#          468 historique linéaire · 469 artefact versionné · 470 nom de branche
#          471 commit provisoire · 472 binaire déclaré
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

HOOK_PATHS="${DOCTOR_HOOK_PATHS:-.githooks/pre-commit .husky/pre-commit}"
COMMIT_DEPTH="${DOCTOR_COMMIT_DEPTH:-20}"
SUBJECT_MAX="${DOCTOR_COMMIT_SUBJECT_MAX:-72}"
COMMIT_PATTERN="${DOCTOR_COMMIT_PATTERN:-^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: .+}"
BRANCH_PATTERN="${DOCTOR_BRANCH_PATTERN:-^(main|master|HEAD|(feat|feature|fix|chore|docs|refactor|perf|test|ci|build)/[a-z0-9][a-z0-9._/-]*)$}"
WIP_PATTERN="${DOCTOR_WIP_PATTERN:-^([Ww][Ii][Pp]([^A-Za-z]|$)|fixup!|squash!|amend!|(tmp|temp)([^A-Za-z]|$)|\.+$)}"
GENERATED_PATTERN="${DOCTOR_GENERATED_PATTERN:-(^|/)(coverage|out|storybook-static)/|\.(map|log|orig|rej|bak|min\.js)$|(^|/)\.DS_Store$}"
BINARY_PATTERN="${DOCTOR_BINARY_PATTERN:-\.(png|jpe?g|gif|ico|pdf|zip|gz|tgz|stl|step|stp|3mf|f3d|woff2?|ttf|otf|bin|hex|uf2|elf|img|wav|mp3|mp4|xlsx|docx|sqlite|db)$}"

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN: $1"; }

HOOK=""
for candidate in $HOOK_PATHS; do
  if [[ -f "$candidate" ]]; then HOOK="$candidate"; break; fi
done
if [[ -z "$HOOK" ]]; then
  report "464 aucun crochet de pré-validation parmi: $HOOK_PATHS"
else
  [[ -x "$HOOK" ]] || report "464 $HOOK non exécutable"
  grep -qE '(doctor|run\.sh)' "$HOOK" || report "465 $HOOK ne lance pas la suite de checks"
fi

ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)

GENERATED=$(printf '%s\n' "$ALL" | grep -E "$GENERATED_PATTERN" || true)
if [[ -n "$GENERATED" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] && report "469 $file — artefact généré versionné"
  done <<< "$GENERATED"
fi

BINARIES=$(printf '%s\n' "$ALL" | grep -E "$BINARY_PATTERN" || true)
if [[ -n "$BINARIES" ]]; then
  EXTENSIONS=$(printf '%s\n' "$BINARIES" | sed -E 's/.*\.([A-Za-z0-9]+)$/\1/' | sort -u)
  while IFS= read -r ext; do
    [[ -z "$ext" ]] && continue
    if [[ ! -f .gitattributes ]] || ! grep -qE "\.$ext[[:space:]].*(binary|-text|filter=lfs)" .gitattributes; then
      warn "472 .$ext non déclaré comme binaire dans .gitattributes"
    fi
  done <<< "$EXTENSIONS"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [[ -n "$BRANCH" ]] && ! printf '%s' "$BRANCH" | grep -qE "$BRANCH_PATTERN"; then
    warn "470 branche $BRANCH hors convention ($BRANCH_PATTERN)"
  fi

  ROOTS=$(git rev-list --max-parents=0 HEAD 2>/dev/null || true)
  MERGES=$(git log --merges --format='%h %s' -n "$COMMIT_DEPTH" 2>/dev/null || true)
  if [[ -n "$MERGES" ]]; then
    while IFS= read -r merge; do
      [[ -n "$merge" ]] && warn "468 $merge — commit de fusion, historique non linéaire"
    done <<< "$MERGES"
  fi

  HISTORY=$(git log --no-merges --format='%H %s' -n "$COMMIT_DEPTH" 2>/dev/null || true)
  while read -r sha subject; do
    [[ -z "${sha:-}" ]] && continue
    printf '%s\n' "$ROOTS" | grep -qxF "$sha" && continue
    short="${sha:0:8}"
    if ! printf '%s' "$subject" | grep -qE "$COMMIT_PATTERN"; then
      warn "467 $short — message hors convention: $subject"
    elif [[ "${#subject}" -gt "$SUBJECT_MAX" ]]; then
      warn "467 $short — sujet de ${#subject} caractères (max $SUBJECT_MAX)"
    fi
    if printf '%s' "$subject" | grep -qE "$WIP_PATTERN"; then
      warn "471 $short — commit provisoire: $subject"
    fi
  done <<< "$HISTORY"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: crochet, historique et artefacts conformes"
