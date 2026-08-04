# 腾讯云单机部署手册

本手册用于把智能生活提醒后端部署到腾讯云 Ubuntu 服务器，并通过 `https://aipupu.cloud` 提供 API。首期运行 Django API、普通 Celery Worker、Celery Beat、PostgreSQL、Redis 和 Nginx；OCR 由独立分支完成后再接入。

生产环境中禁止提交或打印服务器密码、SSH 私钥、Bearer Token、Django Secret、数据库密码和 DeepSeek Key。

## 1. 安全组与域名

腾讯云安全组只开放 `22/80/443`：

- `22/tcp` 仅允许管理员当前公网 IP，不能向全网开放。
- `80/tcp` 用于 Let's Encrypt 验证，并在正式配置中跳转 HTTPS。
- `443/tcp` 面向 App 和健康检查开放。
- 不开放 `5432`、`6379`、`8000`、`9000`、`9001`。

在域名控制台为 `aipupu.cloud` 设置 A 记录。签发证书前执行：

```bash
getent ahostsv4 aipupu.cloud
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
git checkout feature/tencent-single-server-deployment
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

使用终端编辑器填写空值。`DJANGO_SECRET_KEY` 和数据库密码使用密码生成器或 `openssl rand -hex 32` 单独生成；DeepSeek Key 使用供应商控制台提供的生产专用值；`CERTBOT_EMAIL` 填写证书到期通知邮箱。

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

该脚本的 HTTP 服务只响应 ACME 验证，其余路径返回 `503`，不会通过明文 HTTP 暴露 API。

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
```

公网健康检查应返回：

```json
{"status":"ok","service":"smart-reminder-api"}
```

## 7. 证书续期

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

## 8. 数据库备份与恢复演练

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

## 9. 更新与回滚

更新：

```bash
cd /opt/smart-reminder/app
git fetch origin
git checkout feature/tencent-single-server-deployment
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

## 10. 重启与故障排查

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
  --profile production logs --tail 200 api worker beat nginx
df -h
free -h
```

日志不得包含环境文件内容、Token、完整用户输入或模型响应。构建失败时保持现有容器运行；迁移失败时不要启动新 API；磁盘不足时先列出镜像和备份，禁止删除 PostgreSQL 卷。

## 11. iPhone 验收

使用以下生产地址构建测试 App：

```bash
--dart-define=API_BASE_URL=https://aipupu.cloud
```

在 iPhone 上创建一条文字提醒草稿、确认创建并验证本地通知。生产环境不再使用 Mac 局域网 HTTP 地址。
