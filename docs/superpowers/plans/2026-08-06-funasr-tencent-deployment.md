# FunASR Tencent Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the reviewed FunASR V1 implementation with the existing Tencent single-server deployment and release it to the current 4 vCPU / 4 GB internal-test host without deploying OCR.

**Architecture:** Main already contains the reviewed Tencent, FunASR, and OCR merge histories; this integration branch starts from main commit `0cbcc17` and must not repeat those merges. Keep FunASR private on the dedicated `asr_proxy` network, use one CPU inference process and one global request lease, give Nginx a fixed private address so Django can trust only that proxy, and make the release script initialize models and pass readiness before replacing the API. Preserve the existing HTTPS endpoint, OCR code, and production data volumes while putting MinIO, MinIO init, OCR Worker, and Beat behind the optional `ocr` profile.

**Tech Stack:** Docker Compose, FastAPI/FunASR, Django/Gunicorn, Redis, Nginx, Bash, pytest, Tencent Cloud Ubuntu.

---

### Task 1: Verify the main integration baseline

**Files:**
- Baseline: main commit `0cbcc17`
- Preserve: FunASR voice flow, Tencent deployment, OCR/MinIO integration, and Flutter behavior already merged to main
- Do not merge old feature branches again or alter Flutter UI in this production-only task

- [x] **Step 1: Confirm the reviewed histories are already in main**

Run: `git log --oneline -5`

Expected: main history includes the reviewed FunASR/Tencent and OCR preservation merges before `0cbcc17`.

- [x] **Step 2: Confirm the merged tree retains both features**

The resolved tree must contain `services/funasr/`, `backend/apps/voice/`, `deploy/tencent/`, the voice-input Flutter files, the Tencent production settings, and both deployment and FunASR tests.

- [x] **Step 3: Run the merged backend and lightweight FunASR suites**

Run:

```bash
.venv/bin/python -m pytest backend/tests services/funasr/tests -q
```

Expected: all tests pass.

- [x] **Step 4: Skip redundant merge resolution**

No merge commit is needed because the task starts from the merged main baseline.

### Task 2: Add production FunASR release contracts

**Files:**
- Modify: `backend/tests/deployment/test_compose_contract.py`
- Modify: `backend/tests/deployment/test_env_contract.py`
- Modify: `backend/tests/deployment/test_operations_scripts.py`
- Modify: `deploy/tencent/compose.production.yaml`
- Modify: `deploy/tencent/env.production.example`
- Modify: `deploy/tencent/scripts/check_env.py`
- Modify: `deploy/tencent/scripts/deploy.sh`
- Modify: `deploy/tencent/nginx/aipupu.cloud.conf`
- Modify: `deploy/tencent/README.md`

- [x] **Step 1: Write failing production contracts**

Add assertions that production publishes no FunASR port; rotates FunASR logs; uses a fixed private Nginx address matching `ASR_TRUSTED_PROXY_IPS`; passes all ASR settings to Django; gives FunASR a production image tag and release-script readiness gate; raises the Nginx upload limit above the Django multipart limit; and makes `deploy.sh` build the FunASR image, initialize its persistent model volume, start it, and wait for readiness before starting the application tier.

The contracts must also prove final base-plus-production semantics: MinIO, MinIO init, OCR Worker, and Beat are in the `ocr` profile; API has no OCR startup dependency; disabled OCR stops existing services without removing containers or volumes; the FunASR model volume is read-only for inference; Nginx has fixed address `172.29.0.10` on `172.29.0.0/24`; and the ordinary Celery Worker is fixed to concurrency/prefetch 1.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
.venv/bin/python -m pytest backend/tests/deployment -q
```

Expected: the new FunASR production assertions fail because the deployment overlay and release script do not yet contain those contracts.

- [x] **Step 3: Implement the minimum production integration**

Use `smart-reminder-funasr:${APP_VERSION}` for both model initialization and inference. Keep the model volume persistent and private; do not expose port 8000. Configure the complete ASR environment, one global and one per-user concurrent request, and the fixed Nginx proxy IP. The deploy sequence must validate configuration/revision/logging, capture the previous API image, build API and FunASR while the old API/Nginx stay live, start PostgreSQL/Redis, conditionally stop OCR services, check the pinned model marker, stop old FunASR before initializing a missing or stale cache with `--no-deps`, start FunASR with `--no-deps`, wait for `/health`, pass a real synthetic Mandarin WAV transcription, run candidate dependency preflight, migrate, then replace API/worker. Validate production Nginx in a one-off container before force-recreating the live proxy. If the new API health gate fails, retag the captured image and force-recreate API/worker. Only `OCR_ENABLED=true` starts the `ocr` profile and performs MinIO init plus OCR smoke before Nginx recreation.

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
.venv/bin/python -m pytest backend/tests/deployment -q
bash -n deploy/tencent/scripts/deploy.sh
```

Expected: all deployment tests pass and Bash syntax is valid.

- [x] **Step 5: Document 4 GB operation and rollback**

The runbook must state that OCR is excluded from this release, FunASR is single-concurrency, the first model download can take a long time, and operators must capture `docker stats`, `free -h`, disk usage, model readiness, transcription latency, and OOM evidence. On memory failure, keep the previous API release running and stop the new FunASR containers; do not delete database or model volumes.

- [x] **Step 6: Commit the production integration**

Run:

```bash
git add backend/tests/deployment deploy/tencent services/funasr docs/superpowers/plans/2026-08-06-funasr-tencent-deployment.md docs/superpowers/specs/2026-08-05-smart-reminder-v2-enhancements.md
git commit -m "fix: harden FunASR production rollout"
```

### Task 3: Verify and deploy the exact reviewed revision

**Files:**
- No production secret files are committed or printed.
- Remote checkout: `/opt/smart-reminder/app`
- Remote environment: `/opt/smart-reminder/shared/.env.production`

- [x] **Step 1: Run the complete local release gate**

Run backend, FunASR, Flutter tests, Flutter analyzer, Django checks, migration drift, deployment tests, Bash syntax checks, and `git diff --check`.

- [x] **Step 2: Review the integration diff**

Compare the integration branch with both parent feature branches. Fix all Critical or Important findings and rerun affected verification.

- [ ] **Step 3: Push the exact integration branch**

Run: `git push -u origin feature/funasr-tencent-deploy`

Expected: the server can fetch the reviewed commit by full SHA.

- [ ] **Step 4: Prepare the existing server without revealing secrets**

Verify the remote worktree is clean, fetch the branch, check out the exact integration commit, append only missing non-secret ASR variables to the mode-600 environment file, and validate it with `check_env.py`.

- [ ] **Step 5: Deploy and wait for real model readiness**

Run `deploy/tencent/scripts/deploy.sh FULL_SHA /opt/smart-reminder/shared/.env.production`. Do not interrupt model download or image build. If the 4 GB host OOMs, collect container status and memory evidence, stop only FunASR-related new containers, and restore the prior reviewed application commit.

- [ ] **Step 6: Run the server release gate**

Verify Compose configuration, private port exposure, Nginx syntax, public HTTPS health, FunASR health from inside the private network, one real short Mandarin WAV transcription, container restart recovery, memory/swap/disk use, and logs without transcript or audio content.

- [ ] **Step 7: Record measured capacity**

Record cold-start time, steady resident memory, peak memory during one request, transcription latency, and whether OOM or swap pressure occurred in the V2 enhancement document. Keep OCR deferred until the voice workflow has been accepted on a real iPhone.
