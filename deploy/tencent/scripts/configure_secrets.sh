#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
if [[ $# -ne 1 ]]; then
  echo "usage: configure_secrets.sh ENV_FILE" >&2
  exit 2
fi
ENV_FILE=$1
if [[ ! -f "$ENV_FILE" ]]; then
  echo "environment file does not exist" >&2
  exit 2
fi
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

get_value() {
  local wanted=$1 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$wanted="*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done < "$ENV_FILE"
}

replace_value() {
  local wanted=$1 replacement=$2 temp line found=false
  temp=$(mktemp "${ENV_FILE}.XXXXXX")
  chmod 600 "$temp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$wanted="*) printf '%s=%s\n' "$wanted" "$replacement"; found=true ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$ENV_FILE" > "$temp"
  if [[ "$found" == false ]]; then
    printf '%s=%s\n' "$wanted" "$replacement" >> "$temp"
  fi
  mv "$temp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

ensure_value() {
  local key=$1 value=$2
  if [[ -z "$(get_value "$key")" ]]; then
    replace_value "$key" "$value"
  fi
}

ensure_value FILES_DOMAIN files.aipupu.cloud
ensure_value OCR_ENABLED false
ensure_value ASR_PROVIDER funasr
ensure_value ASR_BASE_URL http://funasr:8000
ensure_value ASR_MODEL paraformer-zh
ensure_value ASR_TIMEOUT_SECONDS 20
ensure_value ASR_MAX_AUDIO_BYTES 4194304
ensure_value ASR_MAX_REQUEST_BYTES 5242880
ensure_value ASR_MIN_DURATION_SECONDS 0.3
ensure_value ASR_MAX_DURATION_SECONDS 20
ensure_value ASR_GLOBAL_CONCURRENCY 1
ensure_value ASR_CONCURRENCY_PER_USER 1
ensure_value ASR_LEASE_TTL_SECONDS 25
ensure_value ASR_USER_RATE 10/min
ensure_value ASR_IP_RATE 30/min
ensure_value ASR_REDIS_URL redis://redis:6379/0
ensure_value ASR_THROTTLE_REDIS_URL redis://redis:6379/2
ensure_value ASR_TRUSTED_PROXY_IPS 172.29.0.10
ensure_value OCR_PROVIDER rapidocr
ensure_value OCR_STORAGE_PROVIDER s3
ensure_value OCR_JOB_RETENTION_HOURS 24
ensure_value OCR_QUEUE ocr
ensure_value S3_INTERNAL_ENDPOINT http://minio:9000
ensure_value S3_PUBLIC_ENDPOINT https://files.aipupu.cloud
ensure_value S3_BUCKET smart-reminder-private
ensure_value S3_REGION us-east-1
ensure_value S3_ADDRESSING_STYLE path

if [[ -z "$(get_value DEEPSEEK_API_KEY)" ]]; then
  printf 'DeepSeek API key: ' >&2
  IFS= read -r -s deepseek_key
  printf '\n' >&2
  replace_value DEEPSEEK_API_KEY "$deepseek_key"
  unset deepseek_key
fi
if [[ -z "$(get_value CERTBOT_EMAIL)" ]]; then
  printf 'Certbot email: ' >&2
  IFS= read -r certbot_email
  replace_value CERTBOT_EMAIL "$certbot_email"
  unset certbot_email
fi
if [[ "$(get_value OCR_ENABLED)" == "true" ]]; then
  if [[ -z "$(get_value MINIO_ROOT_USER)" ]]; then
    replace_value MINIO_ROOT_USER "minio-root-$(openssl rand -hex 4)"
  fi
  if [[ -z "$(get_value MINIO_ROOT_PASSWORD)" ]]; then
    replace_value MINIO_ROOT_PASSWORD "$(openssl rand -hex 32)"
  fi
  if [[ -z "$(get_value S3_ACCESS_KEY_ID)" ]]; then
    replace_value S3_ACCESS_KEY_ID "sr-app-$(openssl rand -hex 4)"
  fi
  if [[ -z "$(get_value S3_SECRET_ACCESS_KEY)" ]]; then
    replace_value S3_SECRET_ACCESS_KEY "$(openssl rand -hex 32)"
  fi
fi

python3 "$VALIDATOR" "$ENV_FILE" >/dev/null
echo "Production secrets configured and validated"
