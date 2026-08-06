#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE=${1:?usage: backup_postgres.sh ENV_FILE}
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

source "$ROOT_DIR/deploy/tencent/scripts/operation_logging.sh"
start_operation_log backup

python3 "$VALIDATOR" "$ENV_FILE"
BACKUP_DIR=$(python3 "$VALIDATOR" "$ENV_FILE" --get BACKUP_DIR)
BACKUP_RETENTION_DAYS=$(python3 "$VALIDATOR" "$ENV_FILE" --get BACKUP_RETENTION_DAYS)
POSTGRES_DB=$(python3 "$VALIDATOR" "$ENV_FILE" --get POSTGRES_DB)
POSTGRES_USER=$(python3 "$VALIDATOR" "$ENV_FILE" --get POSTGRES_USER)
export APP_VERSION=operations

mkdir -p -- "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_FILE="$BACKUP_DIR/smart_reminder-$TIMESTAMP.dump"
TEMP_FILE="$BACKUP_DIR/.smart_reminder-$TIMESTAMP.dump.tmp"

operation_cleanup() {
  if [[ -n "${TEMP_FILE:-}" ]]; then
    rm -f -- "$TEMP_FILE"
  fi
}

COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

"${COMPOSE[@]}" exec -T postgres pg_dump \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --format=custom \
  --no-owner \
  --no-acl >"$TEMP_FILE"

chmod 600 "$TEMP_FILE"
mv -- "$TEMP_FILE" "$BACKUP_FILE"
TEMP_FILE=""

find "$BACKUP_DIR" \
  -type f \
  -name 'smart_reminder-*.dump' \
  -mtime "+$BACKUP_RETENTION_DAYS" \
  -delete

printf 'Backup created: %s\n' "$BACKUP_FILE"
