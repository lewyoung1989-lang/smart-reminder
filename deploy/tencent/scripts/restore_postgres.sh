#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE=${1:?usage: restore_postgres.sh ENV_FILE BACKUP_FILE}
BACKUP_FILE=${2:?usage: restore_postgres.sh ENV_FILE BACKUP_FILE}
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

python3 "$VALIDATOR" "$ENV_FILE"
BACKUP_DIR=$(python3 "$VALIDATOR" "$ENV_FILE" --get BACKUP_DIR)
POSTGRES_DB=$(python3 "$VALIDATOR" "$ENV_FILE" --get POSTGRES_DB)
POSTGRES_USER=$(python3 "$VALIDATOR" "$ENV_FILE" --get POSTGRES_USER)
export APP_VERSION=operations

BACKUP_ROOT=$(python3 -c \
  'import sys; from pathlib import Path; print(Path(sys.argv[1]).resolve(strict=True))' \
  "$BACKUP_DIR")
BACKUP_REAL=$(python3 -c \
  'import sys; from pathlib import Path; print(Path(sys.argv[1]).resolve(strict=True))' \
  "$BACKUP_FILE")

case "$BACKUP_REAL" in
  "$BACKUP_ROOT"/*) ;;
  *)
    echo "Backup file must be inside BACKUP_DIR" >&2
    exit 1
    ;;
esac

if [[ ! -f "$BACKUP_REAL" ]]; then
  echo "Backup file does not exist" >&2
  exit 1
fi

printf 'Restore %s into database %s. Type RESTORE to continue: ' \
  "$BACKUP_REAL" "$POSTGRES_DB"
read -r CONFIRMATION
if [[ "$CONFIRMATION" != "RESTORE" ]]; then
  echo "Restore cancelled" >&2
  exit 1
fi

COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

"${COMPOSE[@]}" exec -T postgres pg_restore \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --exit-on-error \
  --no-owner \
  --no-acl <"$BACKUP_REAL"

printf 'Restore completed for database %s\n' "$POSTGRES_DB"
