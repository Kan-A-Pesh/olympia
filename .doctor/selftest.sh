#!/usr/bin/env bash
# selftest.sh — vérifie que chaque check attrape une vraie violation
#
# Fabrique un dépôt jetable, y déverse toutes les fixtures déclarées dans fixtures/, puis
# confirme que le check correspondant sort bien en échec. Un check qui ne signale rien ici
# est un check qui ne protège rien.
#
# Chaque check `scripts/<famille>/<nom>.sh` déclare ses violations dans
# `fixtures/<famille>/<nom>.sh`, un script qui écrit ses fichiers dans le dossier courant.
# Un check sans fixture est signalé comme non vérifié.
set -uo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

cd "$FIXTURE"
mkdir -p apps/bad-app/src packages/bad-pkg/src hardware/bad-case firmware/bad-fw
printf 'node_modules/\n' > .gitignore

FIXTURE_SCRIPTS=$(find "$DOCTOR_DIR/fixtures" -name '*.sh' -type f 2>/dev/null | sort)
if [[ -z "$FIXTURE_SCRIPTS" ]]; then
  echo "FAIL: aucune fixture déclarée dans .doctor/fixtures/"
  exit 1
fi

while IFS= read -r fixture; do
  ( cd "$FIXTURE" && bash "$fixture" ) || {
    echo "FAIL: fixture illisible: ${fixture#"$DOCTOR_DIR"/}"
    exit 1
  }
done <<< "$FIXTURE_SCRIPTS"

git init -q . && git add -A >/dev/null 2>&1
export DOCTOR_ROOT="$FIXTURE"

BLIND=()
UNCOVERED=()
CAUGHT=0

while IFS= read -r script; do
  name="${script#"$DOCTOR_DIR"/scripts/}"
  name="${name%.sh}"

  if [[ ! -f "$DOCTOR_DIR/fixtures/$name.sh" ]]; then
    UNCOVERED+=("$name")
    printf '? %s — aucune fixture\n' "$name"
    continue
  fi

  if bash "$script" >/dev/null 2>&1; then
    BLIND+=("$name")
    printf '✗ %s — n a rien détecté sur les fixtures\n' "$name"
  else
    CAUGHT=$((CAUGHT + 1))
    printf '✓ %s\n' "$name"
  fi
done < <(find "$DOCTOR_DIR/scripts" -name '*.sh' -type f | sort)

TOTAL=$((CAUGHT + ${#BLIND[@]} + ${#UNCOVERED[@]}))
printf '\n%d/%d checks ont attrapé leur violation\n' "$CAUGHT" "$TOTAL"

[[ ${#UNCOVERED[@]} -gt 0 ]] && printf 'Sans fixture : %s\n' "${UNCOVERED[*]}"
[[ ${#BLIND[@]} -gt 0 ]] && printf 'Aveugles : %s\n' "${BLIND[*]}"
[[ ${#BLIND[@]} -gt 0 || ${#UNCOVERED[@]} -gt 0 ]] && exit 1
exit 0
