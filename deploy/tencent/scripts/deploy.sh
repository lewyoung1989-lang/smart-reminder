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
OLD_FUNASR_IMAGE_ID=""
OLD_FUNASR_CONTAINER_ID=$("${COMPOSE[@]}" ps -q funasr)
if [[ -n "$OLD_FUNASR_CONTAINER_ID" ]]; then
  OLD_FUNASR_IMAGE_ID=$(docker inspect --format '{{.Image}}' \
    "$OLD_FUNASR_CONTAINER_ID")
fi

API_REPLACED=false
FUNASR_DISRUPTED=false
DEPLOY_ROLLBACK_ACTIVE=false

rollback_api() {
  if [[ -z "$OLD_API_IMAGE_ID" ]]; then
    echo "No previous API image is available for rollback" >&2
    return 1
  fi

  echo "Restoring previous API image" >&2
  if ! docker tag "$OLD_API_IMAGE_ID" "smart-reminder-api:$APP_VERSION"; then
    echo "API rollback image retag failed" >&2
    return 1
  fi
  if ! "${COMPOSE[@]}" up -d --no-deps --force-recreate api worker; then
    echo "API rollback container restore failed" >&2
    return 1
  fi

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

rollback_funasr() {
  if [[ -z "$OLD_FUNASR_IMAGE_ID" ]]; then
    echo "FunASR rollback skipped; no previous FunASR image is available" >&2
    return 1
  fi

  echo "Restoring previous FunASR image" >&2
  if ! docker tag "$OLD_FUNASR_IMAGE_ID" "smart-reminder-funasr:$APP_VERSION"; then
    echo "FunASR rollback image retag failed" >&2
    return 1
  fi
  if ! "${COMPOSE[@]}" up -d --no-deps --force-recreate funasr; then
    echo "FunASR rollback container restore failed" >&2
    return 1
  fi

  for _attempt in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T funasr python -c \
      "import urllib.request; assert urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200"; then
      return 0
    fi
    sleep 5
  done

  echo "FunASR rollback health check failed" >&2
  return 1
}

handle_deploy_failure() {
  local failure_status=${1:-1}
  trap - ERR
  if [[ "$DEPLOY_ROLLBACK_ACTIVE" == "true" ]]; then
    exit "$failure_status"
  fi

  DEPLOY_ROLLBACK_ACTIVE=true
  set +e
  echo "Deployment failed; starting rollback" >&2
  if [[ "$FUNASR_DISRUPTED" == "true" ]]; then
    rollback_funasr || true
  fi
  if [[ "$API_REPLACED" == "true" ]]; then
    rollback_api || true
  fi
  exit "$failure_status"
}

trap 'handle_deploy_failure $?' ERR

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
  FUNASR_DISRUPTED=true
  "${COMPOSE[@]}" stop funasr
  "${COMPOSE[@]}" run --rm --no-deps funasr-model-init
fi
FUNASR_DISRUPTED=true
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
  false
fi

"${COMPOSE[@]}" exec -T funasr \
  python /srv/funasr/smoke/smoke_transcription.py \
  http://funasr:8000 \
  /srv/funasr/smoke/fixtures/mandarin_reminder.wav

"${COMPOSE[@]}" run --rm --no-deps api \
  python manage.py check_release_dependencies
"${COMPOSE[@]}" run --rm --no-deps api python manage.py migrate --noinput
API_REPLACED=true
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
    trap - ERR
    echo "Deployment completed; rollback trap cleared"
    exit 0
  fi
  sleep 5
done

echo "API health check failed" >&2
false
