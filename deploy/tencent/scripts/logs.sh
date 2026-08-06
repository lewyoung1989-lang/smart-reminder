#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
用法：logs.sh SERVICE [--since TIME] [--level LEVEL] [--follow]

SERVICE 可选：api、worker、ocr-worker、beat、nginx、postgres、redis、minio、all
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

SERVICE=$1
shift

case "$SERVICE" in
  api|worker|ocr-worker|beat|nginx|postgres|redis|minio)
    TAGS=("CONTAINER_TAG=smart-reminder/$SERVICE")
    ;;
  all)
    TAGS=(
      "CONTAINER_TAG=smart-reminder/api"
      "CONTAINER_TAG=smart-reminder/worker"
      "CONTAINER_TAG=smart-reminder/ocr-worker"
      "CONTAINER_TAG=smart-reminder/beat"
      "CONTAINER_TAG=smart-reminder/nginx"
      "CONTAINER_TAG=smart-reminder/postgres"
      "CONTAINER_TAG=smart-reminder/redis"
      "CONTAINER_TAG=smart-reminder/minio"
    )
    ;;
  *)
    printf '未知服务：%s\n' "$SERVICE" >&2
    usage
    exit 2
    ;;
esac

OPTIONS=("--output=short-iso-precise" "--no-pager")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      if [[ $# -lt 2 ]]; then
        printf '%s\n' '--since 缺少时间参数' >&2
        exit 2
      fi
      OPTIONS+=("--since" "$2")
      shift 2
      ;;
    --level)
      if [[ $# -lt 2 ]]; then
        printf '%s\n' '--level 缺少级别参数' >&2
        exit 2
      fi
      case "$2" in
        critical|CRITICAL|Critical)
          LEVEL_PATTERN='level=CRITICAL|(^|[^A-Z])CRITICAL([^A-Z]|$)|\[crit\]'
          ;;
        error|ERROR|Error)
          LEVEL_PATTERN='level=(ERROR|CRITICAL)|(^|[^A-Z])(ERROR|CRITICAL)([^A-Z]|$)|\[(error|crit)\]|Traceback'
          ;;
        warning|WARNING|Warning|warn|WARN|Warn)
          LEVEL_PATTERN='level=(WARNING|ERROR|CRITICAL)|(^|[^A-Z])(WARNING|WARN|ERROR|CRITICAL)([^A-Z]|$)|\[(warn|error|crit)\]|Traceback'
          ;;
        info|INFO|Info)
          LEVEL_PATTERN='level=(INFO|WARNING|ERROR|CRITICAL)|(^|[^A-Z])(INFO|WARNING|WARN|ERROR|CRITICAL)([^A-Z]|$)|\[(info|warn|error|crit)\]|Traceback'
          ;;
        debug|DEBUG|Debug)
          LEVEL_PATTERN='level=(DEBUG|INFO|WARNING|ERROR|CRITICAL)|(^|[^A-Z])(DEBUG|INFO|WARNING|WARN|ERROR|CRITICAL)([^A-Z]|$)|\[(debug|info|warn|error|crit)\]|Traceback'
          ;;
        *)
          printf '不支持的日志级别：%s\n' "$2" >&2
          exit 2
          ;;
      esac
      OPTIONS+=("--grep" "$LEVEL_PATTERN" "--case-sensitive=no")
      shift 2
      ;;
    --follow)
      OPTIONS+=("--follow")
      shift
      ;;
    *)
      printf '未知参数：%s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

exec journalctl "${TAGS[@]}" "${OPTIONS[@]}"
