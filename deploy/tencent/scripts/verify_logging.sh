#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

SYSTEM_ROOT=${SMART_REMINDER_SYSTEM_ROOT:-}
LOG_ROOT=${SMART_REMINDER_LOG_ROOT:-/opt/smart-reminder/logs}
CONFIG_NAME=50-smart-reminder.conf

system_path() {
  printf '%s%s' "$SYSTEM_ROOT" "$1"
}

JOURNAL_CONFIG=$(system_path "/etc/systemd/journald.conf.d/$CONFIG_NAME")
if [[ ! -r "$JOURNAL_CONFIG" ]]; then
  printf 'journald 配置不存在或不可读：%s\n' "$JOURNAL_CONFIG" >&2
  exit 1
fi

for setting in \
  Storage=persistent \
  Compress=yes \
  MaxRetentionSec=7day \
  SystemMaxUse=1G; do
  if ! grep -Fxq "$setting" "$JOURNAL_CONFIG"; then
    printf 'journald 配置缺少：%s\n' "$setting" >&2
    exit 1
  fi
done

shopt -s nullglob
for relative_directory in \
  /usr/lib/systemd/journald.conf.d \
  /usr/local/lib/systemd/journald.conf.d \
  /run/systemd/journald.conf.d \
  /etc/systemd/journald.conf.d; do
  directory=$(system_path "$relative_directory")
  for candidate in "$directory"/*.conf; do
    candidate_name=${candidate##*/}
    if [[ "$candidate_name" > "$CONFIG_NAME" ]] && \
      grep -Eq \
        '^[[:space:]]*(Storage|Compress|MaxRetentionSec|SystemMaxUse)=' \
        "$candidate"; then
      printf '后序配置可能覆盖日志保留策略：%s\n' "$candidate" >&2
      exit 1
    fi
  done
done

if ! systemctl is-active --quiet systemd-journald; then
  printf '%s\n' 'systemd-journald 未运行' >&2
  exit 1
fi
if [[ ! -d "$(system_path /var/log/journal)" ]]; then
  printf '%s\n' 'journald 持久化目录不存在' >&2
  exit 1
fi

for category in deploy backup cert; do
  if [[ ! -d "$LOG_ROOT/$category" || ! -w "$LOG_ROOT/$category" ]]; then
    printf '运维日志目录不存在或不可写：%s\n' "$LOG_ROOT/$category" >&2
    exit 1
  fi
done

DOCKER_LOG_PLUGINS=$(docker info --format '{{json .Plugins.Log}}')
if [[ "$DOCKER_LOG_PLUGINS" != *'"journald"'* ]]; then
  printf '%s\n' 'Docker 不支持 journald 日志驱动' >&2
  exit 1
fi

printf '%s\n' '生产日志前置校验通过'
