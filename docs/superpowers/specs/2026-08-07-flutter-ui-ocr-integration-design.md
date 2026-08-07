# Flutter UI And OCR Integration Design

## Goal

Make the redesigned Flutter application the authenticated client shell while preserving the existing inventory and OCR production APIs. Users can inspect real medicine batches in the new medicine cabinet, create an OCR job from the cabinet, review its candidate, explicitly confirm it, and then see the resulting inventory in the same UI.

## Scope

This integration starts from `main` and combines the completed UI branch with the existing authentication, authenticated HTTP client, inventory API, OCR API, image capture, and deployment configuration.

It does not change Django OCR behavior, storage, deployment topology, account policy, reminder backend endpoints, or add medical advice. Existing production APIs remain the source of truth. The new UI only presents typed projections of their responses.

## Architecture

`SmartReminderApp` retains `AuthController`, `AuthenticatedClient`, token storage, notification initialization, and API disposal from `main`. Once authenticated, it hosts the new adaptive `AppShell` instead of the legacy four-tab shell.

An `ApiMedicineRepository` adapts `MedicineCabinetApi` inventory-batch pages to the redesigned `MedicineRepository` models. It aggregates batches by medicine name and specification for the cabinet list, derives expiry status from the server-provided expiry date, and returns immutable detail data containing individual batches. Server deletion is exposed only through an injected async callback and never reports success before the API succeeds.

The cabinet's camera entry opens the existing `MedicineOcrScreen` as a route. That screen retains its two-photo capture, signed upload, job polling, candidate review, and explicit confirmation behavior. On its successful confirmation result, the route returns to the cabinet, which reloads inventory. OCR candidates never become medicine data without the existing confirm endpoint.

## UI And Navigation

The adaptive shell keeps three primary destinations: Today, Plans, and Medicine. Authentication/profile remains reachable from Settings, not a fourth product destination. The medicine header camera action is available only to authenticated users with a configured camera adapter. Permission denial stays explicit; unavailable capture remains disabled and does not invent medicine data.

The desktop 380dp list/detail layout and compact push-detail behavior remain unchanged. Real inventory can expose pagination internally, but the first integration loads a bounded first page and surfaces a retryable error rather than silently losing further data. Pagination support is added only when the typed repository contract grows an explicit load-more operation.

## Reminder And Authentication Compatibility

The redesigned quick-create and confirmation screens call the existing authenticated `ReminderDraftApi`. Their idempotent `ReminderCreationService` remains responsible for local notification scheduling retries. Authentication failures continue through `AuthenticatedClient` to the root `AuthController`; feature screens show unavailable/error states rather than bypassing authentication.

## Error Handling

HTTP/authentication failures map to retryable collection/detail errors without replacing existing cached content. OCR job failures stay within the OCR flow and leave the cabinet unchanged. A confirmed OCR result causes a cabinet reload; a reload failure is shown as an error with retry, never as a fake new medicine.

## Testing

Tests cover the API-to-repository mapping, expired and near-expiry aggregation, cabinet rendering of authenticated API data, OCR route launch and post-confirm refresh, unauthenticated shell routing, and retained reminder confirmation scheduling behavior. Existing Flutter UI golden and accessibility tests are regenerated only if integration changes their visible output. The complete Flutter test suite, analyzer, formatter check, and relevant backend OCR tests must pass before merge.

## Acceptance Criteria

- `main` authentication and deployment configuration remain intact.
- The new shell is used after successful authentication.
- The new cabinet reads real inventory through `AuthenticatedClient` and displays grouped medicine plus batch detail.
- Camera OCR enters the existing review-and-confirm flow; confirmation refreshes the cabinet.
- No OCR candidate, medicine batch, or notification is fabricated locally.
- No medical dosage or treatment advice is introduced.
