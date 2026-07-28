# Módulo de alineación de equipos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar una cuarta operación de Alineación con formulario dinámico, persistencia local, historial y subida exclusiva por USB a `MOT_ALN_REG`.

**Architecture:** El módulo tendrá modelos, validación, formulario y tablas SQLite propios. `OperationFlow` incorporará Alineación únicamente para equipos elegibles según `MOT_EQUIPO.PUNTOS`; `tablet_uploader.py` será la única ruta de escritura en MariaDB y sincronizará también una caché histórica offline.

**Tech Stack:** Flutter/Dart, SQLite mediante `sqflite`, Python 3, MariaDB, ADB y `unittest`.

## Global Constraints

- Alineación aparece únicamente para `PUNTOS` 1, 2, 6 o 9; no se usa `PT_EQ`.
- `PUNTOS` 1, 2 y 9 usan los cuatro campos `AMB_*`.
- `PUNTOS` 6 usa los ocho campos `ACM_*` y `ACB_*`.
- Todos los campos aplicables son obligatorios; el operador escribe `0` cuando no existe lectura.
- La entrada acepta signo, enteros o hasta dos decimales y solo coma decimal.
- No se aplican límites mínimo ni máximo.
- Guardar crea únicamente una fila SQLite pendiente.
- La subida se realiza exclusivamente por USB; no se agregan rutas ni botones API.
- `ODT` permanece `NULL`.
- El APK de trabajo se genera con `build_usb_apk.ps1`.
- El workspace no es un repositorio Git; se omiten pasos de commit sin borrar cambios.

---

### Task 1: Modelo, plan y validación de alineación

**Files:**
- Create: `lib/models/alignment_measurement.dart`
- Create: `lib/models/alignment_plan.dart`
- Modify: `lib/models/models.dart`
- Create: `test/alignment_measurement_test.dart`

**Interfaces:**
- Produces: `AlignmentMeasurement`, `AlignmentField`, `AlignmentSection`, `AlignmentPlanResolver.fromPuntos(int)`, `parseAlignmentValue(String)`.
- Consumes: nombres exactos de columnas de `MOT_ALN_REG`.

- [ ] **Step 1: Write the failing resolver and parser tests**

```dart
expect(
  AlignmentPlanResolver.fromPuntos(1)
      .expand((section) => section.fields)
      .map((field) => field.column),
  ['AMB_ANGULO_V', 'AMB_ANGULO_H', 'AMB_COMPENSACION_V', 'AMB_COMPENSACION_H'],
);
expect(AlignmentPlanResolver.fromPuntos(6), hasLength(2));
expect(AlignmentPlanResolver.isEligible(3), isFalse);
expect(parseAlignmentValue('-1,03'), -1.03);
expect(parseAlignmentValue('0.05'), isNull);
expect(parseAlignmentValue('1,234'), isNull);
```

- [ ] **Step 2: Run the model test and verify RED**

Run: `flutter test test/alignment_measurement_test.dart`

Expected: compilation fails because the alignment types do not exist.

- [ ] **Step 3: Implement immutable plan definitions and parser**

```dart
double? parseAlignmentValue(String input) {
  final value = input.trim();
  if (!RegExp(r'^-?\d+(,\d{1,2})?$').hasMatch(value)) return null;
  return double.tryParse(value.replaceFirst(',', '.'));
}
```

`AlignmentPlanResolver.fromPuntos(1|2|9)` returns one section titled
`ALINEACIÓN MOTOR–BOMBA`; `fromPuntos(6)` returns `ALINEACIÓN MOTOR–CAJA` and
`ALINEACIÓN CAJA–BOMBA`; other values return an empty list.

- [ ] **Step 4: Implement serialization**

`AlignmentMeasurement.toDbMap()` writes all 12 value columns and leaves
non-applicable values as `null`. `fromMap()` and `fromRemoteMap()` preserve
signed doubles, administrative text, sync state and nullable `odt`.

- [ ] **Step 5: Run model tests and format**

Run:

```powershell
dart format lib/models/alignment_measurement.dart lib/models/alignment_plan.dart test/alignment_measurement_test.dart
flutter test test/alignment_measurement_test.dart
```

Expected: all alignment model tests pass.

### Task 2: Persistencia SQLite y cola local

**Files:**
- Modify: `lib/db/db_helper.dart`
- Create: `test/alignment_db_contract_test.dart`

**Interfaces:**
- Consumes: `AlignmentMeasurement`.
- Produces: `insertAlignment`, `getPendingAlignments`, `getLocalAlignments`, `updateAlignment`, `deleteAlignment`, `markAlignmentSynced`, `markAlignmentError`, `clearAlignmentErrors`, `countAlignmentErrors`, `countSyncedAlignmentsToday`, `replaceRemoteAlignmentHistory`, `getRemoteAlignmentHistory`.

- [ ] **Step 1: Write failing schema and mapping contract tests**

The test reads `db_helper.dart` and asserts the schema contains
`ALINEACIONES_LOCAL`, `ALINEACIONES_REMOTAS`, the 12 exact value columns,
`sincronizado`, `error_sync`, `created_at`, and a pending index.

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/alignment_db_contract_test.dart`

Expected: assertions fail because alignment tables and methods are absent.

- [ ] **Step 3: Add additive schema creation**

Create `ALINEACIONES_LOCAL` with `uuid TEXT PRIMARY KEY`, administrative
columns, 12 `REAL` value columns, `odt INTEGER`, `sincronizado INTEGER NOT
NULL DEFAULT 0`, `error_sync TEXT`, and `created_at TEXT NOT NULL DEFAULT
CURRENT_TIMESTAMP`.

Create `ALINEACIONES_REMOTAS` with `remote_key TEXT PRIMARY KEY`, the same
business columns, and `fecha_hora_iso TEXT`.

- [ ] **Step 4: Add queue CRUD**

Use `where: 'sincronizado = 0'` for edit/delete safety. Successful edits reset
`error_sync` to `null`. Marking sync changes only `ALINEACIONES_LOCAL`.

- [ ] **Step 5: Add history cache operations and counts**

Remote replacement runs in a transaction. Local synchronized rows remain
untouched. Date counts use the same `yyyy-MM-dd` helper as existing modules.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
dart format lib/db/db_helper.dart test/alignment_db_contract_test.dart
dart analyze lib/db/db_helper.dart
flutter test test/alignment_db_contract_test.dart test/alignment_measurement_test.dart
```

Expected: no analyzer errors and all focused tests pass.

### Task 3: Formulario de captura y revisión

**Files:**
- Create: `lib/screens/alignment_capture_screen.dart`
- Create: `test/alignment_capture_screen_test.dart`

**Interfaces:**
- Consumes: `Equipo`, `AlignmentPlanResolver`, `DbHelper.insertAlignment`, optional existing `AlignmentMeasurement`.
- Produces: `AlignmentCaptureScreen(equipo, measurementToEdit)`, returning `true` after a confirmed local save.

- [ ] **Step 1: Write failing widget tests**

Cover:

```dart
expect(find.text('ALINEACIÓN MOTOR–BOMBA'), findsOneWidget);
expect(find.text('Ángulo vertical'), findsOneWidget);
expect(find.text('ALINEACIÓN MOTOR–CAJA'), findsOneWidget);
expect(find.text('ALINEACIÓN CAJA–BOMBA'), findsOneWidget);
expect(find.textContaining('anterior'), findsNothing);
expect(find.byType(Image), findsNothing);
```

Add validation cases for empty, `0.25`, `1,234`, `-1,03`, and `0`.

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/alignment_capture_screen_test.dart`

Expected: compilation fails because `AlignmentCaptureScreen` is absent.

- [ ] **Step 3: Implement dynamic cards**

Create one `TextEditingController` per applicable column. Use a scrollable form,
explicit unit suffixes, signed numeric keyboard, optional observation, and a
single Save button.

- [ ] **Step 4: Implement local-only save**

Validate every controller with `parseAlignmentValue`. Read session metadata
from `SharedPreferences`, equipment metadata from `DbHelper`, set `odt: null`,
and call only `DbHelper.insertAlignment` or `updateAlignment`.

The screen source must not contain `ApiService`, HTTP calls, or MariaDB calls.

- [ ] **Step 5: Implement error and success states**

On SQLite failure, leave every controller unchanged and show
`No se pudo guardar localmente`. On success, show
`Alineación guardada en la tablet para subirla por USB`.

- [ ] **Step 6: Run widget tests and analyze**

Run:

```powershell
dart format lib/screens/alignment_capture_screen.dart test/alignment_capture_screen_test.dart
dart analyze lib/screens/alignment_capture_screen.dart
flutter test test/alignment_capture_screen_test.dart
```

Expected: all capture tests pass.

### Task 4: Cuarta operación y secuencia

**Files:**
- Modify: `lib/models/operation_flow.dart`
- Modify: `lib/screens/operation_selection_screen.dart`
- Modify: `test/operation_flow_test.dart`
- Modify: `test/operation_selection_screen_test.dart`

**Interfaces:**
- Consumes: `AlignmentPlanResolver.isEligible(equipo.puntos)`.
- Produces: `OperationType.alignment` and navigation to `AlignmentCaptureScreen`.

- [ ] **Step 1: Extend tests to four operations**

Assert that eligible equipment finds `Alineación`, non-eligible equipment does
not, and a sequence of four selected operations preserves the chosen order.

- [ ] **Step 2: Run and verify RED**

Run:

```powershell
flutter test test/operation_flow_test.dart test/operation_selection_screen_test.dart
```

Expected: tests fail because `OperationType.alignment` is absent.

- [ ] **Step 3: Add enum, labels, card and navigation**

Use `Icons.straighten_rounded`, the title `Alineación`, and pass the same
`Equipo` to `AlignmentCaptureScreen`.

- [ ] **Step 4: Preserve existing sequence behavior**

The continuation dialog must produce `Continuar con Alineación` when alignment
is pending and must not show it for ineligible equipment.

- [ ] **Step 5: Run sequence tests**

Expected: all operation tests pass without changing behavior for the existing
three operations.

### Task 5: Pendientes, edición, eliminación y contadores

**Files:**
- Modify: `lib/screens/sync_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/providers/app_provider.dart`
- Create: `test/alignment_sync_contract_test.dart`

**Interfaces:**
- Consumes: alignment queue CRUD from `DbHelper`.
- Produces: pending cards, edit/delete actions, counts and USB-only contract.

- [ ] **Step 1: Write failing UI/source contract tests**

Assert SyncScreen renders alignment pending rows, exposes edit/delete callbacks,
includes alignment in `_pendingTotal`, and still contains no
`Subir por red / API`.

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/alignment_sync_contract_test.dart test/usb_only_sync_test.dart`

Expected: alignment assertions fail; USB-only assertions remain green.

- [ ] **Step 3: Load alignment queue and counts**

Add `_alignmentPendientes`, synced-today count, error count, pending list rows,
and temperature-style iconography without adding an API upload method.

- [ ] **Step 4: Add review and delete actions**

Review opens `AlignmentCaptureScreen` with the existing measurement. Delete
requires confirmation and calls `deleteAlignment` only for pending rows.

- [ ] **Step 5: Add home/provider statistics**

Pending, inspected-today and error totals include alignment while connectivity
checks remain read-only.

- [ ] **Step 6: Run focused regression**

Run:

```powershell
dart analyze lib/screens/sync_screen.dart lib/screens/home_screen.dart lib/providers/app_provider.dart
flutter test test/alignment_sync_contract_test.dart test/usb_only_sync_test.dart
```

Expected: all focused tests pass.

### Task 6: Historial de alineaciones

**Files:**
- Modify: `lib/screens/mediciones_screen.dart`
- Create: `test/alignment_history_test.dart`

**Interfaces:**
- Consumes: local and remote alignment history.
- Produces: `AlignmentHistoryCard` and Alineación filter.

- [ ] **Step 1: Write failing history widget tests**

Test MOTOR–BOMBA and MOTOR–CAJA–BOMBA cards, signed values, units,
observations, sync state, and absence of non-applicable columns.

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/alignment_history_test.dart`

Expected: compilation fails because alignment history widgets do not exist.

- [ ] **Step 3: Add Alineación filter and loading**

Merge local and cached remote rows. Deduplicate with a signature containing
location, date, time, 12 rounded values, text fields and ODT.

- [ ] **Step 4: Render applicable cards**

Use plan-aware labels and units. Do not infer applicability from zero values;
use the non-null columns and equipment `PUNTOS`.

- [ ] **Step 5: Run history and existing measurement tests**

Run:

```powershell
flutter test test/alignment_history_test.dart test/temperature_history_test.dart
```

Expected: both alignment and temperature history pass.

### Task 7: Sincronización Python con `MOT_ALN_REG`

**Files:**
- Modify: `tablet_uploader.py`
- Modify: `test_tablet_uploader.py`

**Interfaces:**
- Produces: `ensure_alignment_schema`, `fetch_pending_alignments`, `upload_alignment_rows`, `upload_pending_alignments`, `mark_alignment_result`, `sync_alignment_history_from_mariadb`.
- Consumes: `ALINEACIONES_LOCAL`, `ALINEACIONES_REMOTAS`, MariaDB `MOT_ALN_REG`.

- [ ] **Step 1: Write failing Python tests**

Cover schema migration, pending filtering, exact 23-column insert order,
nullable non-applicable values, identical retry, different values at the same
timestamp, row rollback, mark result, combined queue totals, GUI display and
history limit/order.

- [ ] **Step 2: Run and verify RED**

Run:

```powershell
& 'C:\Users\home-it\AppData\Local\Python\pythoncore-3.14-64\python.exe' -m unittest test_tablet_uploader.py -v
```

Expected: new alignment tests fail because uploader support is absent.

- [ ] **Step 3: Add additive tablet schema migration**

Mirror the Dart tables and columns exactly. Never drop or recreate a local
pending table.

- [ ] **Step 4: Add pending fetch and normalized signature**

Convert numeric strings through `Decimal(...).quantize(Decimal('0.01'))`.
Normalize text by trimming, collapsing whitespace and casefolding. Keep `None`
distinct from numeric zero for non-applicable columns.

- [ ] **Step 5: Add transactional MariaDB upload**

Query candidates by location/date/time, compare the full signature, insert in
the exact 23-column order, commit one row at a time, rollback failures, and
continue the queue.

- [ ] **Step 6: Integrate every execution path**

Add alignment to `upload_pending_work`, CLI summaries, tablet-request flow,
GUI pending display, success/error counts and database pushback.

- [ ] **Step 7: Add bounded remote cache**

Fetch at most 500 rows ordered by parsed date/time descending with ID as final
tiebreaker. Rebuild `ALINEACIONES_REMOTAS` without touching local pending rows.

- [ ] **Step 8: Run Python suites**

Run:

```powershell
& 'C:\Users\home-it\AppData\Local\Python\pythoncore-3.14-64\python.exe' -m py_compile tablet_uploader.py
& 'C:\Users\home-it\AppData\Local\Python\pythoncore-3.14-64\python.exe' -m unittest test_tablet_uploader.py test_api_temperatures.py test_api_replacements.py -v
```

Expected: compilation succeeds and all Python tests pass.

### Task 8: Verificación integrada, APK e instalación

**Files:**
- Modify only files required by failures found in this task.
- Verify: `build/app/outputs/flutter-apk/app-debug.apk`

**Interfaces:**
- Consumes: completed Flutter and Python implementation.
- Produces: installed USB-compatible APK and visible uploader GUI.

- [ ] **Step 1: Run formatting and analysis**

Run `dart format --output=none --set-exit-if-changed` on every changed Dart
file, then `dart analyze` on those files.

Expected: no formatting changes and no analyzer errors.

- [ ] **Step 2: Run the complete Flutter suite**

Run: `flutter test`

Expected: all tests pass with zero failures.

- [ ] **Step 3: Run the complete Python suite**

Run the command from Task 7 Step 8.

Expected: all tests pass with zero failures.

- [ ] **Step 4: Build the coherent USB APK**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_usb_apk.ps1
```

Expected: `app-debug.apk` exists and contains `kernel_blob.bin` plus
`android:debuggable="true"`.

- [ ] **Step 5: Install without deleting local data**

Run:

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -W -n com.example.scv_ptbg/.MainActivity
```

Expected: streamed install succeeds and the activity reports `Status: ok`.

- [ ] **Step 6: Verify the real tablet**

Confirm `pidof com.example.scv_ptbg` returns a PID, the activity remains
top-resumed, `usb_status.json` reports `ONLINE`, and logcat contains no Flutter
fatal error.

- [ ] **Step 7: Open the laptop uploader**

Launch `tablet_uploader.py` visibly and confirm the window title is
`SCV-PTBG - Subir mediciones USB desde laptop`.

