#!/usr/bin/env bash
set -Eeuo pipefail

: "${S3_INTERNAL_ENDPOINT:?S3_INTERNAL_ENDPOINT is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"

mc alias set private "$S3_INTERNAL_ENDPOINT" \
  "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "private/$S3_BUCKET"
mc anonymous set none "private/$S3_BUCKET"
if ! mc admin user info private "$S3_ACCESS_KEY_ID" >/dev/null 2>&1; then
  mc admin user add private "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY"
fi
mc admin policy create private smart-reminder-ocr /config/app-policy.json
mc admin policy attach private smart-reminder-ocr \
  --user "$S3_ACCESS_KEY_ID"

if ! mc ilm rule ls --json "private/$S3_BUCKET" | grep -Fq 'ocr/tmp/'; then
  mc ilm rule add --expire-days 1 --prefix 'ocr/tmp/' \
    "private/$S3_BUCKET"
fi
