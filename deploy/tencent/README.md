# 腾讯云单机部署手册

本手册用于把智能生活提醒后端部署到腾讯云 Ubuntu 服务器。`https://aipupu.cloud` 提供 API，`https://files.aipupu.cloud` 提供药盒图片的短期签名上传。服务器运行 Django API、普通 Celery Worker、Celery Beat、独立 RapidOCR Worker、PostgreSQL、Redis、私有 MinIO 和 Nginx。

生产环境中禁止提交或打印服务器密码、SSH 私钥、Bearer Token、Django Secret、数据库密码和 DeepSeek Key。

## 1. 安全组与域名

腾讯云安全组只开放 `22/80/443`：

- `22/tcp` 仅允许管理员当前公网 IP，不能向全网开放。
- `80/tcp` 用于 Let's Encrypt 验证，并在正式配置中跳转 HTTPS。
- `443/tcp` 面向 App、健康检查和签名图片上传开放。
- 不开放 `5432`、`6379`、`8000`、`9000`、`9001`。

在域名控制台为 `aipupu.cloud` 和 `files.aipupu.cloud` 设置指向同一服务器的 A 记录。签发证书前执行：

```bash
getent ahostsv4 aipupu.cloud
getent ahostsv4 files.aipupu.cloud
```

解析结果必须是当前服务器；否则不要运行证书脚本。

## 2. SSH 公钥与登录加固

在开发机生成项目专用密钥：

```bash
ssh-keygen -t ed25519 -a 64 \
  -f ~/.ssh/id_ed25519_smart_reminder \
  -C smart-reminder-deploy
ssh-add ~/.ssh/id_ed25519_smart_reminder
```

为私钥设置口令。只显示 `.pub` 公钥并通过腾讯云控制台绑定到服务器，私钥不得上传：

```bash
cat ~/.ssh/id_ed25519_smart_reminder.pub
```

绑定后先验证新连接：

```bash
ssh -i ~/.ssh/id_ed25519_smart_reminder \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  ubuntu@aipupu.cloud true
```

验证成功后，在仍保持旧会话打开的情况下：

1. 在 `/etc/ssh/sshd_config.d/99-smart-reminder.conf` 设置 `PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`PubkeyAuthentication yes`、`PermitRootLogin no`。
2. 执行 `sudo sshd -t`，只有退出码为 `0` 才执行 `sudo systemctl reload ssh`。
3. 再开一个终端验证 SSH 公钥登录，成功后才关闭旧会话。
4. 执行 `sudo passwd ubuntu` 更换已经暴露的初始密码。

任何时候都不能在确认公钥登录成功前禁用密码登录。

## 3. 安装 Docker

使用 Docker 官方 Ubuntu 软件源：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
```

重新登录后检查：

```bash
docker version
docker compose version
```

必须使用 Docker Compose v2.24.4 或更高版本，因为生产覆盖文件使用 `!reset` 删除内部服务的宿主端口。

## 4. 目录与代码

```bash
sudo install -d -o ubuntu -g ubuntu -m 0755 /opt/smart-reminder/app
sudo install -d -o ubuntu -g ubuntu -m 0700 /opt/smart-reminder/shared
sudo install -d -o ubuntu -g ubuntu -m 0700 /opt/smart-reminder/backups/postgres

git clone https://github.com/lewyoung1989-lang/smart-reminder.git \
  /opt/smart-reminder/app
cd /opt/smart-reminder/app
git fetch origin
git checkout main
```

每次发布前记录并审核完整提交：

```bash
git pull --ff-only
DEPLOY_SHA=$(git rev-parse HEAD)
git status --short
```

`git status --short` 必须无输出。发布脚本接收上面的完整 SHA，不直接部署可移动的分支名称。

## 5. 生产环境文件

```bash
install -m 0600 deploy/tencent/env.production.example \
  /opt/smart-reminder/shared/.env.production
```

已有环境文件通过非回显脚本升级并补齐 DeepSeek、Certbot 和 MinIO 凭据：

```bash
./deploy/tencent/scripts/configure_secrets.sh \
  /opt/smart-reminder/shared/.env.production
```

脚本不会 `source` 环境文件，也不会把密钥放入命令参数。生产配置必须同时包含 `S3_INTERNAL_ENDPOINT=http://minio:9000` 和 `S3_PUBLIC_ENDPOINT=https://files.aipupu.cloud`；前者供 API/OCR Worker 内部读删，后者只用于生成 iPhone 上传签名。

检查权限和配置，不显示文件内容：

```bash
stat -c '%a %U %G %n' /opt/smart-reminder/shared/.env.production
python3 deploy/tencent/scripts/check_env.py \
  /opt/smart-reminder/shared/.env.production
```

权限必须为 `600`，所有者必须是部署用户。

## 6. 安装生产日志

首次发布前必须先初始化主机日志系统：

```bash
cd /opt/smart-reminder/app
sudo ./deploy/tencent/scripts/install_logging.sh
```

脚本配置持久化 journald、7 天保留和 1GB 上限，创建部署、备份、证书日志目录，并安装数据库备份和证书续期 timer。只有脚本完整成功后才能部署使用 `journald` 驱动的容器。

检查 timer 已启用：

```bash
systemctl list-timers \
  smart-reminder-postgres-backup.timer \
  smart-reminder-cert-renew.timer
```

## 7. 首次 TLS 与发布

确认域名已解析且安全组开放 80 后运行：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/bootstrap_tls.sh \
  /opt/smart-reminder/shared/.env.production
```

该脚本为两个域名申请同一张证书。HTTP 服务只响应 ACME 验证，其余路径返回 `503`，不会通过明文 HTTP 暴露 API 或对象上传。

发布脚本会强制重建 Nginx 容器，因为 Git 更新配置文件时可能替换单文件 bind mount 的宿主 inode；只执行 reload 不能保证容器读到新文件。重建后脚本仍会执行 `nginx -t`，成功才 reload。

证书签发成功后部署审核过的提交：

```bash
./deploy/tencent/scripts/deploy.sh \
  "$DEPLOY_SHA" \
  /opt/smart-reminder/shared/.env.production
```

验证：

```bash
export APP_VERSION
APP_VERSION=$(git rev-parse --short=12 HEAD)
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  config --quiet
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile production exec -T nginx nginx -t
curl --fail --show-error --silent \
  https://aipupu.cloud/api/v1/health
curl --head https://files.aipupu.cloud/
```

公网健康检查应返回：

```json
{"status":"ok","service":"smart-reminder-api"}
```

文件域名的匿名 `HEAD/GET` 必须被拒绝。MinIO Console 不配置公网域名，`9000/9001` 不得出现在宿主端口列表中。部署脚本会运行：

```bash
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  run --rm ocr-worker python manage.py check_ocr \
  tests/ocr/fixtures/medicine_front.jpg
```

输出只能包含识别行数和耗时，不能包含药名等 OCR 原文。

## 8. MinIO 与临时图片

`minio-init` 创建私有 `smart-reminder-private` 桶、独立应用用户和最小权限策略。Django/RapidOCR 不使用 MinIO root 凭据。药盒图片确认后立即异步删除；未确认或失败任务按 24 小时策略清理，bucket 的 1 天生命周期规则处理孤儿上传。

MinIO 数据不进入 PostgreSQL 备份，也不复制到 COS。服务中断期间无法精确计时删除，恢复后由 Celery 和 MinIO 生命周期继续执行。磁盘损坏导致临时图片丢失时，用户重拍或手动录入即可。

## 9. 证书续期

每月运行一次 Certbot 续期，并在续期后检查和重载 Nginx。生产日志安装脚本已启用 `smart-reminder-cert-renew.timer`，手工验证使用同一个脚本：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/renew_certificate.sh \
  /opt/smart-reminder/shared/.env.production
```

脚本先续期，再执行 `nginx -t`，校验成功后才重载 Nginx。输出同时进入 journal 和 `/opt/smart-reminder/logs/cert/`。首次上线后还要手动执行一次 `certbot renew --dry-run` 验证续期链路。

## 10. 数据库备份与恢复演练

手动备份：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/backup_postgres.sh \
  /opt/smart-reminder/shared/.env.production
```

`smart-reminder-postgres-backup.timer` 每天凌晨执行一次，并监控退出码和备份文件大小。检查最近状态：

```bash
systemctl status smart-reminder-postgres-backup.timer
systemctl status smart-reminder-postgres-backup.service
```

任务输出同时进入 journal 和 `/opt/smart-reminder/logs/backup/`。备份目录权限为 `700`，备份文件权限为 `600`，默认保留 14 天；这里的 14 天是数据库备份保留期，不是运行日志保留期。同机备份不能防止整机磁盘损坏，亲友内测前要把备份加密复制到私有 COS 或迁移 TencentDB。

恢复演练不得直接使用主数据库。复制生产环境文件到权限为 `600` 的临时文件，把 `POSTGRES_DB` 改为单独的恢复测试数据库，创建该数据库后运行：

```bash
./deploy/tencent/scripts/restore_postgres.sh \
  /opt/smart-reminder/shared/.env.restore-test \
  /opt/smart-reminder/backups/postgres/smart_reminder-YYYYmmddTHHMMSSZ.dump
```

脚本要求输入精确的 `RESTORE`，且只接受备份目录内部的普通文件。验证表和记录数量后删除临时数据库及临时环境文件；不要在未安排维护窗口和恢复点时对主数据库执行恢复。

## 11. 更新与回滚

更新：

```bash
cd /opt/smart-reminder/app
git fetch origin
git checkout main
git pull --ff-only
DEPLOY_SHA=$(git rev-parse HEAD)
./deploy/tencent/scripts/deploy.sh \
  "$DEPLOY_SHA" \
  /opt/smart-reminder/shared/.env.production
```

回滚应用版本：

1. 从发布记录选择上一个成功的完整提交 SHA。
2. `git checkout --detach` 到该提交。
3. 使用该完整 SHA 再次运行 `deploy.sh`。
4. 检查容器状态和公网健康检查。

不要自动回滚数据库卷。数据库迁移必须采用可向后兼容的扩展/切换/清理顺序；需要恢复数据库时先停止发布并使用明确的备份恢复方案。

## 12. 日志路径与查询

生产日志保留 7 天。运行日志和运维任务日志的存储方式不同：

| 日志类型 | 物理路径 | 推荐查询方式 |
|---|---|---|
| 容器、Django、Celery、Nginx | `/var/log/journal/` | `logs.sh` 或 `journalctl` |
| 应用发布 | `/opt/smart-reminder/logs/deploy/` | `tail`、`less` |
| PostgreSQL 备份 | `/opt/smart-reminder/logs/backup/` | `tail`、`less` |
| TLS 证书续期 | `/opt/smart-reminder/logs/cert/` | `tail`、`less` |

普通排查优先使用统一脚本：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/logs.sh api --since "2 hours ago"
./deploy/tencent/scripts/logs.sh worker --level error
./deploy/tencent/scripts/logs.sh ocr-worker --since today --follow
./deploy/tencent/scripts/logs.sh all --since "30 minutes ago"
```

脚本支持的服务名为 `api`、`worker`、`ocr-worker`、`beat`、`nginx`、`postgres`、`redis`、`minio` 和 `all`。服务器账户没有 journal 读取权限时，在命令前加 `sudo`。

`--level` 根据日志正文中的 `level=ERROR`、Celery `ERROR`、Nginx `[error]` 等标准级别标记过滤，不使用 Docker 按 stdout/stderr 推断的 journal priority。未包含常见级别标记的第三方服务行不会出现在级别过滤结果中；排查完整上下文时省略 `--level`。

直接查询和检查磁盘占用：

```bash
journalctl --disk-usage
journalctl CONTAINER_TAG=smart-reminder/api --since today \
  --output=short-iso-precise
systemd-analyze cat-config systemd/journald.conf
./deploy/tencent/scripts/verify_logging.sh
```

有效配置必须包含 `Storage=persistent`、`MaxRetentionSec=7day` 和 `SystemMaxUse=1G`。`verify_logging.sh` 还会拒绝排序在项目配置之后且会覆盖这些值的 drop-in。journald 的限制同时作用于本项目容器日志和操作系统日志。

查看纯文本运维日志及权限：

```bash
tail -n 200 /opt/smart-reminder/logs/deploy/deploy.log
tail -n 200 /opt/smart-reminder/logs/backup/backup.log
tail -n 200 /opt/smart-reminder/logs/cert/cert.log
find /opt/smart-reminder/logs -maxdepth 2 -type d \
  -exec stat -c '%a %U %G %n' {} \;
```

三个子目录必须是 `0750 ubuntu ubuntu`，日志文件必须是 `0640`。logrotate 每日压缩并删除超过 7 天的运维日志。

Nginx 响应和上下游日志共用请求 ID。排查单次请求时，从响应头取得 `X-Request-ID`，再在 Nginx 和 API 日志中搜索。访问日志只包含 `$uri`，不得出现查询参数、Authorization、Bearer Token、DeepSeek Key、提醒原文、OCR 原文或图片签名 URL。抽查命令：

```bash
./deploy/tencent/scripts/logs.sh all --since today \
  | grep -Ei 'authorization|bearer|api[_-]?key|x-amz-signature'
```

正常情况下该命令应无输出；若发现敏感内容，先限制日志访问并停止相关新增日志，再修正记录点。

## 13. 重启与故障排查

服务器重启后检查：

```bash
cd /opt/smart-reminder/app
export APP_VERSION
APP_VERSION=$(git rev-parse --short=12 HEAD)
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile production ps
curl --fail --show-error --silent \
  https://aipupu.cloud/api/v1/health
```

常用排查命令：

```bash
./deploy/tencent/scripts/logs.sh all --since "30 minutes ago"
df -h
free -h
```

日志不得包含环境文件内容、Token、完整用户输入或模型响应。构建失败时保持现有容器运行；迁移失败时不要启动新 API；磁盘不足时先列出镜像和备份，禁止删除 PostgreSQL 卷。

OCR Worker 内存不足时先停止 `ocr-worker`，核心提醒 API 可继续运行；不要临时提高并发或移除 `1.2 GB` 内存上限。

## 14. iPhone 验收

使用以下生产地址构建测试 App：

```bash
--dart-define=API_BASE_URL=https://aipupu.cloud
```

在 iPhone 上完成以下流程：

1. 创建一条文字提醒草稿、确认并验证本地通知。
2. 拍摄药盒正面和有效期区域，确认上传地址 host 为 `files.aipupu.cloud`。
3. 等待 OCR 候选，修改错误字段后人工确认。
4. 确认前药箱不得新增库存；确认后新增库存，并验证两张临时图片已删除。

生产环境不再使用 Mac 局域网 HTTP 地址。
