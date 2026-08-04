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
git checkout feature/tencent-ocr-minio-integration
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

## 6. 首次 TLS 与发布

确认域名已解析且安全组开放 80 后运行：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/bootstrap_tls.sh \
  /opt/smart-reminder/shared/.env.production
```

该脚本为两个域名申请同一张证书。HTTP 服务只响应 ACME 验证，其余路径返回 `503`，不会通过明文 HTTP 暴露 API 或对象上传。

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

## 7. MinIO 与临时图片

`minio-init` 创建私有 `smart-reminder-private` 桶、独立应用用户和最小权限策略。Django/RapidOCR 不使用 MinIO root 凭据。药盒图片确认后立即异步删除；未确认或失败任务按 24 小时策略清理，bucket 的 1 天生命周期规则处理孤儿上传。

MinIO 数据不进入 PostgreSQL 备份，也不复制到 COS。服务中断期间无法精确计时删除，恢复后由 Celery 和 MinIO 生命周期继续执行。磁盘损坏导致临时图片丢失时，用户重拍或手动录入即可。

## 8. 证书续期

每月运行一次 Certbot 续期，并在续期后检查和重载 Nginx：

```bash
cd /opt/smart-reminder/app
export APP_VERSION=operations
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile certbot run --rm certbot renew \
  --webroot --webroot-path /var/www/certbot
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile production exec -T nginx nginx -t
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile production exec -T nginx nginx -s reload
```

使用 systemd timer 或 rootless cron 定时执行，并监控证书到期日。先手动执行 `certbot renew --dry-run` 验证续期链路。

## 9. 数据库备份与恢复演练

手动备份：

```bash
cd /opt/smart-reminder/app
./deploy/tencent/scripts/backup_postgres.sh \
  /opt/smart-reminder/shared/.env.production
```

每天凌晨执行一次，并监控退出码和备份文件大小：

```cron
0 3 * * * cd /opt/smart-reminder/app && ./deploy/tencent/scripts/backup_postgres.sh /opt/smart-reminder/shared/.env.production >>/opt/smart-reminder/backups/postgres/backup.log 2>&1
```

备份目录权限为 `700`，备份文件权限为 `600`，默认保留 14 天。同机备份不能防止整机磁盘损坏，亲友内测前要把备份加密复制到私有 COS 或迁移 TencentDB。

恢复演练不得直接使用主数据库。复制生产环境文件到权限为 `600` 的临时文件，把 `POSTGRES_DB` 改为单独的恢复测试数据库，创建该数据库后运行：

```bash
./deploy/tencent/scripts/restore_postgres.sh \
  /opt/smart-reminder/shared/.env.restore-test \
  /opt/smart-reminder/backups/postgres/smart_reminder-YYYYmmddTHHMMSSZ.dump
```

脚本要求输入精确的 `RESTORE`，且只接受备份目录内部的普通文件。验证表和记录数量后删除临时数据库及临时环境文件；不要在未安排维护窗口和恢复点时对主数据库执行恢复。

## 10. 更新与回滚

更新：

```bash
cd /opt/smart-reminder/app
git fetch origin
git checkout feature/tencent-ocr-minio-integration
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

## 11. 重启与故障排查

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
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml \
  -f deploy/tencent/compose.production.yaml \
  --profile production logs --tail 200 api worker ocr-worker beat minio nginx
df -h
free -h
```

日志不得包含环境文件内容、Token、完整用户输入或模型响应。构建失败时保持现有容器运行；迁移失败时不要启动新 API；磁盘不足时先列出镜像和备份，禁止删除 PostgreSQL 卷。

OCR Worker 内存不足时先停止 `ocr-worker`，核心提醒 API 可继续运行；不要临时提高并发或移除 `1.2 GB` 内存上限。

## 12. iPhone 验收

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
