#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  printf '%s\n' '请使用 sudo 或 root 运行 install_logging.sh' >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
INSTALL_ROOT=/opt/smart-reminder
DEPLOY_USER=ubuntu
JOURNAL_CONFIG="$ROOT_DIR/deploy/tencent/logging/50-smart-reminder.conf"
LOGROTATE_CONFIG="$ROOT_DIR/deploy/tencent/logging/smart-reminder.logrotate"

if [[ ! -d "$INSTALL_ROOT/app" ]]; then
  printf '项目目录不存在：%s\n' "$INSTALL_ROOT/app" >&2
  exit 1
fi
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  printf '部署用户不存在：%s\n' "$DEPLOY_USER" >&2
  exit 1
fi

for directory in logs/deploy logs/backup logs/cert; do
  install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0750 \
    "$INSTALL_ROOT/$directory"
done

install -d -m 0755 /etc/systemd/journald.conf.d
install -m 0644 "$JOURNAL_CONFIG" \
  /etc/systemd/journald.conf.d/50-smart-reminder.conf
install -m 0644 "$LOGROTATE_CONFIG" \
  /etc/logrotate.d/smart-reminder

install -d -m 2755 /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald
journalctl --flush

EFFECTIVE_CONFIG=$(systemd-analyze cat-config systemd/journald.conf)
for setting in \
  Storage=persistent \
  Compress=yes \
  MaxRetentionSec=7day \
  SystemMaxUse=1G; do
  if [[ "$EFFECTIVE_CONFIG" != *"$setting"* ]]; then
    printf 'journald 配置未生效：%s\n' "$setting" >&2
    exit 1
  fi
done

logrotate --debug /etc/logrotate.d/smart-reminder >/dev/null

printf '%s\n' '日志系统安装完成：'
printf '  运行日志：%s\n' /var/log/journal/
printf '  部署日志：%s\n' "$INSTALL_ROOT/logs/deploy/"
printf '  备份日志：%s\n' "$INSTALL_ROOT/logs/backup/"
printf '  证书日志：%s\n' "$INSTALL_ROOT/logs/cert/"
journalctl --disk-usage
