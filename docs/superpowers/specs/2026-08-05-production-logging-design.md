# Production Logging Design

## Goal

Give the single-server Tencent Cloud deployment searchable, privacy-safe logs with a seven-day retention window, bounded disk usage, and documented operational paths.

## Current State

- Every production container uses Docker's `json-file` logging driver with five 10 MB files.
- The physical Docker log path is container-ID dependent and unsuitable as an operator contract.
- Gunicorn emits startup and error output but does not emit access logs.
- Nginx disables access logs for `files.aipupu.cloud` to avoid leaking signed upload query parameters.
- PostgreSQL backup and certificate renewal already run through `smart-reminder-postgres-backup.timer` and `smart-reminder-cert-renew.timer`.
- The host journal currently uses about 32 MB.

## Decisions

### Runtime Storage

All production containers use Docker's `journald` logging driver. Docker adds a stable tag in the form `smart-reminder/<service>` and journald stores the records under its persistent binary store:

```text
/var/log/journal/
```

The host installs `/etc/systemd/journald.conf.d/50-smart-reminder.conf` with:

```ini
[Journal]
Storage=persistent
Compress=yes
MaxRetentionSec=7day
SystemMaxUse=1G
```

The retention and size limits apply to the host journal, including operating-system logs. This is appropriate for the dedicated single-application server and prevents logs from filling the system disk.

### Human-Readable Operation Logs

Long-running operational commands also write plain-text timestamped logs under:

```text
/opt/smart-reminder/logs/deploy/
/opt/smart-reminder/logs/backup/
/opt/smart-reminder/logs/cert/
```

The root directory is owned by `ubuntu:ubuntu`, has mode `0750`, and log files have mode `0640`. A daily logrotate rule compresses old files and deletes files older than seven days.

The existing timers retain their names. Their services call the repository scripts, and each script records start time, result, and non-secret command output in its corresponding operation directory.

## Log Content

| Source | Records | Explicitly excluded |
|---|---|---|
| Nginx | timestamp, request ID, method, path without query, status, bytes, request/upstream duration | query string, Authorization header, request body |
| Gunicorn | request ID, method, path without query, status, duration | query string, headers, body |
| Django | timestamp, level, logger, event code, internal entity IDs, parser/provider result, exception class | reminder text, structured draft content, Token, API key |
| Celery | task name/ID, queue, lifecycle, duration, retry and failure class | task payload and user content |
| OCR worker | job ID, provider, duration, recognized line count, outcome, retry, deletion outcome | image, OCR text, signed URL, object credentials |
| PostgreSQL/Redis/MinIO | startup, shutdown, health and service errors | database passwords and object-store credentials |
| Deployment | full Git SHA, environment validation result, migration/OCR check outcome, service health and Nginx reload | environment file contents and secrets |
| Backup/certificate | start/end, destination filename or certificate domains, result and duration | credentials and private-key contents |

Nginx uses `$uri`, never `$request_uri`, so signed upload parameters cannot enter access logs. Source IPs are omitted in the first release because this is a personal/family application and request IDs are sufficient for request correlation.

## Application Logging

Django defines an explicit console `LOGGING` configuration with a stable one-line formatter and an environment-controlled `LOG_LEVEL` defaulting to `INFO` in production. Existing OCR log events continue to use entity IDs and counts only.

Gunicorn writes access and error logs to stdout/stderr. Its access format contains method, URL path without query, status, response size, duration, and the forwarded request ID.

Nginx creates a request ID when absent, forwards it as `X-Request-ID`, and writes its safe access format to stdout. The API and files hosts both use the same safe format; upload query signatures remain excluded.

## Operator Interface

`deploy/tencent/scripts/logs.sh` is the supported runtime interface:

```text
logs.sh SERVICE [--since TIME] [--level LEVEL] [--follow]
```

Allowed services are `api`, `worker`, `ocr-worker`, `beat`, `nginx`, `postgres`, `redis`, `minio`, and `all`. The script rejects unknown values and invokes `journalctl` using the stable Docker tag. Examples:

```bash
./deploy/tencent/scripts/logs.sh api --since "2 hours ago"
./deploy/tencent/scripts/logs.sh ocr-worker --level error
./deploy/tencent/scripts/logs.sh all --since today --follow
```

The deployment README documents both the journal path and operation-log paths, plus direct `journalctl` and `tail` examples. Operators should use the script instead of reading Docker's implementation directories.

## Installation And Deployment

`deploy/tencent/scripts/install_logging.sh` performs the privileged host setup. It:

1. Requires root and validates the expected `/opt/smart-reminder` installation.
2. Creates the three operation-log directories with fixed ownership and modes.
3. Installs the journald drop-in and logrotate policy.
4. Restarts journald and verifies persistent storage and effective limits.
5. Prints only paths and validation results.

The production Compose contract changes every service to `journald` with its stable tag. Containers are recreated only after host logging installation succeeds. Deployment continues using the reviewed full Git SHA.

## Failure Handling

- If journald installation or validation fails, existing containers remain unchanged.
- If a container cannot attach to journald, Compose deployment fails before Nginx is reloaded.
- If operation-log file creation fails, deploy/backup/certificate scripts exit non-zero instead of running without an audit record.
- Logging failures never trigger database rollback or volume deletion.
- Disk limits are enforced by journald and logrotate independently.

## Verification

Automated tests cover:

- Compose uses `journald` and stable tags for every production service.
- Nginx access formats contain `$uri` and exclude `$request_uri`, query variables, Authorization, and signed URL data.
- Django logging is console-only and defaults to a valid production level.
- `logs.sh` validates service names and constructs the correct journal filter.
- `install_logging.sh` and logrotate configuration specify seven-day retention, `1G` journal usage, correct paths, ownership, and permissions.
- Deploy, backup, and certificate scripts never print environment file contents.

Production acceptance verifies effective journald configuration, container log-driver metadata, one public health request correlated by request ID, operation directory permissions, timer logs, and seven-day/log-size settings.
