#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE=${1:?usage: renew_certificate.sh ENV_FILE}
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

source "$ROOT_DIR/deploy/tencent/scripts/operation_logging.sh"
start_operation_log cert

python3 "$VALIDATOR" "$ENV_FILE"
export APP_VERSION=operations

COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

"${COMPOSE[@]}" --profile certbot run --rm certbot renew \
  --webroot \
  --webroot-path /var/www/certbot
"${COMPOSE[@]}" --profile production exec -T nginx nginx -t
"${COMPOSE[@]}" --profile production exec -T nginx nginx -s reload
