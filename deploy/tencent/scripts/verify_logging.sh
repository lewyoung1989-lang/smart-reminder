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

journal_setting_counts() {
  local config_file=$1
  local wanted_key=$2
  local wanted_value=$3
  local utf8_bom=$'\357\273\277'

  awk -v wanted_key="$wanted_key" -v wanted_value="$wanted_value" \
    -v utf8_bom="$utf8_bom" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function process_logical_line(line, equals_at, key, value) {
      line = trim(line)
      if (line == "" || line ~ /^[#;]/) {
        return
      }
      if (line ~ /^\[[^]]+\]$/) {
        current_section = substr(line, 2, length(line) - 2)
        return
      }
      if (current_section != "Journal") {
        return
      }

      equals_at = index(line, "=")
      if (equals_at == 0) {
        return
      }
      key = trim(substr(line, 1, equals_at - 1))
      value = trim(substr(line, equals_at + 1))
      if (key == wanted_key) {
        key_count++
        if (value == wanted_value) {
          value_count++
        }
      }
    }

    {
      sub(/\r$/, "")
      physical_line = $0
      if (NR == 1 && index(physical_line, utf8_bom) == 1) {
        physical_line = substr(physical_line, length(utf8_bom) + 1)
      }
      if (continuing && physical_line ~ /^[[:space:]]*[#;]/) {
        next
      }
      logical_line = logical_line physical_line
      if (logical_line ~ /\\$/) {
        sub(/\\$/, " ", logical_line)
        continuing = 1
        next
      }
      process_logical_line(logical_line)
      logical_line = ""
      continuing = 0
    }

    END {
      if (logical_line != "") {
        process_logical_line(logical_line)
      }
      printf "%d %d\n", key_count, value_count
    }
  ' "$config_file"
}

for setting in \
  Storage=persistent \
  Compress=yes \
  MaxRetentionSec=7day \
  SystemMaxUse=1G; do
  key=${setting%%=*}
  value=${setting#*=}
  read -r key_count value_count < <(
    journal_setting_counts "$JOURNAL_CONFIG" "$key" "$value"
  )
  if [[ "$key_count" -ne 1 || "$value_count" -ne 1 ]]; then
    printf 'journald 管理配置必须且只能包含一次 %s：%s\n' \
      "$setting" "$JOURNAL_CONFIG" >&2
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
    if [[ "$candidate_name" > "$CONFIG_NAME" ]]; then
      for key in Storage Compress MaxRetentionSec SystemMaxUse; do
        read -r key_count _ < <(
          journal_setting_counts "$candidate" "$key" ''
        )
        if [[ "$key_count" -gt 0 ]]; then
          printf '后序配置可能覆盖日志保留策略：%s\n' "$candidate" >&2
          exit 1
        fi
      done
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
