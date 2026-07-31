#!/usr/bin/env bash
# secrets.sh — 170 secret en dur · 171 clé privée · 172 certificat · 173 identifiants WiFi
#              174 mot de passe par défaut · 175 port MQTT en clair · 176 vérification TLS
#              177 version TLS · 178 empreintes obsolètes · 179 aléatoire non cryptographique
#              182 shell interpolé · 185 fichier .env
set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${DOCTOR_ROOT:-$DOCTOR_DIR/..}"

ERRORS=0
report() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }

ALL=$("$DOCTOR_DIR/utils/list-files.sh" all)
while IFS= read -r file; do
  case "$file" in
    *.pem|*.key|*.p12|*.pfx|*.crt) report "172 $file — matériel cryptographique versionné" ;;
    .env|.env.*|*/.env) report "185 $file — fichier d environnement versionné" ;;
  esac
done <<< "$ALL"

TEXT=$(printf '%s\n' "$ALL" | grep -E '\.(ts|js|json|sh|dts|snippet|yaml|yml)$' || true)
[[ -z "$TEXT" ]] && { echo "OK: aucun fichier à inspecter"; exit 0; }

scan() {
  local id="$1" pattern="$2" label="$3" hits
  hits=$(printf '%s\n' "$TEXT" | tr '\n' '\0' | xargs -0 grep -HnE "$pattern" 2>/dev/null || true)
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do report "$id $hit — $label"; done <<< "$hits"
}

scan 171 'BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+)?PRIVATE[[:space:]]+KEY' 'clé privée en clair'
scan 170 '(api[_-]?key|secret|token|passwd|password)[[:space:]]*[:=][[:space:]]*"[A-Za-z0-9/+_-]{16,}"' 'secret en dur'
scan 173 '(ssid|wifi[_-]?pass)[[:space:]]*[:=][[:space:]]*"[^"]+"' 'identifiants WiFi en dur'
scan 174 '"(admin|root|changeme|password|123456)"' 'mot de passe par défaut'
scan 175 '(mqtt://|:1883)' 'connexion MQTT non chiffrée'
scan 176 'rejectUnauthorized[[:space:]]*:[[:space:]]*false' 'vérification de certificat désactivée'
scan 177 '(TLSv1(\.[01])?|SSLv[23])' 'version TLS obsolète'
scan 178 'createHash\("(md5|sha1)"\)' 'empreinte cryptographique obsolète'
scan 182 '(exec|execSync|spawnSync)\([^)]*\$\{' 'commande shell interpolée'

RANDOM_HITS=$(printf '%s\n' "$TEXT" | tr '\n' '\0' \
  | xargs -0 grep -HnE 'Math\.random\(' 2>/dev/null || true)
[[ -n "$RANDOM_HITS" ]] && while IFS= read -r hit; do
  report "179 $hit — aléatoire non cryptographique"
done <<< "$RANDOM_HITS"

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "TOTAL: $ERRORS violation(s)"
  exit 1
fi
echo "OK: aucun secret ni usage cryptographique douteux"
