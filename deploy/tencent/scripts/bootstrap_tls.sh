#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE=${1:?usage: bootstrap_tls.sh ENV_FILE}
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

python3 "$VALIDATOR" "$ENV_FILE"
DOMAIN=$(python3 "$VALIDATOR" "$ENV_FILE" --get DOMAIN)
CERTBOT_EMAIL=$(python3 "$VALIDATOR" "$ENV_FILE" --get CERTBOT_EMAIL)
export APP_VERSION=bootstrap

COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

cleanup() {
  "${COMPOSE[@]}" --profile bootstrap stop nginx-bootstrap >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${COMPOSE[@]}" --profile bootstrap up -d nginx-bootstrap
"${COMPOSE[@]}" --profile certbot run --rm certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --domain "$DOMAIN" \
  --email "$CERTBOT_EMAIL" \
  --agree-tos \
  --no-eff-email \
  --non-interactive
