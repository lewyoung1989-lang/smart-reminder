#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
EXPECTED_SHA=${1:?usage: deploy.sh EXPECTED_SHA ENV_FILE}
ENV_FILE=${2:?usage: deploy.sh EXPECTED_SHA ENV_FILE}

source "$ROOT_DIR/deploy/tencent/scripts/operation_logging.sh"
start_operation_log deploy

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

printf '准备部署提交：%s\n' "$ACTUAL_SHA"

"$ROOT_DIR/deploy/tencent/scripts/verify_logging.sh"

export APP_VERSION
APP_VERSION=$(git rev-parse --short=12 HEAD)
OCR_ENABLED=$(python3 deploy/tencent/scripts/check_env.py "$ENV_FILE" \
  --get OCR_ENABLED)
COMPOSE=(
  docker compose
  --project-directory "$ROOT_DIR"
  --env-file "$ENV_FILE"
  -f "$ROOT_DIR/compose.yaml"
  -f "$ROOT_DIR/deploy/tencent/compose.production.yaml"
)

"${COMPOSE[@]}" config --quiet

OLD_API_IMAGE_ID=""
OLD_API_CONTAINER_ID=$("${COMPOSE[@]}" ps -q api)
if [[ -n "$OLD_API_CONTAINER_ID" ]]; then
  OLD_API_IMAGE_ID=$(docker inspect --format '{{.Image}}' \
    "$OLD_API_CONTAINER_ID")
fi

rollback_api() {
  if [[ -z "$OLD_API_IMAGE_ID" ]]; then
    echo "API health check failed; no previous API image is available" >&2
    return 1
  fi

  echo "API health check failed; restoring previous API image" >&2
  docker tag "$OLD_API_IMAGE_ID" "smart-reminder-api:$APP_VERSION"
  "${COMPOSE[@]}" up -d --no-deps --force-recreate api worker

  for _attempt in $(seq 1 24); do
    if "${COMPOSE[@]}" exec -T api python -c \
      "import urllib.request; request=urllib.request.Request('http://127.0.0.1:8000/api/v1/health', headers={'Host':'aipupu.cloud','X-Forwarded-Proto':'https'}); assert urllib.request.urlopen(request, timeout=3).status == 200"; then
      return 0
    fi
    sleep 5
  done

  echo "API rollback health check failed" >&2
  return 1
}

"${COMPOSE[@]}" build api funasr
if [[ "$OCR_ENABLED" == "true" ]]; then
  "${COMPOSE[@]}" --profile ocr build ocr-worker
fi

"${COMPOSE[@]}" up -d postgres redis
if [[ "$OCR_ENABLED" == "false" ]]; then
  "${COMPOSE[@]}" --profile ocr stop ocr-worker minio beat
fi

if "${COMPOSE[@]}" run --rm --no-deps funasr-model-init \
  python -m app.download_models --check; then
  echo "FunASR model cache is ready"
else
  "${COMPOSE[@]}" stop funasr
  "${COMPOSE[@]}" run --rm --no-deps funasr-model-init
fi
"${COMPOSE[@]}" up -d --no-deps funasr

funasr_ready=false
for _attempt in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T funasr python -c \
    "import urllib.request; assert urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200"; then
    funasr_ready=true
    break
  fi
  sleep 5
done
if [[ "$funasr_ready" != "true" ]]; then
  echo "FunASR health check failed" >&2
  exit 1
fi

"${COMPOSE[@]}" exec -T funasr \
  python /srv/funasr/smoke/smoke_transcription.py \
  http://funasr:8000 \
  /srv/funasr/smoke/fixtures/mandarin_reminder.wav

"${COMPOSE[@]}" run --rm --no-deps api \
  python manage.py check_release_dependencies
"${COMPOSE[@]}" run --rm --no-deps api python manage.py migrate --noinput
"${COMPOSE[@]}" up -d --no-deps api worker

if [[ "$OCR_ENABLED" == "true" ]]; then
  "${COMPOSE[@]}" --profile ocr up -d minio
  "${COMPOSE[@]}" --profile ocr run --rm minio-init
  "${COMPOSE[@]}" --profile ocr run --rm --no-deps ocr-worker \
    python manage.py check_ocr tests/ocr/fixtures/medicine_front.jpg
  "${COMPOSE[@]}" --profile ocr up -d --no-deps ocr-worker beat
fi

"${COMPOSE[@]}" --profile production run --rm --no-deps nginx-check nginx -t

for _attempt in $(seq 1 24); do
  if "${COMPOSE[@]}" exec -T api python -c \
    "import urllib.request; request=urllib.request.Request('http://127.0.0.1:8000/api/v1/health', headers={'Host':'aipupu.cloud','X-Forwarded-Proto':'https'}); assert urllib.request.urlopen(request, timeout=3).status == 200"; then
    "${COMPOSE[@]}" --profile production up -d --force-recreate nginx
    "${COMPOSE[@]}" --profile production exec -T nginx nginx -t
    "${COMPOSE[@]}" --profile production exec -T nginx nginx -s reload
    exit 0
  fi
  sleep 5
done

rollback_api || true
exit 1
