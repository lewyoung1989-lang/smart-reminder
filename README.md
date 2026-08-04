# 智能生活提醒

面向个人与家庭的智能提醒 App。当前 MVP 已支持：

- 输入中文文字生成结构化提醒草稿。
- “今天/明天几点”和“几分钟后”等简单表达由本地规则解析。
- 复杂单次提醒在配置后交给 DeepSeek JSON 模式解析。
- 所有解析结果必须由用户确认，确认前不会创建正式提醒。
- 确认后在 iPhone 安排一次本地通知。
- 服务端不保存原始输入，只保存 SHA-256 和结构化草稿。

药盒 OCR 当前使用自建 RapidOCR，候选结果必须人工核对后才会写入药箱。AlarmKit 强闹钟、语音识别和天气预检查仍在后续阶段。

## 本地后端

```bash
make install
cp .env.example .env
.venv/bin/python backend/manage.py migrate
.venv/bin/python backend/manage.py create_local_test_token
make run-backend
```

健康检查：`http://127.0.0.1:8000/api/v1/health`

`create_local_test_token` 会输出本地开发 Bearer Token。该命令只在 `DEBUG=True` 时可用；Token 不应提交到 Git、截图分享或用于线上环境。

## DeepSeek

在 Git 忽略的 `.env` 中设置：

```dotenv
DEEPSEEK_API_KEY=你的本地密钥
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
DEEPSEEK_TIMEOUT_SECONDS=8
```

修改后重启 Django。简单表达不会调用模型；例如“下周一上午十点提醒我体检”会在本地规则无法确定时调用 DeepSeek。草稿页会显示“本地规则”“DeepSeek”或“本地规则（模型不可用）”。

模型输出始终经过 Pydantic 严格字段校验。非创建意图、额外权限字段、错误时区和过去时间会被拒绝；DeepSeek Key、完整输入和完整模型响应不写日志。

## iPhone 通知测试

1. Mac 与 iPhone 连接同一局域网。
2. 执行 `ipconfig getifaddr en0` 获取 Mac 局域网 IP。
3. 把这个 IP 加入 `.env` 的 `DJANGO_ALLOWED_HOSTS`，然后重启后端。
4. 使用上一步生成的 Token 启动 Flutter App：

```bash
cd app
../scripts/flutterw run \
  --dart-define=API_BASE_URL=http://<MAC局域网IP>:8000 \
  --dart-define=API_ACCESS_TOKEN=<本地Token>
```

5. 输入“1分钟后提醒我喝水”，检查草稿时间后点击“确认创建”。
6. 首次确认时允许通知，将 App 切到后台，约一分钟后应收到“喝水”通知。

如果通知权限被拒绝，服务端提醒仍会创建，但 App 会明确显示“提醒已创建，但手机通知未安排”。再次点击确认只重试手机通知，不会重复创建服务端提醒。

模拟器可验证 UI 和编译，锁屏、后台和真实通知权限必须使用 iPhone 验证。当前实现是普通本地通知，不等同于 iOS 26 AlarmKit 强闹钟。

## Flutter 检查

```bash
cd app
../scripts/flutterw test
../scripts/flutterw analyze
../scripts/flutterw build ios --simulator --debug
```

## 当前 API

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/v1/health` | 服务健康检查 |
| POST | `/api/v1/reminder-drafts` | 解析文字并创建短期草稿 |
| POST | `/api/v1/reminder-drafts/{id}/confirm` | 人工确认并创建正式提醒 |
| POST | `/api/v1/voice/reminder-drafts` | 兼容上一阶段的转写草稿路径 |
| POST | `/api/v1/voice/reminder-drafts/{id}/confirm` | 兼容上一阶段的确认路径 |
| POST | `/api/v1/ocr/uploads` | 获取私有药盒图片的限时上传地址 |
| POST | `/api/v1/ocr/jobs` | 创建药盒 OCR 任务 |
| GET | `/api/v1/ocr/jobs/{id}` | 查询任务状态与结构化候选值 |
| POST | `/api/v1/ocr/jobs/{id}/confirm` | 人工确认候选并创建药品库存 |

请求需要 `Authorization: Bearer <token>`。文字和语音最终使用同一套结构化草稿、确认和幂等逻辑。

## Docker Compose

安装 Docker Desktop 后运行：

```bash
docker compose config
docker compose up --build
```

服务包括 PostgreSQL、Redis、MinIO、Django API、普通 Celery Worker、并发为 1 的 OCR Worker 和 Celery Beat。MinIO 控制台位于 `http://127.0.0.1:9001`。

只启动 OCR 闭环依赖并执行安全冒烟检查：

```bash
docker compose up -d postgres redis minio api ocr-worker beat
docker compose exec ocr-worker python manage.py check_ocr tests/ocr/fixtures/medicine_front.jpg
```

API 镜像只安装 `backend/requirements/base.txt`；RapidOCR、ONNX Runtime 和 OpenCV 只存在于 `ocr-worker` 镜像。

## OCR 配置

本地 `.env` 可使用以下配置；腾讯云部署时将 Endpoint、Region 和凭据替换为私有 COS 配置：

```dotenv
OCR_PROVIDER=rapidocr
OCR_LANGUAGE=ch
OCR_TEXT_SCORE=0.50
OCR_MAX_IMAGE_BYTES=8388608
OCR_MAX_IMAGE_SIDE=2048
OCR_JOB_RETENTION_HOURS=24
OCR_WORKER_CONCURRENCY=1
OCR_TASK_SOFT_TIME_LIMIT=45
OCR_TASK_TIME_LIMIT=60
OCR_MAX_RETRIES=2
OCR_MODEL_ROOT=
OCR_QUEUE=ocr
OCR_STORAGE_PROVIDER=s3
OCR_UPLOAD_URL_TTL_SECONDS=600
S3_ENDPOINT=http://minio:9000
S3_BUCKET=smart-reminder-private
S3_REGION=us-east-1
S3_ADDRESSING_STYLE=path
S3_ACCESS_KEY_ID=smart-reminder
S3_SECRET_ACCESS_KEY=local-development-only
```

腾讯云亲友内测建议使用 4 核 4 GB、系统盘至少 60 GB 的轻量服务器。PostgreSQL 和 Redis 初期可随 Compose 部署，药盒图片必须放入私有 COS；公网只开放 HTTPS，数据库、Redis 和对象存储管理端口保持私网可见。

上线前检查：

- 本地 MinIO 或云端 COS 已创建私有 `smart-reminder-private` 桶，匿名读写和列表均关闭。
- COS 桶禁止匿名读写和列表，开启服务端加密，`ocr/tmp/` 生命周期设为 1 天。
- OCR Worker 固定 `1 CPU`、约 `700 MB` 预留、`1.2 GB` 上限、并发 `1`。
- 生产环境在构建或发布阶段准备模型文件，挂载只读 `OCR_MODEL_ROOT`，启动时不联网下载。
- Celery 超时为 `45/60` 秒，最多重试 `2` 次；每小时清理过期图片。
- 日志只包含任务 ID、耗时、行数、Provider 和错误码，不包含 OCR 原文、图片、签名 URL 或密钥。
- 监控主机内存、Worker 重启、队列深度、P95 耗时、失败率和图片删除失败。
