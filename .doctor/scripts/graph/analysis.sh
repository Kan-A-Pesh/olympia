#!/usr/bin/env bash
# analysis.sh — un seul graphe de modules, toutes les règles dessus
#   64 cycle d'import · 65 import inutilisé · 75 import interne non déclaré
#   76/423 dépendance fantôme · 98 dépendance d'exécution en devDependencies
#   124 export non consommé (WARN) · 125 fichier inatteignable · 46 import type
#   35 paramètre sans type · 56 union sans discriminant (WARN) · 99 fonction trop longue
#   101 complexité · 102 imbrication · 105 bloc dupliqué (WARN) · 117 promesse non attendue
#   130 else après sortie anticipée · 133 switch non exhaustif · 381 regex exponentielle
#   422 dépendance déclarée non importée · 507 annotation redondante (WARN)
#   154 export non testé (WARN, DOCTOR_GRAPH_UNTESTED_EXPORTS=1)
# Seuils : DOCTOR_MAX_COMPLEXITY(10) DOCTOR_MAX_FUNCTION_LINES(60) DOCTOR_MAX_NESTING(4)
#          DOCTOR_DUP_LINES(12) DOCTOR_GRAPH_ROOTS DOCTOR_GRAPH_TOOLCHAIN
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

"$DOCTOR_DIR/utils/list-files.sh" all | node "$DOCTOR_DIR/scripts/graph/analysis.mjs"
