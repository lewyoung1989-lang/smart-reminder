#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
COMMON_DIR=$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir)
case "$COMMON_DIR" in
  /*) ;;
  *) COMMON_DIR="$PROJECT_ROOT/$COMMON_DIR" ;;
esac
COMMON_ROOT=$(CDPATH= cd -- "$COMMON_DIR/.." && pwd)
PYTHON="$COMMON_ROOT/.venv-funasr/bin/python"
MODEL_CACHE="$COMMON_ROOT/.models/funasr"

if [ ! -x "$PYTHON" ]; then
  echo "未找到本机 FunASR 环境：$PYTHON" >&2
  exit 1
fi

export MODELSCOPE_CACHE="$MODEL_CACHE"
export PYTHONPATH="$PROJECT_ROOT/services/funasr"
exec "$PYTHON" -m uvicorn app.main:app \
  --host 127.0.0.1 \
  --port "${FUNASR_LOCAL_PORT:-18001}" \
  --no-access-log
