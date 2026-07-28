# Diseño Visual de Alineación Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir la captura de alineación en una pantalla industrial visual que muestre una referencia de ejes perfectamente alineados para MOTOR–BOMBA y MOTOR–CAJA–BOMBA.

**Architecture:** Crear un widget visual autocontenido que dibuje el tren del equipo con primitivas Flutter, sin imágenes externas ni cálculos de tolerancia. Integrarlo en el formulario actual, reorganizar los campos por Ángulo y Compensación y reforzar la elegibilidad antes de permitir capturas.

**Tech Stack:** Flutter, Dart, Material 3, CustomPainter, flutter_test, SQLite local, sincronización USB/ADB existente.

## Global Constraints

- Solo `PUNTOS 1`, `PUNTOS 2`, `PUNTOS 6` y `PUNTOS 9` admiten alineación.
- FIN-FAN, VENTILADORES y los demás equipos no muestran ni abren alineación.
- `PUNTOS 1`, `PUNTOS 2` y `PUNTOS 9` usan MOTOR–BOMBA.
- `PUNTOS 6` usa MOTOR–CAJA y CAJA–BOMBA.
- No se calculan estados correcto/incorrecto porque no existen tolerancias oficiales.
- Los campos usan coma decimal, signo opcional y máximo dos decimales, sin límite numérico.
- La medición se guarda primero en SQLite y solo se sube desde la laptop por USB.
- `ODT` permanece nulo y los campos no aplicables permanecen `NULL`.

---

### Task 1: Referencia técnica reutilizable

**Files:**
- Create: `lib/widgets/alignment_reference_card.dart`
- Modify: `lib/widgets/widgets.dart`
- Test: `test/alignment_reference_card_test.dart`

**Interfaces:**
- Consumes: `Equipo.puntos` y `AlignmentPlanResolver.isEligible(int puntos)`.
- Produces: `AlignmentReferenceCard({required int puntos})` y `AlignmentTrainType`.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('PUNTOS 1 muestra referencia MOTOR–BOMBA', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: AlignmentReferenceCard(puntos: 1)),
  ));
  expect(find.byKey(const Key('alignment-reference-motor-pump')), findsOneWidget);
  expect(find.text('Referencia de alineación correcta'), findsOneWidget);
  expect(find.text('MOTOR'), findsOneWidget);
  expect(find.text('BOMBA'), findsOneWidget);
});

testWidgets('PUNTOS 6 distingue los dos acoples', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: AlignmentReferenceCard(puntos: 6)),
  ));
  expect(find.byKey(const Key('alignment-reference-motor-gearbox-pump')), findsOneWidget);
  expect(find.text('Motor–Caja'), findsOneWidget);
  expect(find.text('Caja–Bomba'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and confirm the missing-widget failure**

Run: `flutter test test/alignment_reference_card_test.dart`

Expected: FAIL because `AlignmentReferenceCard` does not exist.

- [ ] **Step 3: Implement the visual reference**

Create a white rounded card with:

```dart
enum AlignmentTrainType { motorPump, motorGearboxPump }

class AlignmentReferenceCard extends StatelessWidget {
  const AlignmentReferenceCard({super.key, required this.puntos});
  final int puntos;

  @override
  Widget build(BuildContext context) {
    final type = puntos == 6
        ? AlignmentTrainType.motorGearboxPump
        : AlignmentTrainType.motorPump;
    return Container(
      key: Key(type == AlignmentTrainType.motorPump
          ? 'alignment-reference-motor-pump'
          : 'alignment-reference-motor-gearbox-pump'),
      child: Column(children: [
        const Text('Referencia de alineación correcta'),
        CustomPaint(
          painter: AlignmentTrainPainter(type),
          child: const SizedBox(height: 150, width: double.infinity),
        ),
        const Text('Guía visual · no representa un diagnóstico calculado'),
      ]),
    );
  }
}
```

`AlignmentTrainPainter` debe dibujar cuerpos azul marino, bases azul grisáceo,
ejes y línea central turquesa, acoples con anillos concéntricos y etiquetas
visibles. No debe interpretar valores capturados.

- [ ] **Step 4: Run the widget tests**

Run: `flutter test test/alignment_reference_card_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```text
git add lib/widgets/alignment_reference_card.dart lib/widgets/widgets.dart test/alignment_reference_card_test.dart
git commit -m "feat: add technical alignment reference"
```

### Task 2: Formulario visual de alineación

**Files:**
- Modify: `lib/screens/alignment_capture_screen.dart`
- Modify: `test/alignment_capture_screen_test.dart`

**Interfaces:**
- Consumes: `AlignmentReferenceCard`, `AlignmentSection`, `AlignmentField`.
- Produces: formulario con claves actuales `alignment-<COLUMN>` y `alignment-save-button`, sin alterar el contrato de persistencia.

- [ ] **Step 1: Update tests for the approved layout**

Replace the old “ninguna imagen” assertion and add:

```dart
expect(find.text('Referencia de alineación correcta'), findsOneWidget);
expect(find.byKey(const Key('alignment-reference-motor-pump')), findsOneWidget);
expect(find.text('Ángulo'), findsOneWidget);
expect(find.text('Compensación'), findsOneWidget);
expect(find.text('Ejemplo: 0,05'), findsWidgets);
```

For `PUNTOS 6`, assert the MOTOR–CAJA–BOMBA reference and both section titles.

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `flutter test test/alignment_capture_screen_test.dart`

Expected: FAIL because the reference and grouped labels are absent.

- [ ] **Step 3: Integrate the reference and grouped field cards**

Insert after `_EquipmentHeader`:

```dart
AlignmentReferenceCard(puntos: widget.equipo.puntos),
const SizedBox(height: 16),
```

Change `_AlignmentCard` so fields 0–1 appear under `Ángulo` and fields 2–3
under `Compensación`. Keep one vertical reading flow and preserve every
existing controller key and validator. Add persistent helper text
`Ejemplo: 0,05`, the unit suffix, and a `V` or `H` leading badge.

- [ ] **Step 4: Preserve save behavior and run focused tests**

Run: `flutter test test/alignment_capture_screen_test.dart test/alignment_measurement_test.dart test/alignment_db_contract_test.dart`

Expected: PASS with local save, null ODT and unchanged column mapping.

- [ ] **Step 5: Commit**

```text
git add lib/screens/alignment_capture_screen.dart test/alignment_capture_screen_test.dart
git commit -m "feat: redesign alignment capture form"
```

### Task 3: Exclusión defensiva de equipos no alineables

**Files:**
- Modify: `lib/screens/alignment_capture_screen.dart`
- Modify: `test/alignment_capture_screen_test.dart`
- Modify: `test/operation_selection_screen_test.dart`

**Interfaces:**
- Consumes: `AlignmentPlanResolver.isEligible(int puntos)`.
- Produces: selector sin alineación para FIN-FAN/VENTILADORES y pantalla directa con mensaje seguro para cualquier equipo no elegible.

- [ ] **Step 1: Add explicit FIN-FAN and VENTILADORES tests**

```dart
for (final puntos in [4, 5]) {
  testWidgets('PUNTOS $puntos no ofrece alineación', (tester) async {
    final equipo = _equipoSinAlineacion.copyWith(puntos: puntos);
    await tester.pumpWidget(MaterialApp(
      home: OperationSelectionScreen(equipo: equipo),
    ));
    expect(find.byKey(const Key('operation-alignment')), findsNothing);
  });
}
```

Add a direct-screen test that expects `Alineación no disponible para este equipo`
and no save button for a non-eligible `Equipo`.

- [ ] **Step 2: Run tests and confirm direct navigation fails**

Run: `flutter test test/alignment_capture_screen_test.dart test/operation_selection_screen_test.dart`

Expected: the existing selector assertions pass and the new direct-screen
assertion fails.

- [ ] **Step 3: Add the defensive screen state**

At the beginning of `build`, when `_sections.isEmpty`, return a scaffold with
the normal app bar, an `Icons.block_rounded` state, the exact text
`Alineación no disponible para este equipo` and a `Volver` button. Do not
create inputs or expose `Guardar alineación`.

- [ ] **Step 4: Run exclusion and full Flutter tests**

Run:

```text
flutter test test/alignment_capture_screen_test.dart test/operation_selection_screen_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```text
git add lib/screens/alignment_capture_screen.dart test/alignment_capture_screen_test.dart test/operation_selection_screen_test.dart
git commit -m "fix: block alignment for ineligible equipment"
```

### Task 4: APK, tablet and publicación

**Files:**
- Update through build: `build/app/outputs/flutter-apk/app-debug.apk`

**Interfaces:**
- Consumes: verified Flutter project and USB-connected tablet.
- Produces: tested debug APK installed on the tablet and uploaded to GitHub through Git LFS.

- [ ] **Step 1: Verify Python USB uploader remains green**

Run:

```text
py -3 -m py_compile tablet_uploader.py
py -3 -m unittest test_tablet_uploader.py
```

Expected: PASS.

- [ ] **Step 2: Build the APK**

Run: `flutter build apk --debug`

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is generated.

- [ ] **Step 3: Install and launch on the connected tablet**

Run:

```text
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.example.scv_ptbg -c android.intent.category.LAUNCHER 1
```

Expected: one authorized tablet, `Success`, and the application launches.

- [ ] **Step 4: Commit the LFS APK and push**

```text
git add build/app/outputs/flutter-apk/app-debug.apk
git commit -m "build: publish alignment visual APK"
git push origin main
```

Expected: `main` points to the final commit and Git LFS reports one uploaded APK.

- [ ] **Step 5: Verify the remote**

Run:

```text
git ls-remote origin refs/heads/main
git status --short --branch
```

Expected: remote SHA matches local `HEAD` and working tree is clean.
