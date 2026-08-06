# Medicine Cabinet Expiry List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an authenticated user browse and search their medicine inventory, see expiry risk at a glance, and keep OCR capture as a separate first-class App destination.

**Architecture:** Django exposes an owner-scoped, cursor-paginated read API over `InventoryBatch`, with server-derived expiry state and deterministic expiry ordering. Flutter adds a focused medicine-cabinet domain model, API client, searchable refreshable list, and a third bottom-navigation destination while preserving the existing OCR flow.

**Tech Stack:** Django 5.2, Django REST Framework token authentication and cursor pagination, PostgreSQL/SQLite tests, Flutter 3.44, Material 3, `http`, pytest, Flutter widget tests.

---

### Task 1: Owner-Scoped Inventory API

**Files:**
- Create: `backend/apps/medicines/api/__init__.py`
- Create: `backend/apps/medicines/api/pagination.py`
- Create: `backend/apps/medicines/api/serializers.py`
- Create: `backend/apps/medicines/api/views.py`
- Create: `backend/apps/medicines/api/urls.py`
- Create: `backend/tests/medicines/api/test_inventory_batches.py`
- Modify: `backend/config/urls.py`

- [ ] **Step 1: Write failing API tests**

Create batches for two users and assert `GET /api/v1/inventory-batches` returns only the authenticated user's records, ordered by expiry with missing dates last. Freeze `timezone.localdate()` and assert serialized states are `expired`, `expiring_soon`, `valid`, and `unknown`. Add a search assertion covering medicine name, specification, and batch number, plus an anonymous `401` assertion.

- [ ] **Step 2: Run tests and verify RED**

Run: `.venv/bin/pytest backend/tests/medicines/api/test_inventory_batches.py -q`

Expected: collection or `404` failure because the medicines API does not exist.

- [ ] **Step 3: Implement cursor pagination and serialization**

Use a `CursorPagination` subclass with `page_size = 50`, `ordering = ("expiry_sort", "id")`, and annotate the queryset with:

```python
expiry_sort=Coalesce("expiry_date", Value(date.max, output_field=DateField()))
```

Return this stable result shape:

```json
{
  "next": null,
  "previous": null,
  "results": [
    {
      "id": "batch-uuid",
      "medicine_id": "medicine-uuid",
      "medicine_name": "布洛芬胶囊",
      "specification": "0.3g*20粒",
      "batch_number": "20260108",
      "production_date": "2026-01-08",
      "expiry_date": "2028-05-31",
      "quantity": 2,
      "expiry_status": "valid",
      "days_until_expiry": 665
    }
  ]
}
```

The view must filter `medicine__owner=request.user`, accept a trimmed `q` query up to 100 characters, search name/specification/batch number with `icontains`, and use `select_related("medicine")`.

- [ ] **Step 4: Run API tests and verify GREEN**

Run: `.venv/bin/pytest backend/tests/medicines/api/test_inventory_batches.py -q`

Expected: all inventory API tests pass.

### Task 2: Flutter Inventory Domain And API Client

**Files:**
- Create: `app/lib/features/medicine_cabinet/domain/inventory_batch.dart`
- Create: `app/lib/features/medicine_cabinet/data/medicine_cabinet_api.dart`
- Create: `app/test/medicine_cabinet_api_test.dart`

- [ ] **Step 1: Write failing parsing and request tests**

Assert the client sends `GET /api/v1/inventory-batches?q=布洛芬` with the bearer token, parses nullable dates, and maps `expiry_status` into a Dart enum. Assert non-`200` responses throw `MedicineCabinetApiException`.

- [ ] **Step 2: Run tests and verify RED**

Run from `app/`: `../scripts/flutterw test test/medicine_cabinet_api_test.dart`

Expected: compilation fails because the domain model and API client do not exist.

- [ ] **Step 3: Implement the minimal client**

Define `InventoryExpiryStatus { expired, expiringSoon, valid, unknown }`, immutable `InventoryBatch`, and `InventoryBatchPage`. Implement `MedicineCabinetApi.listBatches({String query = "", Uri? pageUrl})`; only the first request constructs `q`, while later requests follow the server-provided HTTPS `next` URL.

- [ ] **Step 4: Run API client tests and verify GREEN**

Run from `app/`: `../scripts/flutterw test test/medicine_cabinet_api_test.dart`

Expected: all API client tests pass.

### Task 3: Searchable Medicine Cabinet UI

**Files:**
- Create: `app/lib/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart`
- Create: `app/test/medicine_cabinet_screen_test.dart`
- Modify: `app/lib/features/home/presentation/app_shell.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Cover loading, empty, error/retry, search submission, clear search, pull-to-refresh, expiry labels, and loading the next page. Update the shell test to require three destinations: `提醒`, `药箱`, and `拍照录入`.

- [ ] **Step 2: Run tests and verify RED**

Run from `app/`: `../scripts/flutterw test test/medicine_cabinet_screen_test.dart test/medicine_ocr_screen_test.dart`

Expected: compilation fails because the cabinet screen and third destination do not exist.

- [ ] **Step 3: Implement the list and navigation**

Render an unframed `ListView.separated` with medicine name, specification/batch secondary text, quantity, expiry date, and restrained status chips. Use a search field with search and clear icon buttons, `RefreshIndicator`, inline retry state, and a bottom progress row for cursor loading. Keep OCR as the separate `拍照录入` destination and inject one shared `MedicineCabinetApi` from `main.dart`.

- [ ] **Step 4: Run widget tests and verify GREEN**

Run from `app/`: `../scripts/flutterw test test/medicine_cabinet_screen_test.dart test/medicine_ocr_screen_test.dart`

Expected: all cabinet and navigation tests pass.

### Task 4: Release Gate And Production Deployment

**Files:**
- Modify: `README.md`
- Modify only other files required by failures introduced in Tasks 1-3.

- [ ] **Step 1: Document the inventory endpoint and App flow**

Add `GET /api/v1/inventory-batches` to the API table and state that the App now separates browsing from OCR capture.

- [ ] **Step 2: Run complete local verification**

Run:

```bash
.venv/bin/pytest backend/tests -q
.venv/bin/python backend/manage.py check
.venv/bin/python backend/manage.py makemigrations --check --dry-run
(cd app && ../scripts/flutterw test test)
(cd app && ../scripts/flutterw analyze)
(cd app && ../scripts/flutterw build ios --simulator --debug --dart-define=API_BASE_URL=https://aipupu.cloud)
git diff --check
```

Expected: all tests, analysis, checks, and simulator build exit `0`.

- [ ] **Step 3: Commit, synchronize `main`, and deploy by full SHA**

Stage only the plan-owned files, commit with `feat: add medicine cabinet expiry list`, synchronize GitHub `main`, and run `deploy/tencent/scripts/deploy.sh` on the server using the full commit SHA.

- [ ] **Step 4: Run production acceptance**

Create one temporary authenticated user and three inventory batches, call the public endpoint, verify owner isolation/search/expiry states, then delete the temporary records. Recheck public health, container status, Nginx syntax, and recent application errors.
