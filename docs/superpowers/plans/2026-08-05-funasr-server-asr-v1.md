# FunASR Server ASR V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iPhone-first voice input flow that records a short WAV file, transcribes it through a private FunASR service, places the editable transcript into the existing reminder composer, and preserves the existing confirmation boundary.

**Architecture:** Flutter owns microphone interaction and uploads one short WAV file to an authenticated Django endpoint. A focused `apps.voice` Django app validates the WAV contract, acquires a non-blocking Redis lease, calls a private FunASR HTTP provider, maps stable errors, and closes the upload without persisting audio or transcript. A separate CPU FunASR container normalizes accepted PCM WAV input to 16 kHz mono before inference; ordinary CI uses fakes and never downloads models.

**Tech Stack:** Python 3.13, Django 5.2, Django REST Framework 3.16, redis-py, httpx, pytest, FastAPI, FunASR 1.4.1, PyTorch/torchaudio, Flutter 3.44, Dart 3.12, `record` 7.1, `path_provider`, `package:http`.

---

## File Map

- `backend/apps/voice/domain/audio.py`: parse and validate untrusted PCM WAV metadata.
- `backend/apps/voice/domain/results.py`: provider result and stable exception types.
- `backend/apps/voice/providers/funasr.py`: multipart HTTP adapter for the private FunASR service.
- `backend/apps/voice/services/lease.py`: ownership-safe Redis lease for V1 global concurrency 1.
- `backend/apps/voice/services/transcription.py`: orchestrate validation, lease, provider call, and cleanup.
- `backend/apps/voice/api/serializers.py`: multipart upload serializer.
- `backend/apps/voice/api/throttles.py`: per-user and per-IP ASR request rates.
- `backend/apps/voice/api/views.py`: authenticated transcription endpoint and stable response mapping.
- `backend/apps/voice/api/urls.py`: `/api/v1/voice/transcriptions` route.
- `services/funasr/`: isolated model server, normalization, container, and health endpoint.
- `app/lib/features/voice_input/`: Flutter recorder, transcription API, and orchestration service.
- `app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart`: microphone controls and editable transcript insertion.

## Task 1: Backend Configuration And Dependency Boundary

**Files:**
- Modify: `backend/requirements/base.txt`
- Modify: `backend/config/settings.py`
- Modify: `.env.example`
- Create: `backend/apps/voice/__init__.py`
- Create: `backend/apps/voice/apps.py`
- Test: `backend/tests/voice/test_settings.py`

- [ ] **Step 1: Write failing settings tests**

```python
from django.conf import settings


def test_asr_defaults_are_safe_for_v1():
    assert settings.ASR_PROVIDER == "funasr"
    assert settings.ASR_MAX_AUDIO_BYTES == 4 * 1024 * 1024
    assert settings.ASR_MAX_REQUEST_BYTES == 5 * 1024 * 1024
    assert settings.ASR_MAX_DURATION_SECONDS == 20
    assert settings.ASR_GLOBAL_CONCURRENCY == 1
    assert settings.ASR_LEASE_TTL_SECONDS > settings.ASR_TIMEOUT_SECONDS
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/voice/test_settings.py -q`
Expected: FAIL because the ASR settings do not exist.

- [ ] **Step 3: Add the voice app, `httpx==0.28.1`, and environment-backed settings**

Add `apps.voice` to `INSTALLED_APPS`. Define `ASR_PROVIDER`, `ASR_BASE_URL`, `ASR_MODEL`, `ASR_TIMEOUT_SECONDS`, `ASR_MAX_AUDIO_BYTES`, `ASR_MAX_REQUEST_BYTES`, `ASR_MIN_DURATION_SECONDS`, `ASR_MAX_DURATION_SECONDS`, `ASR_GLOBAL_CONCURRENCY`, `ASR_CONCURRENCY_PER_USER`, `ASR_LEASE_TTL_SECONDS`, `ASR_USER_RATE`, and `ASR_IP_RATE`. Add matching documented values to `.env.example`.

Run: `.venv/bin/python -m pip install -r backend/requirements/dev.txt`
Expected: `httpx==0.28.1` installs successfully without changing the pinned Django stack.

- [ ] **Step 4: Run the test and Django check**

Run: `.venv/bin/pytest backend/tests/voice/test_settings.py -q && .venv/bin/python backend/manage.py check`
Expected: PASS and `System check identified no issues`.

## Task 2: PCM WAV Validation

**Files:**
- Create: `backend/apps/voice/domain/__init__.py`
- Create: `backend/apps/voice/domain/audio.py`
- Test: `backend/tests/voice/domain/test_audio.py`

- [ ] **Step 1: Write parameterized failing tests**

Generate WAV values with `wave.open(BytesIO(), "wb")`. Cover 8/16/44.1/48 kHz, mono/stereo, 16-bit PCM, invalid RIFF data, 8-bit samples, 7 kHz, 48,001 Hz, 0.2 seconds, 20.1 seconds, and files above 4 MiB. Assert a frozen `WavMetadata(sample_rate, channels, sample_width, frame_count, duration_ms)` for valid files and `AudioValidationError(code)` for invalid input.

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/voice/domain/test_audio.py -q`
Expected: FAIL because `apps.voice.domain.audio` does not exist.

- [ ] **Step 3: Implement strict metadata parsing**

Use the standard-library `wave` module. Reject compressed WAV, sample widths other than 2 bytes, channels outside 1-2, rates outside 8,000-48,000, duration outside configured bounds, and oversize files. Always restore the input stream position after inspection. Compute duration from `frame_count / sample_rate`; never accept client duration metadata.

- [ ] **Step 4: Run the validator tests**

Run: `.venv/bin/pytest backend/tests/voice/domain/test_audio.py -q`
Expected: all tests PASS.

## Task 3: FunASR Provider Contract

**Files:**
- Create: `backend/apps/voice/domain/results.py`
- Create: `backend/apps/voice/providers/__init__.py`
- Create: `backend/apps/voice/providers/funasr.py`
- Test: `backend/tests/voice/providers/test_funasr.py`

- [ ] **Step 1: Write failing provider tests**

Define a fake transport with `post_audio(url, audio, model, timeout_seconds)`. Verify the provider sends `/v1/audio/transcriptions`, returns a stripped transcript and provider latency, maps connection errors to `AsrUnavailableError`, timeouts to `AsrTimeoutError`, malformed JSON to `AsrResponseError`, and blank text to `EmptyTranscriptError`.

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/voice/providers/test_funasr.py -q`
Expected: FAIL because the provider does not exist.

- [ ] **Step 3: Implement the provider and HTTP transport**

Use `httpx.Client.post` with multipart field `file`, form fields `model` and `response_format=json`, and the configured timeout. The public provider signature is:

```python
class AsrProvider(Protocol):
    def transcribe(self, audio: BinaryIO, *, request_id: str) -> AsrResult: ...

@dataclass(frozen=True)
class AsrResult:
    transcript: str
    latency_ms: int
    provider: str
```

Do not log multipart bodies, transcript text, or raw FunASR responses.

- [ ] **Step 4: Run provider tests**

Run: `.venv/bin/pytest backend/tests/voice/providers/test_funasr.py -q`
Expected: all tests PASS.

## Task 4: Ownership-Safe Redis Lease

**Files:**
- Create: `backend/apps/voice/services/__init__.py`
- Create: `backend/apps/voice/services/lease.py`
- Test: `backend/tests/voice/services/test_lease.py`

- [ ] **Step 1: Write failing lease tests**

Use a fake Redis client supporting `set` and `eval`. Verify acquisition uses `NX` with a 25-second TTL, contention returns no lease, release supplies the unique owner token, and a stale owner cannot remove a replacement lease.

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/voice/services/test_lease.py -q`
Expected: FAIL because `RedisLeaseManager` does not exist.

- [ ] **Step 3: Implement the lease manager**

Acquire `voice:asr:global` with `SET key token NX EX ttl`. Release through one Lua compare-and-delete script. Represent an acquired lease as a context manager and never call unconditional `DEL`.

- [ ] **Step 4: Run lease tests**

Run: `.venv/bin/pytest backend/tests/voice/services/test_lease.py -q`
Expected: all tests PASS.

## Task 5: Transcription Service And Authenticated API

**Files:**
- Create: `backend/apps/voice/services/transcription.py`
- Create: `backend/apps/voice/api/__init__.py`
- Create: `backend/apps/voice/api/serializers.py`
- Create: `backend/apps/voice/api/throttles.py`
- Create: `backend/apps/voice/api/views.py`
- Create: `backend/apps/voice/api/urls.py`
- Modify: `backend/config/urls.py`
- Test: `backend/tests/voice/api/test_transcriptions.py`

- [ ] **Step 1: Write failing API tests**

Cover authentication, missing file, valid WAV success, computed `audio_duration_ms`, invalid WAV, oversize upload, global lease contention, empty transcript, unavailable provider, timeout, provider failure, per-user throttle, and uploaded-file closure. Inject fake provider and fake lease manager so tests do not require Redis or FunASR.

- [ ] **Step 2: Run the API tests and verify RED**

Run: `.venv/bin/pytest backend/tests/voice/api/test_transcriptions.py -q`
Expected: FAIL with a missing route or view.

- [ ] **Step 3: Implement orchestration and stable responses**

The view uses `IsAuthenticated`, `MultiPartParser`, `FormParser`, and both ASR throttles. On success return HTTP 200:

```json
{
  "request_id": "uuid",
  "status": "completed",
  "transcript": "明天早上七点提醒我吃药",
  "audio_duration_ms": 3800,
  "transcription_latency_ms": 920,
  "provider": "funasr"
}
```

Map format/duration errors to 400, empty text to 422, busy/rate limits to 429, unavailable to 503, and timeout to 504. Include `Retry-After: 2` for `asr_busy`. Close the uploaded file in `finally` on every path.

- [ ] **Step 4: Run focused and existing backend tests**

Run: `.venv/bin/pytest backend/tests/voice backend/tests/reminders -q`
Expected: all tests PASS.

## Task 6: Private FunASR Model Service

**Files:**
- Create: `services/funasr/requirements.txt`
- Create: `services/funasr/Dockerfile`
- Create: `services/funasr/app/__init__.py`
- Create: `services/funasr/app/audio.py`
- Create: `services/funasr/app/engine.py`
- Create: `services/funasr/app/main.py`
- Create: `services/funasr/tests/test_audio.py`
- Create: `services/funasr/tests/test_api.py`
- Modify: `compose.yaml`

- [ ] **Step 1: Write service tests with a fake engine**

Test 44.1/48 kHz and stereo normalization to a float32 16 kHz mono tensor, health before/after engine readiness, successful OpenAI-compatible transcription, oversize rejection, invalid audio rejection, and blank engine output. Model tests remain opt-in.

- [ ] **Step 2: Implement explicit normalization and the HTTP service**

Decode WAV with `soundfile`, average stereo channels, and use `torchaudio.functional.resample` when the input rate is not 16 kHz. Load `AutoModel(model="paraformer-zh", vad_model="fsmn-vad", punc_model="ct-punc", device="cpu", disable_update=True)` once at startup. Expose `GET /health` and `POST /v1/audio/transcriptions`; never log text or file contents.

- [ ] **Step 3: Add the private Compose service**

Build `services/funasr/Dockerfile`, use `restart: unless-stopped`, a persistent read-only-at-runtime model cache volume, healthcheck `/health`, no host `ports`, and backend environment `ASR_BASE_URL=http://funasr:8000`. Keep model/image versions pinned.

- [ ] **Step 4: Validate configuration and lightweight tests**

Run: `docker compose config`
Expected: exit 0 and no public port on `funasr`.

Run: `.venv/bin/pytest services/funasr/tests -q`
Expected: PASS when optional service test dependencies are installed; otherwise record the dependency blocker and rely on container build verification.

## Task 7: Flutter Multipart Transcription Client

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/pubspec.lock`
- Create: `app/lib/features/voice_input/domain/voice_transcription.dart`
- Create: `app/lib/features/voice_input/data/voice_transcription_api.dart`
- Test: `app/test/voice_transcription_api_test.dart`

- [ ] **Step 1: Add `record` and `path_provider`, then write failing API tests**

Verify bearer authentication, multipart field name `audio`, WAV content type, response parsing, and stable extraction of `code` from non-200 JSON responses.

- [ ] **Step 2: Run the test and verify RED**

Run: `cd app && ../scripts/flutterw test test/voice_transcription_api_test.dart`
Expected: FAIL because `VoiceTranscriptionApi` does not exist.

- [ ] **Step 3: Implement the client**

Use `http.MultipartRequest`, `http.MultipartFile.fromPath`, and `_client.send`. Define `VoiceTranscriptionApiException(statusCode, code)` and close only clients owned by the API.

- [ ] **Step 4: Run the client tests**

Run: `cd app && ../scripts/flutterw test test/voice_transcription_api_test.dart`
Expected: all tests PASS.

## Task 8: Flutter Recorder And Cleanup Service

**Files:**
- Create: `app/lib/features/voice_input/data/audio_recorder_gateway.dart`
- Create: `app/lib/features/voice_input/services/voice_input_service.dart`
- Test: `app/test/voice_input_service_test.dart`

- [ ] **Step 1: Write failing service tests**

Use fake recorder and transcription gateways. Verify permission denial, requested WAV/16 kHz/mono config, stop then upload, cancel, local-file deletion after success and failure, and disposal.

- [ ] **Step 2: Run the test and verify RED**

Run: `cd app && ../scripts/flutterw test test/voice_input_service_test.dart`
Expected: FAIL because the service does not exist.

- [ ] **Step 3: Implement the recorder gateway and service**

Use `AudioRecorder`, `RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)`, and `getTemporaryDirectory()`. Generate a UUID-like timestamp/random filename, never reuse user input in paths, and delete the file in `finally` after upload or on cancel.

- [ ] **Step 4: Run service tests**

Run: `cd app && ../scripts/flutterw test test/voice_input_service_test.dart`
Expected: all tests PASS.

## Task 9: Reminder Composer Voice Interaction

**Files:**
- Modify: `app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/reminder_composer_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Inject start, stop/transcribe, and cancel callbacks. Verify the microphone icon starts recording, stop triggers transcription, the transcript fills the existing editable `TextField`, duplicate parsing is disabled while recording/transcribing, cancel returns to idle, a 20-second timer auto-stops, permission/busy/timeout messages are stable, and text entry remains available after errors.

- [ ] **Step 2: Run widget tests and verify RED**

Run: `cd app && ../scripts/flutterw test test/reminder_composer_screen_test.dart`
Expected: FAIL because microphone controls do not exist.

- [ ] **Step 3: Implement stable controls and dependency wiring**

Use a 48px icon button with `Icons.mic_none`, switch to `Icons.stop` while recording, provide `Tooltip`, and show a cancel icon only while recording. Do not automatically create a reminder draft after transcription; populate the existing controller so the user can edit and explicitly tap `解析提醒`. Dispose timers, recorder, and API clients.

- [ ] **Step 4: Run Flutter tests and analysis**

Run: `cd app && ../scripts/flutterw test && ../scripts/flutterw analyze`
Expected: all tests PASS and analyzer reports no issues.

## Task 10: Integration Documentation And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-05-funasr-server-asr-design.md` only if implementation details require a factual correction

- [ ] **Step 1: Document local startup and model cost**

Add commands for building the FunASR service, first model download, API-only tests with fakes, real integration health checks, and iPhone launch. State that `docker compose up funasr api` may require several GB of model/runtime download and that the first ready state is slow.

- [ ] **Step 2: Run backend verification**

Run: `.venv/bin/pytest backend -q`
Expected: all tests PASS.

Run: `.venv/bin/python backend/manage.py check && .venv/bin/python backend/manage.py makemigrations --check --dry-run`
Expected: no issues and no new migrations.

- [ ] **Step 3: Run Flutter verification**

Run: `cd app && ../scripts/flutterw test && ../scripts/flutterw analyze && ../scripts/flutterw build ios --simulator --debug`
Expected: tests and analysis PASS; simulator build succeeds.

- [ ] **Step 4: Validate Compose and inspect exposure**

Run: `docker compose config`
Expected: exit 0; `api`, PostgreSQL, Redis, and MinIO keep their current development ports, while `funasr` has no host port.

- [ ] **Step 5: Record unrun real-model checks honestly**

If the full FunASR image/model cannot be downloaded in the environment, do not claim real transcription. Report that fake-provider contract, Compose structure, and client/server behavior passed, with real Mandarin accuracy/CER and p95 latency remaining a deployment verification item.
