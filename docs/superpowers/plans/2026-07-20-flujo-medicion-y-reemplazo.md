# Flujo de medicion y reemplazo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar despues del QR un selector de Vibracion y Reemplazo de equipo, con seleccion multiple, orden elegido por el usuario y un frontend completo de reemplazo por componente.

**Architecture:** Un modelo puro resuelve operaciones pendientes y componentes disponibles. `OperationSelectionScreen` coordina las rutas existentes y nuevas; `ReplacementScreen` administra seleccion, captura y revision sin escribir en MariaDB.

**Tech Stack:** Flutter, Dart, Material 3, flutter_test.

## Global Constraints

- Conservar login, inicio, QR, captura, sincronizacion e impresion actuales.
- Determinar componentes exclusivamente desde `MOT_EQUIPO.PUNTOS`.
- Capturar solo Marca, Modelo y Serial.
- No modificar MariaDB en esta fase.
- El proyecto no contiene repositorio Git; no se incluyen pasos de commit.

---

### Task 1: Modelo del flujo y componentes

**Files:**
- Create: `lib/models/operation_flow.dart`
- Test: `test/operation_flow_test.dart`

**Interfaces:**
- Produces: `OperationType`, `ReplacementComponent`, `OperationFlow`, `ReplacementComponentResolver.fromPuntos(int)`.

- [ ] **Step 1: Write the failing tests**

Probar que `OperationFlow` respeta la primera operacion elegida y elimina solo operaciones completadas. Probar los mapas `1,2,3,7,8,9 -> motor+bomba`, `4,5 -> motor+ventilador`, `6 -> motor+caja+bomba` y valores desconocidos vacios.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/operation_flow_test.dart`
Expected: FAIL porque `operation_flow.dart` no existe.

- [ ] **Step 3: Write minimal implementation**

```dart
enum OperationType { vibration, replacement }
enum ReplacementComponent { motor, pump, gearbox, fan }

class OperationFlow {
  OperationFlow({required List<OperationType> selected, required this.current})
      : pending = List.of(selected)..remove(current);
  final OperationType current;
  final List<OperationType> pending;
  OperationType? get next => pending.isEmpty ? null : pending.first;
}

class ReplacementComponentResolver {
  static List<ReplacementComponent> fromPuntos(int puntos) {
    if ({1, 2, 3, 7, 8, 9}.contains(puntos)) {
      return const [ReplacementComponent.motor, ReplacementComponent.pump];
    }
    if ({4, 5}.contains(puntos)) {
      return const [ReplacementComponent.motor, ReplacementComponent.fan];
    }
    if (puntos == 6) {
      return const [ReplacementComponent.motor, ReplacementComponent.gearbox, ReplacementComponent.pump];
    }
    return const [];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/operation_flow_test.dart`
Expected: PASS.

### Task 2: Selector y coordinador de operaciones

**Files:**
- Create: `lib/screens/operation_selection_screen.dart`
- Test: `test/operation_selection_screen_test.dart`

**Interfaces:**
- Consumes: `Equipo`, `OperationType`, `OperationFlow`.
- Produces: `OperationSelectionScreen(equipo: Equipo)`.

- [ ] **Step 1: Write failing widget tests**

Comprobar que aparecen exactamente `Vibracion` y `Reemplazo de equipo`, que el boton esta deshabilitado sin seleccion y que al seleccionar ambas se muestran controles para elegir cual comenzar.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/operation_selection_screen_test.dart`
Expected: FAIL porque la pantalla no existe.

- [ ] **Step 3: Implement the screen**

Usar dos opciones grandes seleccionables, un indicador de primera operacion y un boton `Comenzar`. Al completar una ruta con resultado `true`, mostrar un dialogo con `Continuar con ...` y `Finalizar`. Vibracion abre `CaptureScreen`; reemplazo abre `ReplacementScreen`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/operation_selection_screen_test.dart`
Expected: PASS.

### Task 3: Formulario de reemplazo

**Files:**
- Create: `lib/screens/replacement_screen.dart`
- Test: `test/replacement_screen_test.dart`

**Interfaces:**
- Consumes: `Equipo`, `ReplacementComponentResolver`.
- Produces: `ReplacementScreen(equipo: Equipo)` que retorna `true` al finalizar.

- [ ] **Step 1: Write failing widget tests**

Comprobar componentes de PUNTOS 6, validacion de Marca/Modelo/Serial, seleccion multiple y resumen separado por componente.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/replacement_screen_test.dart`
Expected: FAIL porque la pantalla no existe.

- [ ] **Step 3: Implement capture and review**

Crear seleccion de componentes, tres controladores por componente, validacion con `Form`, resumen del equipo y datos nuevos, confirmacion de salida con cambios y confirmacion final sin escritura en MariaDB.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/replacement_screen_test.dart`
Expected: PASS.

### Task 4: Integrar despues del QR

**Files:**
- Modify: `lib/screens/qr_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/operation_selection_screen_test.dart`

**Interfaces:**
- Consumes: `OperationSelectionScreen(equipo: eq)`.
- Produces: el boton existente `Iniciar medicion` abre el selector con el mismo `Equipo`.

- [ ] **Step 1: Add a failing navigation assertion**

Verificar mediante la accion publica del selector que el equipo conserva localizacion, nombre y `PUNTOS`.

- [ ] **Step 2: Run the focused test**

Run: `flutter test test/operation_selection_screen_test.dart`
Expected: FAIL hasta integrar el argumento del equipo.

- [ ] **Step 3: Replace direct capture navigation**

Cambiar `_iniciarMedicion` para abrir `OperationSelectionScreen(equipo: eq)` y reemplazar el import directo de captura. Mantener intacto el escaneo y la vista previa.

- [ ] **Step 4: Run focused and complete tests**

Run: `flutter test`
Expected: todos PASS.

### Task 5: Verificacion e instalacion

**Files:**
- Verify: `lib/`, `test/`, `build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: sin errores.

- [ ] **Step 2: Build only ARM64 without dependency download**

Run: `flutter build apk --debug --target-platform android-arm64 --no-pub`
Expected: exit 0 y APK en `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 3: Detect tablet**

Run: `adb devices`
Expected: `TABR70000000012091 device`.

- [ ] **Step 4: Install and launch**

Run: `adb -s TABR70000000012091 install -r build/app/outputs/flutter-apk/app-debug.apk`
Expected: `Success`.

Run: `adb -s TABR70000000012091 shell am start -n com.example.scv_ptbg/.MainActivity`
Expected: actividad iniciada.
