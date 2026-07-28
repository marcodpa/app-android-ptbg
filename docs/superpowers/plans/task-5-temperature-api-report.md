# Task 5 — Temperature API report

## Status

Implemented the temperature API payload, Dart client methods, FastAPI models,
MariaDB queries, and focused tests without changing vibration behavior.

## TDD evidence

- RED (Dart): `flutter test test/api_service_payload_test.dart` failed to
  compile because `buildTemperatureSyncPayload` did not exist.
- RED (Python): the new API tests initially referenced the absent
  `TemperatureReq` and temperature endpoint functions. The first executable
  Python run later also caught a test expectation that incorrectly assumed
  location order instead of newest-date order; the expectation was corrected.
- GREEN: the focused Dart payload/model suite and the Python temperature plus
  replacement-regression suite pass.

## Implemented contracts

### Dart

- `buildTemperatureSyncPayload` emits base request fields, uppercase
  administrative columns, every column from `T1` through `T10`, and nullable
  uppercase `ODT`.
- `ApiService.syncTemperature` posts to `/temperaturas`, retains the existing
  authentication/logout behavior, and returns `SyncResult`.
- `ApiService.fetchLatestTemperature` reads
  `/temperaturas/ultima/{localizacion}` and maps 404 to no prior reading.
- `ApiService.fetchLatestTemperatures` reads `/temperaturas/ultimas`.
- `ApiService.fetchTemperatureHistory` reads `/temperaturas`, optionally
  filtered by location.

### FastAPI / MariaDB

- `TemperatureReq` validates a positive location and decimal `T1`–`T10`
  values; `ODT` is nullable.
- `POST /temperaturas` inserts into `MOT_TEMP_MUES` in this order:
  `FECHA`, `HORA`, `SISTEMA`, `LOCALIZACION`, `T1`–`T10`,
  `OBSERVACIONES`, `USUARIO`, `CARGO`, `MARCA`, `MODELO`, `SERIAL`, `ODT`.
- `GET /temperaturas` returns newest-first history with optional location and
  limit filters.
- `GET /temperaturas/ultimas` selects one newest row per location using
  date/time and `ID` as the tie-breaker.
- `GET /temperaturas/ultima/{localizacion}` returns the newest row or 404.
- Decimal and date/time database values are mapped to JSON-safe values.

## Verification summary

- Dart formatting: no changes required after final format.
- Dart focused analysis: no issues found.
- Dart focused tests: 9 passed (payload and temperature model tests).
- Python syntax compilation: passed for API and temperature test files.
- Python focused/regression tests: 7 passed (4 temperature, 3 replacement).
- Existing vibration payload behavior remains covered by its original Dart
  payload test.

No commit was created because this workspace is not a Git repository.

## Reviewer corrections

The Important review findings were addressed in a second RED/GREEN cycle:

- `buildTemperatureSyncPayload` now emits `0.0` for every absent `T1`–`T10`
  value. `ODT` remains nullable.
- `TemperatureReq` now defaults omitted temperatures to `0.0` and normalizes
  explicitly null temperatures to `0.0`, so inserts into `MOT_TEMP_MUES` use
  `0.00` for non-applicable points.
- `GET /temperaturas` now applies its optional location filter, newest-first
  ordering, and `LIMIT` in MariaDB.
- `GET /temperaturas/ultima/{localizacion}` now applies newest-first ordering
  and `LIMIT 1` in MariaDB and reads only that row.
- `GET /temperaturas/ultimas` now uses `ROW_NUMBER() OVER (PARTITION BY
  LOCALIZACION ...)`, filters `rn = 1`, orders, and limits in MariaDB. It no
  longer loads the entire temperature table into Python.
- Tests now inspect route registration, SQL filters/order/limits/windowing,
  zero defaults, insert values, and nullable `ODT`.
- The existing `/mediciones` and `/ultimas-mediciones` vibration functions
  were reviewed and were not modified by these corrections.

Correction RED evidence:

- Dart: two expected failures showed absent temperatures were still null.
- Python: five expected failures showed null/default temperature values and
  missing SQL ordering, limiting, and window partitioning.

Correction GREEN evidence before final verification:

- Dart payload tests: 3 passed.
- Python temperature tests: 7 passed.

## Second reviewer correction

A further RED/GREEN cycle restored the exact legacy vibration query contract
and strengthened temperature synchronization:

- `GET /ultima-medicion/{localizacion}` again selects the row with
  `ORDER BY ID DESC LIMIT 1` directly in MariaDB.
- `GET /ultimas-mediciones` again returns the latest N rows globally with
  `ORDER BY ID DESC LIMIT %s`; it no longer groups rows per location in Python.
- `POST /temperaturas` is idempotent for the available table schema. Before
  insertion it checks `LOCALIZACION + FECHA + HORA`; an existing row returns
  `status: skipped`, `reason: already_exists`, and its existing ID without
  executing another insert.
- `GET /temperaturas/ultimas` and
  `GET /temperaturas/ultima/{localizacion}` now both require
  `Depends(verify_token)`.
- Regression tests assert both vibration SQL contracts, temperature retry
  behavior without a second insert, and authentication dependencies.

Second correction RED evidence:

- Four expected failures covered the missing duplicate guard, missing token
  dependencies, per-location vibration processing, and missing vibration SQL
  ordering/limit.

Second correction GREEN evidence before final verification:

- Python API tests: 11 passed.

## Final idempotency correction

The timestamp-only duplicate check was replaced because distinct samples can
legitimately share the same second:

- `POST /temperaturas` first loads candidate rows matching only
  `LOCALIZACION + FECHA + HORA`.
- A candidate is skipped only when its normalized sample signature also
  matches. The signature includes `T1`–`T10`, `SISTEMA`, `OBSERVACIONES`,
  `USUARIO`, `CARGO`, `MARCA`, `MODELO`, `SERIAL`, and nullable `ODT`.
- Temperature values are normalized to the table's two-decimal precision.
  Text is trimmed, repeated whitespace is collapsed, and case is normalized.
- A row with the same timestamp but a different temperature or relevant
  administrative value is inserted as a new measurement.

Final correction RED/GREEN evidence:

- RED: same timestamp with a different `T1` incorrectly returned `skipped`.
- GREEN: identical normalized data returns `skipped`, while different `T1`
  executes the insert; both focused tests pass.
