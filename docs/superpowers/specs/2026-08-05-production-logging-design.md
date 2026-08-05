# 生产日志系统设计

## 目标

为腾讯云单机部署建立可检索、保护隐私的生产日志系统。日志保留 7 天，限制最大磁盘占用，并提供明确、稳定的运维路径。

## 当前状态

- 所有生产容器使用 Docker `json-file` 日志驱动，每个容器最多保留 5 个 10MB 文件。
- Docker 日志物理路径依赖容器 ID，不能作为稳定的运维路径。
- Gunicorn 会输出启动和错误信息，但没有输出访问日志。
- `files.aipupu.cloud` 已关闭 Nginx 访问日志，避免上传签名参数泄露。
- PostgreSQL 备份和证书续期分别由 `smart-reminder-postgres-backup.timer`、`smart-reminder-cert-renew.timer` 执行。
- 服务器当前 journal 占用约 32MB。

## 设计决策

### 运行日志存储

所有生产容器改用 Docker `journald` 日志驱动。Docker 为日志添加 `smart-reminder/<服务名>` 格式的稳定标签，journald 将日志保存在持久化二进制目录：

```text
/var/log/journal/
```

服务器安装 `/etc/systemd/journald.conf.d/50-smart-reminder.conf`：

```ini
[Journal]
Storage=persistent
Compress=yes
MaxRetentionSec=7day
SystemMaxUse=1G
```

保留时间和容量限制会作用于服务器的全部 journal，包括操作系统日志。当前服务器只承载本项目，因此该方案可以统一控制日志并防止系统盘被写满。

### 可直接读取的运维日志

部署、备份和证书续期等长时间运维操作，同时写入以下纯文本目录：

```text
/opt/smart-reminder/logs/deploy/
/opt/smart-reminder/logs/backup/
/opt/smart-reminder/logs/cert/
```

根目录所有者为 `ubuntu:ubuntu`，权限为 `0750`；日志文件权限为 `0640`。每日 logrotate 会压缩历史日志，并删除超过 7 天的文件。

现有 systemd timer 名称保持不变。对应 service 继续调用仓库中的脚本，每次运行记录开始时间、结果和不含密钥的命令输出。

## 日志内容

| 来源 | 记录内容 | 明确禁止记录 |
|---|---|---|
| Nginx | 时间、请求 ID、方法、不含查询参数的路径、状态码、响应字节、请求及上游耗时 | 查询参数、Authorization、请求正文 |
| Gunicorn | 请求 ID、方法、不含查询参数的路径、状态码、耗时 | 查询参数、请求头、请求正文 |
| Django | 时间、级别、logger、事件码、内部实体 ID、解析器或 Provider 结果、异常类型 | 提醒原文、结构化草稿内容、Token、API Key |
| Celery | 任务名、任务 ID、队列、生命周期、耗时、重试和失败类型 | 任务载荷和用户内容 |
| OCR Worker | 任务 ID、Provider、耗时、识别行数、结果、重试、图片删除结果 | 图片、OCR 原文、签名 URL、对象存储凭据 |
| PostgreSQL、Redis、MinIO | 启停、健康状态和服务错误 | 数据库密码和对象存储凭据 |
| 部署 | 完整 Git SHA、环境校验结果、迁移及 OCR 检查结果、服务健康状态、Nginx 重载结果 | 环境文件内容和密钥 |
| 备份、证书 | 开始及结束时间、备份文件名或证书域名、结果和耗时 | 凭据和私钥内容 |

Nginx 使用 `$uri`，不使用 `$request_uri`，确保上传签名参数不会进入访问日志。首版不记录来源 IP；这是个人和家庭应用，请求 ID 已足够关联一次请求的上下游日志。

## 应用日志

Django 增加明确的控制台 `LOGGING` 配置，使用稳定的单行格式。日志级别由环境变量 `LOG_LEVEL` 控制，生产环境默认 `INFO`。现有 OCR 日志继续只记录实体 ID 和数量等元数据。

Gunicorn 将访问日志和错误日志输出到标准输出及标准错误。访问日志只包含请求方法、不含查询参数的路径、状态码、响应大小、耗时和上游传入的请求 ID。

Nginx 在请求没有 ID 时生成请求 ID，通过 `X-Request-ID` 传给后端，并使用安全格式向标准输出写访问日志。API 域名和文件上传域名使用相同安全格式，上传签名参数始终被排除。

## 运维查询接口

`deploy/tencent/scripts/logs.sh` 是统一的运行日志查询入口：

```text
logs.sh SERVICE [--since TIME] [--level LEVEL] [--follow]
```

允许的服务名为 `api`、`worker`、`ocr-worker`、`beat`、`nginx`、`postgres`、`redis`、`minio` 和 `all`。脚本拒绝未知服务，并使用稳定 Docker 标签查询 journal。例如：

```bash
./deploy/tencent/scripts/logs.sh api --since "2 hours ago"
./deploy/tencent/scripts/logs.sh ocr-worker --level error
./deploy/tencent/scripts/logs.sh all --since today --follow
```

腾讯云部署手册需要列出 journal 路径、三个运维日志路径，以及直接使用 `journalctl` 和 `tail` 的示例。运维人员应使用查询脚本，不直接依赖 Docker 内部实现目录。

## 安装与部署

`deploy/tencent/scripts/install_logging.sh` 负责需要管理员权限的服务器初始化：

1. 要求以 root 运行，并校验 `/opt/smart-reminder` 安装目录。
2. 创建三个运维日志目录，设置固定所有者和权限。
3. 安装 journald 配置片段和 logrotate 策略。
4. 重启 journald，验证持久化存储及生效的保留限制。
5. 只输出路径和校验结果，不输出环境变量或密钥。

生产 Compose 文件把所有服务切换到 `journald` 并配置稳定标签。只有服务器日志初始化成功后才重新创建容器。部署继续使用经过审核的完整 Git SHA。

## 失败处理

- journald 安装或校验失败时，不修改现有容器。
- 容器无法连接 journald 时，Compose 部署必须失败，不能重载 Nginx。
- 无法创建运维日志文件时，部署、备份或证书脚本返回非零状态，不允许在没有审计记录的情况下继续执行。
- 日志故障不能触发数据库回滚或数据卷删除。
- journald 与 logrotate 分别独立限制运行日志和运维日志的磁盘占用。

## 验证方案

自动化测试覆盖：

- 所有生产服务使用 `journald` 和稳定标签。
- Nginx 访问日志包含 `$uri`，不包含 `$request_uri`、查询参数变量、Authorization 或签名 URL 数据。
- Django 只向控制台写日志，并使用有效的默认生产日志级别。
- `logs.sh` 校验服务名，并生成正确的 journal 查询条件。
- `install_logging.sh` 和 logrotate 配置包含 7 天保留期、1GB journal 上限、正确路径、所有者及权限。
- 部署、备份和证书脚本不输出环境文件内容。

生产验收检查 journald 生效配置、容器日志驱动元数据、一次带请求 ID 的公网健康请求、运维目录权限、timer 日志以及 7 天和容量限制。
