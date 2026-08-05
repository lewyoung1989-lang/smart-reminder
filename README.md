# 智能生活提醒

面向个人与家庭的智能提醒 App。当前 MVP 已支持：

- 输入中文文字生成结构化提醒草稿。
- “今天/明天几点”和“几分钟后”等简单表达由本地规则解析。
- 复杂单次提醒在配置后交给 DeepSeek JSON 模式解析。
- 所有解析结果必须由用户确认，确认前不会创建正式提醒。
- 确认后在 iPhone 安排一次本地通知。
- 服务端不保存原始输入，只保存 SHA-256 和结构化草稿。

AlarmKit 强闹钟、FunASR 服务端语音识别、天气预检查和家庭药箱仍在后续阶段。

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

请求需要 `Authorization: Bearer <token>`。文字和语音最终使用同一套结构化草稿、确认和幂等逻辑。

## Docker Compose

安装 Docker Desktop 后运行：

```bash
docker compose config
docker compose up --build
```

服务包括 PostgreSQL、Redis、MinIO、Django API、Celery Worker 和 Celery Beat。MinIO 控制台位于 `http://127.0.0.1:9001`。
