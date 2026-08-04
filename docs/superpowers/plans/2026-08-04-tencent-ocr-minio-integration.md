# Tencent OCR MinIO Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the self-hosted medicine OCR flow into the Tencent single-server deployment and publish secure iPhone uploads through `files.aipupu.cloud` while keeping MinIO private.

**Architecture:** Django signs uploads with a public S3 client pointed at Nginx, while API and OCR Worker use a separate internal S3 client pointed directly at MinIO. Production Compose runs MinIO, an idempotent bucket initializer, and a resource-limited RapidOCR Worker on the private network; Nginx terminates one two-domain certificate and exposes only API traffic plus signed image PUT requests.

**Tech Stack:** Python 3.13, Django 5.2, boto3/botocore, Celery 5.5, RapidOCR 3.9.2, ONNX Runtime 1.28.0, PostgreSQL 16, Redis 7, MinIO, Nginx, Certbot, Docker Compose, pytest, Flutter.

---

## File Map

- `backend/config/settings.py`: OCR settings and public/internal S3 endpoint compatibility.
- `backend/apps/ocr/providers/storage.py`: two-client S3 adapter; public client signs uploads, internal client reads/deletes.
- `backend/tests/ocr/providers/test_storage.py`: endpoint routing and Signature V4 tests.
- `deploy/tencent/env.production.example`: complete production contract without real secrets.
- `deploy/tencent/scripts/check_env.py`: fail-closed production environment validation.
- `deploy/tencent/scripts/configure_secrets.sh`: interactive, non-echoing server-side secret setup.
- `deploy/tencent/minio/app-policy.json`: least-privilege application policy for the OCR bucket.
- `deploy/tencent/scripts/init_minio.sh`: idempotent bucket, user, policy, privacy, and lifecycle initialization.
- `deploy/tencent/compose.production.yaml`: private MinIO, initializer, OCR Worker, resource limits, and service dependencies.
- `deploy/tencent/nginx/bootstrap.conf`: two-domain ACME-only HTTP bootstrap.
- `deploy/tencent/nginx/aipupu.cloud.conf`: API server plus PUT-only file server with signing-query logs disabled.
- `deploy/tencent/scripts/bootstrap_tls.sh`: issue one certificate for both hostnames.
- `deploy/tencent/scripts/deploy.sh`: build/start/migrate/smoke-check the integrated stack.
- `backend/tests/deployment/`: executable contracts for environment, Compose, Nginx, TLS, and deployment order.
- `deploy/tencent/README.md`, `README.md`, `.env.example`, `docs/local-development.mmd`: operator and developer instructions.

### Task 1: Merge the OCR Source Branch Without Losing Deployment Hardening

**Files:**
- Modify through merge: `.env.example`
- Modify through merge: `backend/config/settings.py`
- Modify through merge: `backend/requirements/dev.txt`
- Modify through merge: `compose.yaml`
- Modify through merge: `docs/local-development.mmd`
- Add through merge: `backend/apps/medicines/`
- Add through merge: `backend/apps/ocr/`
- Add through merge: `backend/Dockerfile.ocr`
- Add through merge: `app/lib/features/medicine_ocr/`
- Add through merge: `app/test/medicine_ocr_api_test.dart`
- Add through merge: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: Merge the reviewed OCR tip without committing automatically**

Run:

```bash
git merge --no-ff --no-commit cf24eba3c5e8dd36df998399d2916a9eb40b23d8
```

Expected: merge stops only for overlapping integration files; all medicine/OCR modules and Flutter files are staged.

- [ ] **Step 2: Resolve the known dependency conflict as a functional union**

Make `backend/requirements/dev.txt` exactly:

```text
-r base.txt
pytest==8.4.1
pytest-django==4.11.1
pytest-mock==3.14.1
PyYAML==6.0.2
```

Resolve `backend/config/settings.py` by keeping the deployment security settings and all OCR/medicine settings. Resolve `docs/local-development.mmd` in favor of the approved Lighthouse + private MinIO + dedicated OCR Worker topology. Remove every merge marker.

- [ ] **Step 3: Install the merged test and OCR dependencies**

Run:

```bash
.venv/bin/python -m pip install -r backend/requirements/dev.txt
.venv/bin/python -m pip install -r backend/requirements/ocr.txt
```

Expected: both commands exit `0`; RapidOCR, ONNX Runtime, boto3, pytest-mock, and PyYAML are installed.

- [ ] **Step 4: Verify the merge before committing**

Run:

```bash
rg -n '<<<<<<<|=======|>>>>>>>' . --glob '!app/pubspec.lock'
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py makemigrations --check --dry-run
git diff --check
```

Expected: `rg` prints nothing, all 67 backend tests pass, migration check reports no changes, and diff check exits `0`.

- [ ] **Step 5: Commit the source integration**

```bash
git add .
git commit -m "merge: integrate self-hosted medicine OCR"
```

### Task 2: Split Public Signing From Internal MinIO Operations

**Files:**
- Create: `backend/tests/ocr/providers/test_storage.py`
- Modify: `backend/apps/ocr/providers/storage.py`
- Modify: `backend/config/settings.py`
- Modify: `backend/tests/ocr/test_settings.py`
- Modify: `.env.example`
- Modify: `compose.yaml`

- [ ] **Step 1: Write failing storage routing tests**

Create `backend/tests/ocr/providers/test_storage.py`:

```python
from apps.ocr.providers.storage import S3ObjectStorage


class FakeClient:
    def __init__(self, label):
        self.label = label
        self.calls = []

    def generate_presigned_url(self, operation, *, Params, ExpiresIn):
        self.calls.append((operation, Params, ExpiresIn))
        return f"https://{self.label}.invalid/{Params['Bucket']}/{Params['Key']}"

    def get_object(self, *, Bucket, Key):
        self.calls.append(("get_object", Bucket, Key))
        return {"Body": FakeBody()}

    def delete_object(self, *, Bucket, Key):
        self.calls.append(("delete_object", Bucket, Key))


class FakeBody:
    def read(self):
        return b"image-bytes"


def test_presign_uses_public_client_and_reads_use_internal_client(settings):
    settings.S3_BUCKET = "smart-reminder-private"
    public = FakeClient("files")
    internal = FakeClient("minio")
    storage = S3ObjectStorage(
        internal_client=internal,
        public_client=public,
    )

    signed = storage.presign_put(
        key="ocr/tmp/user/front.jpg",
        content_type="image/jpeg",
        expires_in=600,
    )
    image = storage.get_bytes("ocr/tmp/user/front.jpg")
    storage.delete("ocr/tmp/user/front.jpg")

    assert signed["url"].startswith("https://files.invalid/")
    assert public.calls[0][0] == "put_object"
    assert image == b"image-bytes"
    assert [call[0] for call in internal.calls] == ["get_object", "delete_object"]
```

Add to `backend/tests/ocr/test_settings.py`:

```python
def test_s3_endpoints_have_explicit_internal_and_public_settings(settings):
    assert settings.S3_INTERNAL_ENDPOINT
    assert settings.S3_PUBLIC_ENDPOINT
```

- [ ] **Step 2: Run the tests and verify the missing interface fails**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/providers/test_storage.py backend/tests/ocr/test_settings.py -q
```

Expected: FAIL because `S3ObjectStorage` does not accept separate clients and the new endpoint settings do not exist.

- [ ] **Step 3: Implement two endpoint settings**

Replace the single endpoint definition in `backend/config/settings.py` with:

```python
S3_INTERNAL_ENDPOINT = os.environ.get(
    "S3_INTERNAL_ENDPOINT",
    os.environ.get("S3_ENDPOINT", "http://localhost:9000"),
)
S3_PUBLIC_ENDPOINT = os.environ.get(
    "S3_PUBLIC_ENDPOINT",
    S3_INTERNAL_ENDPOINT,
)
S3_BUCKET = os.environ.get("S3_BUCKET", "smart-reminder-private")
S3_REGION = os.environ.get("S3_REGION", "us-east-1")
S3_ADDRESSING_STYLE = os.environ.get("S3_ADDRESSING_STYLE", "path")
S3_ACCESS_KEY_ID = os.environ.get("S3_ACCESS_KEY_ID", "")
S3_SECRET_ACCESS_KEY = os.environ.get("S3_SECRET_ACCESS_KEY", "")
```

The old `S3_ENDPOINT` is read only as a one-release local compatibility fallback.

- [ ] **Step 4: Implement the two-client adapter**

Refactor `backend/apps/ocr/providers/storage.py` around this implementation:

```python
def _build_client(endpoint_url):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        region_name=settings.S3_REGION,
        aws_access_key_id=settings.S3_ACCESS_KEY_ID or None,
        aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY or None,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": settings.S3_ADDRESSING_STYLE},
        ),
    )


class S3ObjectStorage:
    def __init__(self, *, internal_client=None, public_client=None):
        self._bucket = settings.S3_BUCKET
        self._internal_client = internal_client or _build_client(
            settings.S3_INTERNAL_ENDPOINT
        )
        self._public_client = public_client or _build_client(
            settings.S3_PUBLIC_ENDPOINT
        )

    def presign_put(self, *, key, content_type, expires_in):
        url = self._public_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
                "ContentType": content_type,
            },
            ExpiresIn=expires_in,
        )
        return {"url": url, "headers": {"Content-Type": content_type}}

    def get_bytes(self, key):
        response = self._internal_client.get_object(
            Bucket=self._bucket,
            Key=key,
        )
        return response["Body"].read()

    def delete(self, key):
        self._internal_client.delete_object(Bucket=self._bucket, Key=key)
```

- [ ] **Step 5: Wire local Compose and example settings**

In `compose.yaml`, replace `S3_ENDPOINT` with:

```yaml
S3_INTERNAL_ENDPOINT: ${S3_INTERNAL_ENDPOINT:-http://minio:9000}
S3_PUBLIC_ENDPOINT: ${S3_PUBLIC_ENDPOINT:-http://localhost:9000}
```

List both names in `.env.example`, with a comment that iPhone testing must replace `localhost` with the Mac LAN address.

- [ ] **Step 6: Run the focused and full backend tests**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/providers/test_storage.py backend/tests/ocr/test_settings.py -q
.venv/bin/pytest backend -q
```

Expected: focused tests pass and the full backend suite reports 69 passing tests.

- [ ] **Step 7: Commit the storage boundary**

```bash
git add backend/config/settings.py backend/apps/ocr/providers/storage.py \
  backend/tests/ocr/providers/test_storage.py backend/tests/ocr/test_settings.py \
  .env.example compose.yaml
git commit -m "feat: split public and internal OCR storage endpoints"
```

### Task 3: Expand and Harden the Production Environment Contract

**Files:**
- Modify: `deploy/tencent/env.production.example`
- Modify: `deploy/tencent/scripts/check_env.py`
- Create: `deploy/tencent/scripts/configure_secrets.sh`
- Modify: `backend/tests/deployment/test_env_contract.py`
- Modify: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Write failing environment contract tests**

Extend `backend/tests/deployment/test_env_contract.py` to require:

```python
def parse_example_values():
    values = {}
    for raw_line in EXAMPLE.read_text().splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values


def valid_example_values():
    values = parse_example_values()
    values.update(
        DJANGO_SECRET_KEY="test-django-secret",
        POSTGRES_PASSWORD="test-postgres-secret",
        DEEPSEEK_API_KEY="test-deepseek-key",
        CERTBOT_EMAIL="owner@example.com",
        S3_ACCESS_KEY_ID="test-app-user",
        S3_SECRET_ACCESS_KEY="test-app-secret",
        MINIO_ROOT_USER="test-root-user",
        MINIO_ROOT_PASSWORD="test-root-secret",
    )
    return values


def run_validator(tmp_path, values):
    env_file = tmp_path / "production.env"
    env_file.write_text(
        "".join(f"{key}={value}\n" for key, value in values.items())
    )
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(env_file)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_example_has_private_minio_and_dual_endpoint_contract():
    values = parse_example_values()
    assert values["FILES_DOMAIN"] == "files.aipupu.cloud"
    assert values["S3_INTERNAL_ENDPOINT"] == "http://minio:9000"
    assert values["S3_PUBLIC_ENDPOINT"] == "https://files.aipupu.cloud"
    assert values["S3_BUCKET"] == "smart-reminder-private"
    assert values["S3_ADDRESSING_STYLE"] == "path"
    for secret in (
        "S3_ACCESS_KEY_ID",
        "S3_SECRET_ACCESS_KEY",
        "MINIO_ROOT_USER",
        "MINIO_ROOT_PASSWORD",
    ):
        assert values[secret] == ""


def test_validator_rejects_invalid_minio_boundary(tmp_path):
    values = valid_example_values()
    values["S3_PUBLIC_ENDPOINT"] = "http://files.aipupu.cloud"
    values["S3_INTERNAL_ENDPOINT"] = "https://files.aipupu.cloud"
    values["S3_ADDRESSING_STYLE"] = "virtual"
    values["MINIO_ROOT_USER"] = values["S3_ACCESS_KEY_ID"]
    result = run_validator(tmp_path, values)
    assert result.returncode == 1
    assert "S3_PUBLIC_ENDPOINT" in result.stderr
    assert "S3_INTERNAL_ENDPOINT" in result.stderr
    assert "S3_ADDRESSING_STYLE" in result.stderr
    assert "MINIO_ROOT_USER" in result.stderr
```

- [ ] **Step 2: Run the environment tests and verify failure**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_env_contract.py -q
```

Expected: FAIL because the MinIO and file-domain keys are absent.

- [ ] **Step 3: Add the production variables**

Append the following contract to `deploy/tencent/env.production.example`:

```dotenv
FILES_DOMAIN=files.aipupu.cloud
OCR_PROVIDER=rapidocr
OCR_STORAGE_PROVIDER=s3
OCR_JOB_RETENTION_HOURS=24
OCR_QUEUE=ocr
S3_INTERNAL_ENDPOINT=http://minio:9000
S3_PUBLIC_ENDPOINT=https://files.aipupu.cloud
S3_BUCKET=smart-reminder-private
S3_REGION=us-east-1
S3_ADDRESSING_STYLE=path
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
MINIO_ROOT_USER=
MINIO_ROOT_PASSWORD=
```

- [ ] **Step 4: Implement fail-closed validation**

Add every listed key to `REQUIRED`. Extend `validate()` with exact checks:

```python
from urllib.parse import urlparse


files_domain = values.get("FILES_DOMAIN")
public = urlparse(values.get("S3_PUBLIC_ENDPOINT", ""))
if files_domain not in {None, "", "files.aipupu.cloud"}:
    errors.append("FILES_DOMAIN must be files.aipupu.cloud")
if public.scheme != "https" or public.hostname != files_domain:
    errors.append("S3_PUBLIC_ENDPOINT must use HTTPS FILES_DOMAIN")
if values.get("S3_INTERNAL_ENDPOINT") not in {
    None,
    "",
    "http://minio:9000",
}:
    errors.append("S3_INTERNAL_ENDPOINT must be http://minio:9000")
if values.get("S3_ADDRESSING_STYLE") not in {None, "", "path"}:
    errors.append("S3_ADDRESSING_STYLE must be path")
if (
    values.get("MINIO_ROOT_USER")
    and values.get("MINIO_ROOT_USER") == values.get("S3_ACCESS_KEY_ID")
):
    errors.append("MINIO_ROOT_USER must differ from S3_ACCESS_KEY_ID")
```

Keep output limited to variable names and fixed validation messages; never print values.

- [ ] **Step 5: Add a non-echoing server secret configurator**

Create `deploy/tencent/scripts/configure_secrets.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
[[ $# -eq 1 ]] || { echo "usage: configure_secrets.sh ENV_FILE" >&2; exit 2; }
ENV_FILE=$1
[[ -f "$ENV_FILE" ]] || { echo "environment file does not exist" >&2; exit 2; }
VALIDATOR="$ROOT_DIR/deploy/tencent/scripts/check_env.py"

get_value() {
  local wanted=$1 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$wanted="*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done < "$ENV_FILE"
}

replace_value() {
  local wanted=$1 replacement=$2 temp line found=false
  temp=$(mktemp "${ENV_FILE}.XXXXXX")
  chmod 600 "$temp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$wanted="*) printf '%s=%s\n' "$wanted" "$replacement"; found=true ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$ENV_FILE" > "$temp"
  if [[ "$found" == false ]]; then
    printf '%s=%s\n' "$wanted" "$replacement" >> "$temp"
  fi
  mv "$temp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

ensure_value() {
  local key=$1 value=$2
  if [[ -z "$(get_value "$key")" ]]; then
    replace_value "$key" "$value"
  fi
}

ensure_value FILES_DOMAIN files.aipupu.cloud
ensure_value OCR_PROVIDER rapidocr
ensure_value OCR_STORAGE_PROVIDER s3
ensure_value OCR_JOB_RETENTION_HOURS 24
ensure_value OCR_QUEUE ocr
ensure_value S3_INTERNAL_ENDPOINT http://minio:9000
ensure_value S3_PUBLIC_ENDPOINT https://files.aipupu.cloud
ensure_value S3_BUCKET smart-reminder-private
ensure_value S3_REGION us-east-1
ensure_value S3_ADDRESSING_STYLE path

if [[ -z "$(get_value DEEPSEEK_API_KEY)" ]]; then
  printf 'DeepSeek API key: ' >&2
  IFS= read -r -s deepseek_key
  printf '\n' >&2
  replace_value DEEPSEEK_API_KEY "$deepseek_key"
  unset deepseek_key
fi
if [[ -z "$(get_value CERTBOT_EMAIL)" ]]; then
  printf 'Certbot email: ' >&2
  IFS= read -r certbot_email
  replace_value CERTBOT_EMAIL "$certbot_email"
  unset certbot_email
fi
if [[ -z "$(get_value MINIO_ROOT_USER)" ]]; then
  replace_value MINIO_ROOT_USER "minio-root-$(openssl rand -hex 4)"
fi
if [[ -z "$(get_value MINIO_ROOT_PASSWORD)" ]]; then
  replace_value MINIO_ROOT_PASSWORD "$(openssl rand -hex 32)"
fi
if [[ -z "$(get_value S3_ACCESS_KEY_ID)" ]]; then
  replace_value S3_ACCESS_KEY_ID "sr-app-$(openssl rand -hex 4)"
fi
if [[ -z "$(get_value S3_SECRET_ACCESS_KEY)" ]]; then
  replace_value S3_SECRET_ACCESS_KEY "$(openssl rand -hex 32)"
fi

python3 "$VALIDATOR" "$ENV_FILE" >/dev/null
echo "Production secrets configured and validated"
```

The script upgrades an existing pre-MinIO production file with fixed non-secret defaults, reads the file as text, never sources it, never passes secrets to child-process arguments, and preserves mode `600`.

Add a static contract test to `test_operations_scripts.py` asserting the script contains `read -r -s`, `mktemp`, `chmod 600`, and `check_env.py`, and does not contain `source "$ENV_FILE"`, `set -x`, or `echo "$DEEPSEEK_API_KEY"`.

- [ ] **Step 6: Verify environment and shell contracts**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_env_contract.py \
  backend/tests/deployment/test_operations_scripts.py -q
bash -n deploy/tencent/scripts/configure_secrets.sh
```

Expected: all tests pass and Bash syntax exits `0`.

- [ ] **Step 7: Commit the environment contract**

```bash
git add deploy/tencent/env.production.example deploy/tencent/scripts/check_env.py \
  deploy/tencent/scripts/configure_secrets.sh \
  backend/tests/deployment/test_env_contract.py \
  backend/tests/deployment/test_operations_scripts.py
git commit -m "ops: validate private MinIO production secrets"
```

### Task 4: Add Private MinIO Initialization and the Production OCR Worker

**Files:**
- Create: `deploy/tencent/minio/app-policy.json`
- Create: `deploy/tencent/scripts/init_minio.sh`
- Modify: `deploy/tencent/compose.production.yaml`
- Modify: `deploy/tencent/scripts/deploy.sh`
- Modify: `backend/tests/deployment/test_compose_contract.py`
- Modify: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Write failing Compose and initialization tests**

Add assertions to `backend/tests/deployment/test_compose_contract.py`:

```python
def test_minio_is_private_initialized_and_not_profile_gated():
    services = load_production_compose()["services"]
    assert services["minio"]["ports"] == []
    assert not services["minio"].get("profiles")
    assert services["minio-init"]["depends_on"]["minio"]["condition"] == "service_healthy"
    assert services["minio-init"]["restart"] == "no"


def test_ocr_worker_is_isolated_and_resource_limited():
    service = load_production_compose()["services"]["ocr-worker"]
    assert service["image"].startswith("smart-reminder-ocr:")
    assert "-Q ocr" in service["command"]
    assert "--concurrency=1" in service["command"]
    assert service["cpus"] == 1.0
    assert service["mem_limit"] == "1200m"
    assert service["ports"] == []
```

Add operation tests asserting `deploy.sh` builds `ocr-worker`, starts `minio`, runs `minio-init`, migrates, then starts `ocr-worker`.

- [ ] **Step 2: Run the contracts and verify failure**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_compose_contract.py \
  backend/tests/deployment/test_operations_scripts.py -q
```

Expected: FAIL because `minio-init` and production `ocr-worker` do not exist.

- [ ] **Step 3: Create the least-privilege MinIO policy**

Create `deploy/tencent/minio/app-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::smart-reminder-private"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::smart-reminder-private/ocr/tmp/*"]
    }
  ]
}
```

- [ ] **Step 4: Create the idempotent MinIO initializer**

Create `deploy/tencent/scripts/init_minio.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

: "${S3_INTERNAL_ENDPOINT:?S3_INTERNAL_ENDPOINT is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"

mc alias set private "$S3_INTERNAL_ENDPOINT" \
  "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "private/$S3_BUCKET"
mc anonymous set none "private/$S3_BUCKET"
if ! mc admin user info private "$S3_ACCESS_KEY_ID" >/dev/null 2>&1; then
  mc admin user add private "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY"
fi
mc admin policy create private smart-reminder-ocr /config/app-policy.json
mc admin policy attach private smart-reminder-ocr \
  --user "$S3_ACCESS_KEY_ID"

if ! mc ilm rule ls --json "private/$S3_BUCKET" \
  | grep -Fq 'ocr/tmp/'; then
  mc ilm rule add --expire-days 1 --prefix 'ocr/tmp/' \
    "private/$S3_BUCKET"
fi
```

The script must not print credentials, enable tracing, expose the Console, or set anonymous access.

- [ ] **Step 5: Define production services and environment**

In `deploy/tencent/compose.production.yaml`:

- Add all OCR and S3 application variables to `x-backend-environment`.
- Give `minio` only root credentials, clear its host ports, add a health check, and reset the local-only profile.
- Add `minio-init` using a pinned `minio/mc` image, mount the policy and initializer read-only, pass both credential sets, depend on healthy MinIO, and use `restart: "no"`.
- Add `ocr-worker` using `smart-reminder-ocr:${APP_VERSION}`, `backend/Dockerfile.ocr`, no ports, queue `ocr`, concurrency `1`, prefetch `1`, `cpus: 1.0`, `mem_reservation: 700m`, `mem_limit: 1200m`, and `restart: unless-stopped`.
- Make API and OCR Worker depend on successful `minio-init`; keep ordinary Worker restricted to queue `celery`.

- [ ] **Step 6: Update release ordering and OCR smoke check**

Update `deploy/tencent/scripts/deploy.sh` so the relevant sequence is:

```bash
"${COMPOSE[@]}" build api ocr-worker
"${COMPOSE[@]}" up -d postgres redis minio
"${COMPOSE[@]}" run --rm minio-init
"${COMPOSE[@]}" run --rm api python manage.py migrate --noinput
"${COMPOSE[@]}" run --rm ocr-worker python manage.py check_ocr \
  backend/tests/ocr/fixtures/medicine_front.jpg
"${COMPOSE[@]}" up -d api worker ocr-worker beat
```

Do not print Compose environment output. Keep the existing clean-SHA and API health gates.

- [ ] **Step 7: Verify Compose, scripts, and focused tests**

Run with non-secret test values supplied only to the command environment:

```bash
APP_VERSION=test DJANGO_SECRET_KEY=test POSTGRES_PASSWORD=test \
DEEPSEEK_API_KEY=test CERTBOT_EMAIL=owner@example.com \
S3_ACCESS_KEY_ID=test-app S3_SECRET_ACCESS_KEY=test-secret \
MINIO_ROOT_USER=test-root MINIO_ROOT_PASSWORD=test-root-secret \
docker compose -f compose.yaml -f deploy/tencent/compose.production.yaml \
  config --quiet
.venv/bin/pytest backend/tests/deployment/test_compose_contract.py \
  backend/tests/deployment/test_operations_scripts.py -q
bash -n deploy/tencent/scripts/init_minio.sh
bash -n deploy/tencent/scripts/deploy.sh
```

Expected: Compose config and all tests/syntax checks exit `0`.

- [ ] **Step 8: Commit the private storage stack**

```bash
git add deploy/tencent/minio/app-policy.json deploy/tencent/scripts/init_minio.sh \
  deploy/tencent/compose.production.yaml deploy/tencent/scripts/deploy.sh \
  backend/tests/deployment/test_compose_contract.py \
  backend/tests/deployment/test_operations_scripts.py
git commit -m "ops: run private MinIO and isolated OCR worker"
```

### Task 5: Add Dual-Domain TLS and PUT-Only Nginx Routing

**Files:**
- Modify: `deploy/tencent/nginx/bootstrap.conf`
- Modify: `deploy/tencent/nginx/aipupu.cloud.conf`
- Modify: `deploy/tencent/scripts/bootstrap_tls.sh`
- Modify: `backend/tests/deployment/test_compose_contract.py`
- Modify: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Write failing Nginx and certificate tests**

Extend deployment tests with exact assertions:

```python
def test_file_domain_is_put_only_and_does_not_log_signatures():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    assert "server_name files.aipupu.cloud;" in config
    assert "proxy_pass http://minio:9000;" in config
    assert "proxy_set_header Host $http_host;" in config
    assert "limit_except PUT" in config
    assert "access_log off;" in config
    assert "client_max_body_size 9m;" in config


def test_tls_bootstrap_requests_both_domains():
    script = (SCRIPTS / "bootstrap_tls.sh").read_text()
    assert 'FILES_DOMAIN=$(python3 "$VALIDATOR" "$ENV_FILE" --get FILES_DOMAIN)' in script
    assert '--domain "$DOMAIN"' in script
    assert '--domain "$FILES_DOMAIN"' in script
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_compose_contract.py \
  backend/tests/deployment/test_operations_scripts.py -q
```

Expected: FAIL because only `aipupu.cloud` is configured.

- [ ] **Step 3: Expand the ACME bootstrap server**

Set `server_name aipupu.cloud files.aipupu.cloud;` in `bootstrap.conf`. Keep only the ACME location; every other request returns `503`.

- [ ] **Step 4: Add the file HTTPS server**

Keep the current API HTTP/HTTPS servers and add file-domain HTTP redirect plus a file HTTPS server with:

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name files.aipupu.cloud;

    ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/aipupu.cloud/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 9m;
    access_log off;

    location / {
        limit_except PUT { deny all; }
        proxy_pass http://minio:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 5s;
        proxy_read_timeout 65s;
        proxy_request_buffering off;
    }
}
```

Do not add a Console route, generic GET proxy, directory page, or log format containing `$args` or `$request_uri`.

- [ ] **Step 5: Request both certificate names**

Read `FILES_DOMAIN` through `check_env.py --get` and add a second `--domain "$FILES_DOMAIN"` to the Certbot command.

- [ ] **Step 6: Verify tests and Nginx syntax**

Run:

```bash
.venv/bin/pytest backend/tests/deployment -q
bash -n deploy/tencent/scripts/bootstrap_tls.sh
```

Expected: deployment tests and Bash syntax pass. Production Nginx syntax is checked on the server immediately after the two-domain certificate exists in Task 9; static tests cover the local pre-certificate configuration.

- [ ] **Step 7: Commit the public upload edge**

```bash
git add deploy/tencent/nginx/bootstrap.conf \
  deploy/tencent/nginx/aipupu.cloud.conf \
  deploy/tencent/scripts/bootstrap_tls.sh \
  backend/tests/deployment/test_compose_contract.py \
  backend/tests/deployment/test_operations_scripts.py
git commit -m "ops: expose signed OCR uploads over HTTPS"
```

### Task 6: Keep Cleanup Progressing When One Object Fails

**Files:**
- Modify: `backend/apps/ocr/services/retention.py`
- Modify: `backend/tests/ocr/services/test_retention.py`
- Modify: `backend/config/settings.py`

- [ ] **Step 1: Write a failing partial-failure cleanup test**

Add:

```python
@pytest.mark.django_db
def test_purge_continues_after_one_expired_job_fails(user):
    failed = OCRJob.objects.create(user=user, image_keys={"front": "bad"})
    removed = OCRJob.objects.create(user=user, image_keys={"front": "good"})
    OCRJob.objects.filter(id__in=[failed.id, removed.id]).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )
    storage = FakeStorage(fail_on="bad")

    assert purge_expired_images(storage=storage) == 1

    failed.refresh_from_db()
    removed.refresh_from_db()
    assert failed.image_keys == {"front": "bad"}
    assert removed.image_keys == {}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/services/test_retention.py -q
```

Expected: FAIL because the current loop stops after the first deletion exception.

- [ ] **Step 3: Isolate failures per expired job**

Update `purge_expired_images()` so it orders IDs for deterministic progress, catches each deletion error, continues, and returns only successful deletions:

```python
import logging


logger = logging.getLogger(__name__)


def purge_expired_images(*, storage):
    job_ids = list(
        OCRJob.objects.filter(expires_at__lte=timezone.now())
        .exclude(image_keys={})
        .order_by("created_at")
        .values_list("id", flat=True)
    )
    deleted = 0
    for job_id in job_ids:
        try:
            delete_job_images(job_id, storage=storage)
        except Exception:
            logger.warning(
                "image_delete_failed job_id=%s error_code=image_delete_failed",
                job_id,
            )
            continue
        deleted += 1
    return deleted
```

Do not log object keys or recognized text in this service; only job ID and the fixed error code are allowed.

- [ ] **Step 4: Verify confirmation and expiry cleanup together**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/api/test_ocr_confirmation.py \
  backend/tests/ocr/services/test_retention.py backend/tests/ocr/test_tasks.py -q
```

Expected: confirmation schedules deletion, expired jobs are purged, failures retain keys for retry, and no recognized text appears in logs.

- [ ] **Step 5: Commit the cleanup resilience change**

```bash
git add backend/apps/ocr/services/retention.py \
  backend/tests/ocr/services/test_retention.py backend/config/settings.py
git commit -m "test: lock OCR image retention behavior"
```

### Task 7: Update Runbooks and Developer Configuration

**Files:**
- Modify: `README.md`
- Modify: `.env.example`
- Modify: `deploy/tencent/README.md`
- Modify: `docs/local-development.mmd`
- Modify: `docs/architecture.mmd`
- Modify: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Write a failing runbook contract**

Extend `test_runbook_covers_security_release_backup_and_rollback()` with:

```python
for required in (
    "files.aipupu.cloud",
    "S3_INTERNAL_ENDPOINT",
    "S3_PUBLIC_ENDPOINT",
    "configure_secrets.sh",
    "MinIO Console",
    "24 小时",
    "check_ocr",
):
    assert required in runbook
```

- [ ] **Step 2: Run the contract and verify failure**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q
```

Expected: FAIL on the missing OCR/MinIO deployment instructions.

- [ ] **Step 3: Document local and production endpoint behavior**

Update the root README and `.env.example` with both endpoint names. State that Docker-internal reads use `http://minio:9000`, Mac browser uploads can use `http://localhost:9000`, and iPhone local uploads require the Mac LAN address.

- [ ] **Step 4: Document the production procedure**

Update `deploy/tencent/README.md` with exact sections for:

- `files.aipupu.cloud` DNS A record and verification.
- Interactive `configure_secrets.sh` usage without showing values.
- Two-domain TLS bootstrap.
- Private MinIO and absence of public `9000/9001` or Console.
- Deployment order and OCR smoke command.
- Confirmation-time deletion, 24-hour target, lifecycle fallback, and outage caveat.
- Failure recovery: stop OCR Worker while leaving core reminder API online.

Update Mermaid architecture/local-development diagrams to show Nginx routing the file hostname to MinIO and OCR Worker using the internal endpoint.

- [ ] **Step 5: Verify documentation contracts and formatting**

Run:

```bash
.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q
rg -n 'S3_ENDPOINT=' README.md .env.example deploy/tencent/README.md
git diff --check
```

Expected: tests pass, no documentation instructs production users to set only legacy `S3_ENDPOINT`, and diff check exits `0`.

- [ ] **Step 6: Commit documentation**

```bash
git add README.md .env.example deploy/tencent/README.md \
  docs/local-development.mmd docs/architecture.mmd \
  backend/tests/deployment/test_operations_scripts.py
git commit -m "docs: add private MinIO OCR deployment runbook"
```

### Task 8: Run the Full Local Release Gate

**Files:**
- Verify: all integrated application and deployment files

- [ ] **Step 1: Make the Flutter toolchain available without committing it**

Run only if `.tools` is absent:

```bash
ln -s ../smart-reminder/.tools .tools
```

Expected: `.tools` remains ignored by Git and `scripts/flutterw --version` exits `0`.

- [ ] **Step 2: Run backend and migration gates**

```bash
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py check
.venv/bin/python backend/manage.py makemigrations --check --dry-run
```

Expected: all backend tests pass, Django reports no issues, and no migration changes are detected.

- [ ] **Step 3: Run Flutter gates**

```bash
make flutter-analyze
make flutter-test
```

Expected: Flutter analysis has no issues and all 16 widget/unit tests pass.

- [ ] **Step 4: Run Compose and script gates**

```bash
make test-deployment
APP_VERSION=test DJANGO_SECRET_KEY=test POSTGRES_PASSWORD=test \
DEEPSEEK_API_KEY=test CERTBOT_EMAIL=owner@example.com \
S3_ACCESS_KEY_ID=test-app S3_SECRET_ACCESS_KEY=test-secret \
MINIO_ROOT_USER=test-root MINIO_ROOT_PASSWORD=test-root-secret \
docker compose -f compose.yaml -f deploy/tencent/compose.production.yaml \
  config --quiet
```

Expected: deployment tests, Bash syntax, and Compose rendering all pass.

- [ ] **Step 5: Run a real local OCR model smoke test**

```bash
PYTHONPATH=backend .venv/bin/python backend/manage.py check_ocr \
  backend/tests/ocr/fixtures/medicine_front.jpg
```

Expected: output contains `OCR smoke check passed`, a positive line count, and elapsed milliseconds, but no recognized medicine text.

- [ ] **Step 6: Inspect the final change set and commit any release-gate fix**

```bash
git status --short
git diff --check
git log --oneline --decorate -8
```

Expected: no uncommitted tracked changes and the recent commits correspond to Tasks 1-7.

### Task 9: Push, Configure DNS, and Deploy the Reviewed Commit

**Files:**
- Server file: `/opt/smart-reminder/shared/.env.production`
- Server checkout: `/opt/smart-reminder/app`

- [ ] **Step 1: Push the reviewed integration branch**

```bash
git push -u origin feature/tencent-ocr-minio-integration
```

Expected: GitHub reports the branch updated to the exact locally reviewed commit.

- [ ] **Step 2: Add and verify the file-domain DNS record**

Create an A record with host `files`, the same server address as the apex record, and TTL `600`. Then run:

```bash
dig +short files.aipupu.cloud @1.1.1.1
dig +short files.aipupu.cloud @8.8.8.8
```

Expected: both return the same address as `aipupu.cloud`; do not start TLS bootstrap until they match.

- [ ] **Step 3: Update the server checkout to the reviewed SHA**

```bash
ssh -t -i ~/.ssh/id_ed25519_smart_reminder \
  -o IdentitiesOnly=yes ubuntu@aipupu.cloud
cd /opt/smart-reminder/app
git fetch origin
git checkout feature/tencent-ocr-minio-integration
git pull --ff-only
DEPLOY_SHA=$(git rev-parse HEAD)
git status --short
```

Expected: status is clean and `DEPLOY_SHA` matches the local reviewed commit.

- [ ] **Step 4: Configure secrets interactively on the server**

```bash
./deploy/tencent/scripts/configure_secrets.sh \
  /opt/smart-reminder/shared/.env.production
```

Expected: the script prompts without echoing the DeepSeek key, generates distinct MinIO credentials when absent, validates the file, and prints only its fixed success message.

- [ ] **Step 5: Issue the two-domain certificate**

```bash
./deploy/tencent/scripts/bootstrap_tls.sh \
  /opt/smart-reminder/shared/.env.production
```

Expected: Certbot succeeds for `aipupu.cloud` and `files.aipupu.cloud`.

- [ ] **Step 6: Validate the certificate-backed Nginx configuration**

```bash
export APP_VERSION=preflight
docker compose \
  --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  --profile production run --rm --no-deps nginx nginx -t
```

Expected: Nginx prints `syntax is ok` and `test is successful` while loading the two-domain certificate.

- [ ] **Step 7: Deploy the exact commit**

```bash
./deploy/tencent/scripts/deploy.sh \
  "$DEPLOY_SHA" \
  /opt/smart-reminder/shared/.env.production
```

Expected: images build, MinIO initializes privately, migrations apply, OCR smoke passes, services become healthy, and Nginx starts.

- [ ] **Step 8: Run public and isolation acceptance checks**

```bash
curl --fail --silent https://aipupu.cloud/api/v1/health
curl --head --silent https://files.aipupu.cloud/
docker compose --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml -f deploy/tencent/compose.production.yaml ps
```

Expected: API returns the health JSON, unsigned file GET is denied, and PostgreSQL/Redis/API/Workers/Beat/MinIO/Nginx are healthy. Host ports `5432`, `6379`, `8000`, `9000`, and `9001` are absent.

- [ ] **Step 9: Complete the iPhone OCR acceptance flow**

On the iPhone, request upload grants for front/expiry photos and verify both returned URL hosts equal `files.aipupu.cloud`. Upload, create the job, wait for candidates, edit any incorrect field, and confirm. Verify that inventory is created only after confirmation and both MinIO objects are deleted afterward.

- [ ] **Step 10: Harden SSH after deployment access is reconfirmed**

Keep one SSH session open, validate `/etc/ssh/sshd_config.d/99-smart-reminder.conf` contains `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`, and `PermitRootLogin no`, then run:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

Open a second key-only session before closing the first. Change the previously exposed account password with `sudo passwd ubuntu`; never transmit the replacement through chat or logs.
