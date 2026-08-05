# 智能生活提醒

面向个人与家庭的智能提醒 App。当前 MVP 已支持：

- 输入中文文字生成结构化提醒草稿。
- “今天/明天几点”和“几分钟后”等简单表达由本地规则解析。
- 复杂单次提醒在配置后交给 DeepSeek JSON 模式解析。
- 所有解析结果必须由用户确认，确认前不会创建正式提醒。
- 确认后在 iPhone 安排一次本地通知。
- 在 iPhone 录制最长 20 秒的语音，通过私有 FunASR 服务转成可编辑文字。
- 服务端不保存原始输入，只保存 SHA-256 和结构化草稿。

AlarmKit 强闹钟、天气预检查和家庭药箱仍在后续阶段。

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

## FunASR 语音输入

语音入口位于现有提醒输入框下方。点击麦克风开始录音，再点击停止后，识别文字会填入同一个输入框；用户可以编辑文字，并且仍需主动点击“解析提醒”和“确认创建”。识别本身不会创建草稿或正式提醒。

真实 FunASR 通过 Docker Compose 启动：

```bash
cp .env.example .env
docker compose build funasr-model-init funasr api
docker compose up funasr api
```

首次启动会下载数 GB 的 PyTorch、FunASR 运行时和模型权重，模型缓存初始化可能持续较长时间。`funasr-model-init` 完成后，正式 `funasr` 服务以只读方式挂载持久化模型缓存。可从容器内部检查 readiness：

```bash
docker compose exec funasr python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())"
```

FunASR 不映射宿主机端口，只能由 Compose 私有网络中的 Django API 调用。音频、转写文本和上游原始响应不会写入数据库或日志；上传对象和 iPhone 临时 WAV 在请求结束后清理。上线前需另外确认目标模型权重许可证、普通话样本准确率和目标 CPU 的 p95 延迟。

当前 Compose 的 API 端口用于本地直连，IP 限流只使用连接来源 `REMOTE_ADDR`，不会信任客户端伪造的转发头。生产环境接入 Nginx 时，必须由 Nginx 覆盖 `X-Forwarded-For` 为单一客户端 IP，并把 Nginx 到 Django 的固定来源 IP 写入 `ASR_TRUSTED_PROXY_IPS`；未在白名单中的来源仍忽略转发头。

模型缓存固定使用以下 ModelScope 权重标签；2026-08-05 通过 ModelScope 模型 API 核对，三者均标注为 Apache License 2.0。上线前仍需由发布负责人复核模型页与实际缓存文件中的许可证：

| 用途 | ModelScope 模型 | Revision |
|---|---|---|
| ASR | [`iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch`](https://modelscope.cn/models/iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch) | `v2.0.4` |
| VAD | [`iic/speech_fsmn_vad_zh-cn-16k-common-pytorch`](https://modelscope.cn/models/iic/speech_fsmn_vad_zh-cn-16k-common-pytorch) | `v2.0.4` |
| 标点 | [`iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch`](https://modelscope.cn/models/iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch) | `v2.0.4` |

普通开发和 CI 不需要下载模型。后端 Provider 使用 fake，模型服务使用 fake engine：

```bash
.venv/bin/pytest backend/tests/voice -q
.venv/bin/python -m pip install -r services/funasr/requirements-test.txt
.venv/bin/python -m pytest services/funasr/tests -q
```

完成真实服务启动后，用 iPhone 启动命令连接 Django，允许麦克风权限并录制一条普通话提醒。若返回忙碌、超时或服务不可用，App 会保留键盘输入和已有文字，不会自动把音频发送到第三方服务。

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
| POST | `/api/v1/voice/transcriptions` | 上传短 PCM WAV 并返回 FunASR 转写文字 |
| POST | `/api/v1/voice/reminder-drafts` | 兼容上一阶段的转写草稿路径 |
| POST | `/api/v1/voice/reminder-drafts/{id}/confirm` | 兼容上一阶段的确认路径 |

请求需要 `Authorization: Bearer <token>`。文字和语音最终使用同一套结构化草稿、确认和幂等逻辑。

## 设计文档

- 总体设计：`docs/superpowers/specs/2026-08-03-smart-life-reminder-design.md`
- FunASR 服务端语音识别：`docs/superpowers/specs/2026-08-05-funasr-server-asr-design.md`
- V2 提升路线图：`docs/superpowers/specs/2026-08-05-smart-reminder-v2-enhancements.md`

## Docker Compose

安装 Docker Desktop 后运行：

```bash
docker compose config
docker compose up --build
```

服务包括 PostgreSQL、Redis、MinIO、Django API、Celery Worker、Celery Beat、FunASR 模型缓存初始化和私有 FunASR 推理服务。MinIO 控制台位于 `http://127.0.0.1:9001`；FunASR 没有宿主机访问地址。
