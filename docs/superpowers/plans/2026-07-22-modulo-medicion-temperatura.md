# Temperature Measurement Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Temperature beside Vibration and Equipment Replacement, with guided °C capture, offline storage, API and USB synchronization, and history.

**Architecture:** Keep temperature models, persistence, endpoints, and capture state separate from vibration. Reuse the equipment visual resolver and point viewer, while a temperature plan maps each physical location to `T1` through `T10`.

**Tech Stack:** Flutter/Dart, sqflite, FastAPI/Pydantic, MariaDB/PyMySQL, Python sqlite3, flutter_test, unittest.

## Global Constraints

- Record one manual °C value per physical point.
- Map equipment point codes to the approved `T1` through `T10` columns.
- Include `T10` for the FIN-FAN belt.
- Save locally before any network synchronization.
- Keep Vibration behavior unchanged.
- Store `ODT` as null when the app has no value.
- No Git commit steps can run because the workspace has no `.git` repository.

### Task 1: Temperature domain model and point plan

**Files:**
- Create: `lib/models/temperature_measurement.dart`
- Create: `test/temperature_measurement_test.dart`
- Modify: `lib/models/models.dart`

**Interfaces:**
- Produces: `TemperatureStep`, `TemperaturePlanResolver.fromPuntos(int)`, `TemperatureMeasurement.fromMap`, `TemperatureMeasurement.toDbMap`, and `TemperatureReading.fromJson`
- Consumes: `PuntoCapturaConfig` and the approved point-to-column mapping

- [ ] Write tests asserting codes `1,2,3,7,8,9` map to `T1,T2,T5,T6`, code `4` maps to `T1,T2,T9,T10`, code `5` maps to `T1,T2,T7,T8`, and code `6` maps to `T1` through `T6`.
- [ ] Run `flutter test test/temperature_measurement_test.dart` and confirm failure because the temperature types do not exist.
- [ ] Implement immutable models, decimal parsing for comma and point, DB serialization, JSON parsing, and the resolver.
- [ ] Export the new model from `models.dart` or import it directly where needed.
- [ ] Run `dart format lib/models/temperature_measurement.dart test/temperature_measurement_test.dart` and rerun the focused test.

### Task 2: SQLite temperature storage

**Files:**
- Modify: `lib/db/db_helper.dart`
- Create: `test/temperature_db_mapping_test.dart`

**Interfaces:**
- Produces: `insertTemperature`, `updateTemperature`, `getPendingTemperatures`, `getLocalTemperatures`, `upsertLatestTemperature`, and `getLatestTemperature`
- Consumes: `TemperatureMeasurement` and `TemperatureReading`

- [ ] Write mapping tests for all local fields, nullable `odt`, synchronization state, and `T1` through `T10`.
- [ ] Run the focused test and confirm it fails because storage methods and schema are absent.
- [ ] Add `TEMPERATURAS_LOCAL` and `ULTIMA_TEMPERATURA` to `_ensureSchema`; include indexes for pending rows and latest lookup.
- [ ] Implement insert, update, pending query, local history query, latest upsert, and latest lookup.
- [ ] Run the focused model/storage tests and the existing DB-related tests.

### Task 3: Temperature capture screen

**Files:**
- Create: `lib/screens/temperature_capture_screen.dart`
- Create: `test/temperature_capture_screen_test.dart`
- Reuse: `lib/widgets/equipo_punto_viewer.dart`

**Interfaces:**
- Produces: `TemperatureCaptureScreen(equipo: Equipo)` returning `true` after local save
- Consumes: `TemperaturePlanResolver`, `DbHelper`, `ApiService`, `EquipoVisualResolver`, SharedPreferences operator data

- [ ] Write widget tests for one °C field per step, no H/V/A controls, required numeric input, FIN-FAN `T10`, next/previous navigation, exit confirmation, and one final save.
- [ ] Run the focused widget test and confirm it fails because the screen is absent.
- [ ] Implement guided capture with numeric keyboard, comma normalization, previous temperature display, point image, progress, observation dialog, local-first save, synchronization attempt, and duplicate-submit guard.
- [ ] Run `dart format` on the screen and test, then rerun the focused tests.

### Task 4: Operation selector with three sequential operations

**Files:**
- Modify: `lib/models/operation_flow.dart`
- Modify: `lib/screens/operation_selection_screen.dart`
- Modify: `test/operation_flow_test.dart`
- Modify: `test/operation_selection_screen_test.dart`

**Interfaces:**
- Produces: `OperationType.temperature` and a queue that can execute every selected operation in the chosen order
- Consumes: `TemperatureCaptureScreen`

- [ ] Extend tests to find Vibración, Medición de temperatura, and Reemplazo de equipo; assert Temperature launches with the same `Equipo`.
- [ ] Add flow tests for three selected operations and ordered continuation.
- [ ] Run both tests and confirm expected failures for the missing enum and tile.
- [ ] Add the enum, temperature tile, launch routing, order selection, and a continuation loop that supports one to three operations.
- [ ] Rerun selector and flow tests.

### Task 5: API payload and FastAPI endpoints

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `Api_scv_ptbg.py`
- Modify: `test/api_service_payload_test.dart`
- Modify: `test_api_replacements.py`

**Interfaces:**
- Produces: `buildTemperatureSyncPayload`, `ApiService.syncTemperature`, `ApiService.fetchLatestTemperature`, `POST /temperaturas`, `GET /temperaturas`, `GET /temperaturas/ultimas`, and `GET /temperaturas/ultima/{localizacion}`
- Consumes: `TemperatureMeasurement` and MariaDB table `MOT_TEMP_MUES`

- [ ] Write Dart payload tests for uppercase server columns and nullable `ODT`.
- [ ] Write Python tests for request validation, insert column order, latest-row selection, and JSON response mapping.
- [ ] Run the focused Dart and Python tests and confirm they fail for missing temperature functions.
- [ ] Add Pydantic request/response models, SQL constants, endpoints, and Dart client methods.
- [ ] Rerun the focused tests.

### Task 6: USB synchronization

**Files:**
- Modify: `tablet_uploader.py`
- Modify: `test_tablet_uploader.py`

**Interfaces:**
- Produces: `fetch_pending_temperatures`, `upload_temperature_rows`, `mark_temperature_result`, and `sync_latest_temperatures_from_mariadb`
- Consumes: `TEMPERATURAS_LOCAL`, `ULTIMA_TEMPERATURA`, and `MOT_TEMP_MUES`

- [ ] Write tests for local schema compatibility, pending-row mapping, duplicate detection by localización/fecha/hora, insert values, success marking, error marking, and latest-temperature cache refresh.
- [ ] Run `python -m unittest test_tablet_uploader.py -v` and confirm the new tests fail for missing functions.
- [ ] Implement temperature schema guards, upload helpers, MariaDB SQL, latest download, and summary merging.
- [ ] Include temperature counts and results in manual and device USB flows.
- [ ] Rerun the Python uploader tests.

### Task 7: Temperature history

**Files:**
- Modify: `lib/screens/mediciones_screen.dart`
- Create: `test/temperature_history_test.dart`

**Interfaces:**
- Produces: a Vibración/Temperatura type filter and temperature cards with °C values
- Consumes: local temperature rows and remote/latest cache data from `DbHelper` and `ApiService`

- [ ] Write widget tests that switch to Temperature, display applicable `T` values in °C, show pending/synchronized state, and preserve Vibration history.
- [ ] Run the focused test and confirm it fails because the filter is absent.
- [ ] Add the measurement-type selector, temperature loading, refresh, empty, error, and card states without changing Vibration cards.
- [ ] Rerun history and existing measurement tests.

### Task 8: Full verification

**Files:**
- Verify all modified Dart and Python files

- [ ] Run `dart format --output=none --set-exit-if-changed lib test`.
- [ ] Run `flutter test` and confirm zero failures.
- [ ] Run `python -m unittest test_api_replacements.py test_tablet_uploader.py -v` and confirm zero failures.
- [ ] Run `flutter analyze` and confirm zero issues.
- [ ] Run `flutter build apk --release --target-platform android-arm64` and confirm exit code 0.
- [ ] Compare implementation against every criterion in `docs/superpowers/specs/2026-07-22-modulo-medicion-temperatura-design.md`.
