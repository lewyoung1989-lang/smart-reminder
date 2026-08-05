#!/usr/bin/env bash

finish_operation_log() {
  local status=$?
  trap - EXIT

  if declare -F operation_cleanup >/dev/null; then
    if operation_cleanup; then
      :
    else
      local cleanup_status=$?
      if [[ $status -eq 0 ]]; then
        status=$cleanup_status
      fi
    fi
  fi

  if [[ ${OPERATION_LOG_ACTIVE:-0} -eq 1 ]]; then
    printf '操作结束：时间=%s 状态=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status"
  fi

  exec 1>&3 2>&4
  if ! wait "$OPERATION_LOG_TEE_PID" && [[ $status -eq 0 ]]; then
    status=1
  fi
  exec 3>&- 4>&-
  rm -f -- "$OPERATION_LOG_PIPE"
  exit "$status"
}

start_operation_log() {
  local category=${1:?缺少日志类别}
  case "$category" in
    deploy|backup|cert) ;;
    *)
      printf '不支持的日志类别：%s\n' "$category" >&2
      return 2
      ;;
  esac

  local log_root=${SMART_REMINDER_LOG_ROOT:-/opt/smart-reminder/logs}
  local log_directory="$log_root/$category"
  if [[ ! -d "$log_directory" || ! -w "$log_directory" ]]; then
    printf '日志目录不存在或不可写：%s\n' "$log_directory" >&2
    return 1
  fi

  umask 027
  OPERATION_LOG_FILE="$log_directory/$category-$(date -u +%Y-%m-%d).log"
  touch "$OPERATION_LOG_FILE"
  chmod 0640 "$OPERATION_LOG_FILE"
  OPERATION_LOG_PIPE="$log_directory/.operation-$category-$$-$RANDOM.pipe"
  mkfifo -m 0600 "$OPERATION_LOG_PIPE"
  OPERATION_LOG_ACTIVE=1
  export OPERATION_LOG_FILE OPERATION_LOG_PIPE OPERATION_LOG_ACTIVE

  exec 3>&1 4>&2
  tee -a "$OPERATION_LOG_FILE" <"$OPERATION_LOG_PIPE" >&3 &
  OPERATION_LOG_TEE_PID=$!
  export OPERATION_LOG_TEE_PID
  exec >"$OPERATION_LOG_PIPE" 2>&1
  trap finish_operation_log EXIT
  printf '操作开始：时间=%s 类别=%s 进程=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" "$$"
}
