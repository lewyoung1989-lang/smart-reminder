# 生产日志系统实施计划

> **面向代理开发者：** 必须使用 `superpowers:executing-plans` 逐项实施本计划，并在每项功能中遵循 `superpowers:test-driven-development`；所有任务完成后使用 `superpowers:verification-before-completion` 做最终验证。

**目标：** 为腾讯云单机生产环境建立可检索、保护隐私、最多保留 7 天且有磁盘上限的日志系统，并提供稳定的日志路径和中文运维说明。

**架构：** Docker 容器只向标准输出和标准错误写日志，由 `journald` 统一持久化；部署、备份和证书任务另外写入固定的纯文本目录。Nginx 生成请求 ID 并只记录不带查询参数的路径，Gunicorn 和 Django 以单行格式输出必要元数据，运维人员通过受约束的查询脚本检索日志。

**技术栈：** Docker Compose、systemd-journald、logrotate、Bash、Nginx、Gunicorn、Django、pytest。

---

### 任务 1：固定生产容器日志契约

**文件：**

- 修改：`backend/tests/deployment/test_compose_contract.py`
- 修改：`deploy/tencent/compose.production.yaml`

- [ ] **步骤 1：写入失败的 Compose 契约测试**

将原来的 `json-file` 轮转断言替换为对全部生产服务的 `journald` 驱动和稳定标签断言，并断言 API 的 Gunicorn 命令输出安全访问日志：

```python
def test_production_services_use_journald_with_stable_tags():
    services = load_production_compose()["services"]
    expected = {
        name: f"smart-reminder/{name}"
        for name in services
        if name != "certbot"
    }
    for name, tag in expected.items():
        assert services[name]["logging"] == {
            "driver": "journald",
            "options": {"tag": tag},
        }


def test_gunicorn_access_log_excludes_query_strings_and_headers():
    command = load_production_compose()["services"]["api"]["command"]
    assert "--access-logfile -" in command
    assert "--error-logfile -" in command
    assert "%(U)s" in command
    assert "%(q)s" not in command
    assert "%(r)s" not in command
    assert "x-request-id" in command.lower()
```

- [ ] **步骤 2：运行测试并确认因旧日志配置而失败**

运行：

```bash
cd backend
pytest tests/deployment/test_compose_contract.py -q
```

预期：新测试因驱动仍为 `json-file` 且 Gunicorn 未启用访问日志而失败。

- [ ] **步骤 3：实现 Compose 与 Gunicorn 配置**

把日志锚点改为参数化稳定标签，并为每个服务传入服务名；在后端公共环境中增加 `LOG_LEVEL=${LOG_LEVEL:-INFO}`。API 命令加入：

```text
--access-logfile - --error-logfile -
--access-logformat request_id=%({x-request-id}i)s method=%(m)s path=%(U)s status=%(s)s bytes=%(b)s duration_us=%(D)s
```

格式中不得使用包含查询参数的 `%(q)s` 或完整请求行 `%(r)s`。

- [ ] **步骤 4：运行测试并确认通过**

运行：`cd backend && pytest tests/deployment/test_compose_contract.py -q`

预期：全部通过。

### 任务 2：增加 Django 控制台日志配置

**文件：**

- 修改：`backend/tests/deployment/test_production_settings.py`
- 修改：`backend/config/settings.py`
- 修改：`deploy/tencent/env.production.example`

- [ ] **步骤 1：写入失败的生产设置测试**

在子进程环境中设置 `LOG_LEVEL=WARNING`，并增加：

```python
assert settings.LOGGING["handlers"] == {
    "console": {
        "class": "logging.StreamHandler",
        "formatter": "production",
    }
}
assert settings.LOGGING["root"]["handlers"] == ["console"]
assert settings.LOGGING["root"]["level"] == "WARNING"
assert settings.LOGGING["formatters"]["production"]["format"] == (
    "%(asctime)s level=%(levelname)s logger=%(name)s message=%(message)s"
)
```

另在环境模板契约测试中断言 `LOG_LEVEL=INFO`。

- [ ] **步骤 2：运行测试并确认设置尚不存在**

运行：

```bash
cd backend
pytest tests/deployment/test_production_settings.py \
  tests/deployment/test_env_contract.py -q
```

预期：因 `LOGGING` 或 `LOG_LEVEL` 尚未定义而失败。

- [ ] **步骤 3：实现最小控制台日志配置**

在 `settings.py` 校验 `LOG_LEVEL` 仅允许 Python 标准日志级别，并建立单一 `console` handler；不配置文件 handler，不记录请求正文。在生产环境示例中增加 `LOG_LEVEL=INFO`。

- [ ] **步骤 4：运行设置测试并确认通过**

运行：

```bash
cd backend
pytest tests/deployment/test_production_settings.py \
  tests/deployment/test_env_contract.py -q
```

预期：全部通过。

### 任务 3：增加不泄露隐私的 Nginx 请求日志

**文件：**

- 修改：`backend/tests/deployment/test_compose_contract.py`
- 修改：`deploy/tencent/nginx/aipupu.cloud.conf`
- 修改：`deploy/tencent/nginx/bootstrap.conf`

- [ ] **步骤 1：写入失败的 Nginx 日志契约测试**

解析正式配置中的 `log_format smart_reminder` 行，并断言：

```python
assert "$uri" in log_format
assert "$request_uri" not in log_format
assert "$args" not in log_format
assert "$query_string" not in log_format
assert "$remote_addr" not in log_format
assert "$http_authorization" not in log_format
assert "$smart_request_id" in log_format
assert "access_log /dev/stdout smart_reminder;" in config
assert "proxy_set_header X-Request-ID $smart_request_id;" in config
```

同时把文件域名测试从 `access_log off` 改为使用安全格式，并保留只允许 `PUT` 的约束。

- [ ] **步骤 2：运行测试并确认旧配置失败**

运行：`cd backend && pytest tests/deployment/test_compose_contract.py -q`

预期：因缺少安全日志格式和请求 ID 透传而失败。

- [ ] **步骤 3：实现安全日志与请求 ID**

在正式 Nginx 配置顶层增加：

```nginx
map $http_x_request_id $smart_request_id {
    default $http_x_request_id;
    "" $request_id;
}

log_format smart_reminder
    'time=$time_iso8601 request_id=$smart_request_id method=$request_method '
    'path=$uri status=$status bytes=$body_bytes_sent '
    'request_time=$request_time upstream_time=$upstream_response_time';
access_log /dev/stdout smart_reminder;
error_log /dev/stderr crit;
```

API 和文件上传代理都透传并向客户端响应 `X-Request-ID`，只接受字符集和长度安全的外部 ID。上传域名不再关闭访问日志，但安全格式绝不包含签名查询参数；错误日志只保留不附带请求行的严重系统错误。引导配置采用相同的错误日志边界。

- [ ] **步骤 4：运行测试并确认通过**

运行：`cd backend && pytest tests/deployment/test_compose_contract.py -q`

预期：全部通过。

### 任务 4：建立 journald、logrotate 和统一查询入口

**文件：**

- 创建：`deploy/tencent/logging/50-smart-reminder.conf`
- 创建：`deploy/tencent/logging/smart-reminder.logrotate`
- 创建：`deploy/tencent/scripts/logs.sh`
- 创建：`deploy/tencent/scripts/install_logging.sh`
- 创建：`deploy/tencent/scripts/verify_logging.sh`
- 修改：`backend/tests/deployment/test_operations_scripts.py`

- [ ] **步骤 1：写入失败的安装与查询契约测试**

扩展 Bash 语法测试以包含两个新脚本，并增加断言：

```python
def test_journald_and_logrotate_keep_logs_for_seven_days():
    journald = (REPO_ROOT / "deploy/tencent/logging/50-smart-reminder.conf").read_text()
    assert "Storage=persistent" in journald
    assert "Compress=yes" in journald
    assert "MaxRetentionSec=7day" in journald
    assert "SystemMaxUse=1G" in journald
    rotate = (REPO_ROOT / "deploy/tencent/logging/smart-reminder.logrotate").read_text()
    assert "/opt/smart-reminder/logs/*/*.log" in rotate
    assert "daily" in rotate
    assert "rotate 7" in rotate
    assert "maxage 7" in rotate
    assert "create 0640 ubuntu ubuntu" in rotate


def test_logging_installer_uses_expected_paths_and_permissions():
    script = (SCRIPTS / "install_logging.sh").read_text()
    for path in ("logs/deploy", "logs/backup", "logs/cert"):
        assert path in script
    assert "0750" in script
    assert "ubuntu" in script
    assert "systemd-journald" in script


def test_log_query_rejects_unknown_service_and_uses_stable_tag(tmp_path):
    # 用 PATH 中的假 journalctl 捕获参数；unknown 必须非零，api 必须包含
    # CONTAINER_TAG=smart-reminder/api，且支持 --since、--level、--follow。
```

- [ ] **步骤 2：运行测试并确认文件缺失**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：因新文件不存在而失败。

- [ ] **步骤 3：实现配置和脚本**

`50-smart-reminder.conf` 写入已设计的四项 journald 设置。logrotate 对三个运维目录每日压缩并保留 7 天。

`logs.sh SERVICE [--since TIME] [--level LEVEL] [--follow]` 使用 Bash 数组调用 `journalctl`，只允许九个服务名和 `all`；`--level` 使用日志正文中的标准级别标记，不使用无法反映应用级别的 stdout/stderr journal priority；禁止用 `eval` 拼接命令。

`install_logging.sh` 必须以 root 运行，校验 `/opt/smart-reminder/app`，创建三个 `ubuntu:ubuntu`、`0750` 目录，安装配置，创建持久 journal 目录并重启 journald。`verify_logging.sh` 拒绝会覆盖项目保留策略的后序 drop-in，并检查 journald、持久目录、Docker 驱动和运维目录。任何校验失败均返回非零，且在此脚本中不执行 Compose。

- [ ] **步骤 4：运行测试并确认通过**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：全部通过。

### 任务 5：让部署、备份和证书续期写入稳定日志目录

**文件：**

- 创建：`deploy/tencent/scripts/operation_logging.sh`
- 创建：`deploy/tencent/scripts/renew_certificate.sh`
- 创建：`deploy/tencent/systemd/smart-reminder-postgres-backup.service`
- 创建：`deploy/tencent/systemd/smart-reminder-postgres-backup.timer`
- 创建：`deploy/tencent/systemd/smart-reminder-cert-renew.service`
- 创建：`deploy/tencent/systemd/smart-reminder-cert-renew.timer`
- 修改：`deploy/tencent/scripts/deploy.sh`
- 修改：`deploy/tencent/scripts/backup_postgres.sh`
- 修改：`deploy/tencent/scripts/install_logging.sh`
- 修改：`backend/tests/deployment/test_operations_scripts.py`

- [ ] **步骤 1：写入失败的运维日志测试**

断言三个操作脚本加载统一 helper，分别选择 `deploy`、`backup`、`cert`，并断言 helper 使用 `umask 027`、`tee`、`0640`，遇到不可写目录时失败。断言 systemd 服务只调用仓库脚本、不读取或打印环境文件，两个 timer 保持每日备份和每月证书续期。

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：因 helper、证书脚本及 unit 文件缺失而失败。

- [ ] **步骤 3：实现统一操作日志**

helper 只负责打开每类稳定日志文件（`deploy.log`、`backup.log`、`cert.log`）、检查目录可写、设置权限、复制标准输出/错误到日志，并在退出时记录结果；logrotate 使用 `dateext` 生成每日归档并按 7 天持续清理。helper 不得输出环境变量。部署脚本在任何构建或容器变更前验证 journald 配置和日志目录。备份脚本组合现有临时文件清理与日志退出处理。证书脚本依次执行 `certbot renew`、`nginx -t`、`nginx -s reload`。

`install_logging.sh` 安装四个 systemd 文件，执行 `daemon-reload` 并启用两个 timer，但不立即触发备份或证书任务。

- [ ] **步骤 4：运行运维测试并确认通过**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：全部通过。

### 任务 6：用中文补全路径、查询和验收手册

**文件：**

- 修改：`deploy/tencent/README.md`
- 修改：`backend/tests/deployment/test_operations_scripts.py`

- [ ] **步骤 1：写入失败的手册契约测试**

在既有手册测试中增加以下必需内容：

```python
for required in (
    "/var/log/journal/",
    "/opt/smart-reminder/logs/deploy/",
    "/opt/smart-reminder/logs/backup/",
    "/opt/smart-reminder/logs/cert/",
    "install_logging.sh",
    "logs.sh api",
    "journalctl --disk-usage",
    "保留 7 天",
):
    assert required in runbook
```

- [ ] **步骤 2：运行测试并确认手册尚未覆盖**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：因缺少日志章节而失败。

- [ ] **步骤 3：更新中文腾讯云部署手册**

增加日志安装顺序、完整路径表、`logs.sh` 示例、`journalctl` 直接查询、文本日志查看、权限检查、7 天保留验证、请求 ID 联查和敏感内容排查。把旧的 `docker compose logs` 作为临时兼容说明移除，因为 journald 驱动下统一入口是 `logs.sh`。

- [ ] **步骤 4：运行测试并确认通过**

运行：`cd backend && pytest tests/deployment/test_operations_scripts.py -q`

预期：全部通过。

### 任务 7：完整验证并准备生产部署

**文件：**

- 检查：本计划涉及的全部文件

- [ ] **步骤 1：运行部署相关测试**

```bash
cd backend
pytest tests/deployment -q
```

预期：全部通过。

- [ ] **步骤 2：运行后端全量测试和 Django 检查**

```bash
cd backend
pytest -q
python manage.py check
```

预期：全部通过且 Django 报告没有系统检查问题。

- [ ] **步骤 3：验证配置和脚本语法**

```bash
bash -n deploy/tencent/scripts/*.sh
APP_VERSION=test DJANGO_SECRET_KEY=test POSTGRES_PASSWORD=test \
DEEPSEEK_API_KEY=test S3_ACCESS_KEY_ID=test S3_SECRET_ACCESS_KEY=test \
MINIO_ROOT_USER=test MINIO_ROOT_PASSWORD=test \
docker compose -f compose.yaml -f deploy/tencent/compose.production.yaml config --quiet
git diff --check
```

预期：全部退出码为 `0`。

- [ ] **步骤 4：逐条核对隐私边界**

搜索 Nginx/Gunicorn/脚本日志配置，确认不记录查询参数、Authorization、请求正文、OCR 原文、图片、Token、密钥或环境文件内容。确认所有设计要求都有测试或手册对应项。

- [ ] **步骤 5：提交并部署审核过的完整 SHA**

提交本计划与实现，通过 GitHub `main` 同步完整 SHA。服务器先执行 `sudo ./deploy/tencent/scripts/install_logging.sh`，只有安装校验成功后才执行：

```bash
./deploy/tencent/scripts/deploy.sh \
  "$(git rev-parse HEAD)" \
  /opt/smart-reminder/shared/.env.production
```

- [ ] **步骤 6：生产验收**

运行 `journalctl --disk-usage`、`systemd-analyze cat-config systemd/journald.conf`、`docker inspect`、`logs.sh`、公网健康检查和目录权限检查。用带测试查询参数的健康请求产生一次日志，并确认日志只包含 `$uri`，不包含查询参数或认证信息。
