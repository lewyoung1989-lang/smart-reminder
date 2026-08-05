#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
EXPECTED_SHA=${1:?usage: deploy.sh EXPECTED_SHA ENV_FILE}
ENV_FILE=${2:?usage: deploy.sh EXPECTED_SHA ENV_FILE}

cd "$ROOT_DIR"
python3 deploy/tencent/scripts/check_env.py "$ENV_FILE"

ACTUAL_SHA=$(git rev-parse HEAD)
EXPECTED_FULL=$(git rev-parse --verify "${EXPECTED_SHA}^{commit}")
if [[ "$ACTUAL_SHA" != "$EXPECTED_FULL" ]]; then
  echo "HEAD does not match EXPECTED_SHA" >&2
  exit 1
fi

git diff --quiet
git diff --cached --quiet
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean" >&2
  exit 1
fi

export APP_VERSION
APP_VERSION=$(git rev-parse --short=12 HEAD)
COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" build api ocr-worker
"${COMPOSE[@]}" up -d postgres redis minio
"${COMPOSE[@]}" run --rm minio-init
"${COMPOSE[@]}" run --rm api python manage.py migrate --noinput
"${COMPOSE[@]}" run --rm ocr-worker python manage.py check_ocr \
  tests/ocr/fixtures/medicine_front.jpg
"${COMPOSE[@]}" up -d api worker ocr-worker beat

for _attempt in $(seq 1 24); do
  if "${COMPOSE[@]}" exec -T api python -c \
    "import urllib.request; request=urllib.request.Request('http://127.0.0.1:8000/api/v1/health', headers={'Host':'aipupu.cloud','X-Forwarded-Proto':'https'}); assert urllib.request.urlopen(request, timeout=3).status == 200"; then
    "${COMPOSE[@]}" --profile production up -d nginx
    "${COMPOSE[@]}" --profile production exec -T nginx nginx -t
    "${COMPOSE[@]}" --profile production exec -T nginx nginx -s reload
    exit 0
  fi
  sleep 5
done

echo "API health check failed" >&2
exit 1
