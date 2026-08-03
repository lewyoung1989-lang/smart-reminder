# 智能生活提醒

面向个人与家庭的智能提醒 App。当前开发阶段完成 Django 基础、确定性语音解析、语音提醒草稿和人工确认闭环。

## 本地后端

```bash
make install
.venv/bin/python backend/manage.py migrate
make test-backend
make run-backend
```

健康检查：`http://127.0.0.1:8000/api/v1/health`

## iPhone 联调

1. Mac 与 iPhone 连接同一个局域网。
2. 执行 `ipconfig getifaddr en0` 查询 Mac 的局域网 IP。
3. 复制 `.env.example` 为 `.env`，把该 IP 加入 `DJANGO_ALLOWED_HOSTS`。
4. Flutter Debug 配置的 API 地址使用 `http://<MAC_LAN_IP>:8000`，不能使用 `localhost`。
5. iOS 只在 Debug 配置中为这个局域网地址设置 HTTP 例外；TestFlight 和生产环境必须使用 HTTPS。

## Docker Compose

安装 Docker Desktop 后运行：

```bash
cp .env.example .env
docker compose config
docker compose up --build
```

服务包括 PostgreSQL、Redis、MinIO、Django API、Celery Worker 和 Celery Beat。MinIO 控制台位于 `http://127.0.0.1:9001`。

## Flutter

当前开发机的 Flutter SDK 安装在项目忽略的 `.tools/flutter`。通过包装命令运行：

```bash
scripts/flutterw pub get
make flutter-analyze
make flutter-test
make flutter-build-ios
```

iOS Runner 工程位于 `app/ios`，当前 Bundle ID 为 `com.liuyang.smartreminder.smartReminderApp`，已配置现有 Apple 开发团队、麦克风用途和本地网络用途。AlarmKit entitlement 在闹钟迭代接入。

## 当前 API

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/v1/health` | 服务健康检查 |
| POST | `/api/v1/voice/reminder-drafts` | 解析转写并创建短期草稿 |
| POST | `/api/v1/voice/reminder-drafts/{id}/confirm` | 人工确认并创建正式提醒 |

语音接口支持 Django 会话认证和移动端 `Authorization: Bearer <token>`。登录与令牌签发、阿里云语音令牌、DeepSeek Provider 和 AlarmKit 在后续迭代接入。
