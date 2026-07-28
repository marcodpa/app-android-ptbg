# Marco y contorno de reemplazo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplicar al visor de reemplazo el marco visual de Vibracion y eliminar bordes internos entre regiones seleccionadas superpuestas.

**Architecture:** Una funcion geometrica pura combina rectangulos mediante `PathOperation.union` y alimenta tanto el clipper como el painter. `ReplacementFocusImage` adopta el contenedor, encabezado, fondo y contador del patron `EquipoPuntoViewer`.

**Tech Stack:** Flutter, Dart, Canvas/Path API, flutter_test.

## Global Constraints

- No cambiar coordenadas, assets ni opacidad del enfoque.
- Reutilizar el mismo path unido para recorte y borde.
- Mantener las claves de prueba de los estados de imagen.
- No modificar MariaDB ni el visor de Vibracion.
- El proyecto no tiene repositorio Git; no se incluyen commits.

---

### Task 1: Union geometrica de regiones

**Files:**
- Modify: `lib/widgets/replacement_focus_image.dart`
- Test: `test/replacement_region_path_test.dart`

**Interfaces:**
- Produces: `Path buildReplacementRegionPath(List<Rect> regions, Size size)`.

- [ ] Crear una prueba fallida donde dos rectangulos superpuestos produzcan un contorno de 400 px y un solo `PathMetric` sobre un lienzo 100x100.
- [ ] Crear una prueba donde dos rectangulos separados produzcan dos `PathMetric`.
- [ ] Ejecutar `flutter test test/replacement_region_path_test.dart` y confirmar el fallo por funcion inexistente.
- [ ] Implementar la union incremental con `Path.combine(PathOperation.union, ...)`.
- [ ] Reutilizar la funcion en `_ReplacementRegionClipper` y `_ReplacementRegionPainter`.
- [ ] Ejecutar la prueba dirigida y confirmar que pasa.

### Task 2: Marco estilo Vibracion

**Files:**
- Modify: `lib/widgets/replacement_focus_image.dart`
- Modify: `test/replacement_focus_image_test.dart`

**Interfaces:**
- Conserva: `ReplacementFocusImage(equipo, selected)`.
- Agrega claves: `replacement-viewer-frame`, `replacement-viewer-header`, `replacement-selection-badge`.

- [ ] Agregar pruebas fallidas del marco, encabezado y textos de contador para cero, una y varias selecciones.
- [ ] Aplicar radio 20, borde 1.3, sombra, encabezado degradado y fondo gris usados por `EquipoPuntoViewer`.
- [ ] Mantener una altura fija y el calculo de proporcion actual.
- [ ] Ejecutar las pruebas del widget y confirmar que pasan.

### Task 3: Verificacion e instalacion

**Files:**
- Verify: `lib/widgets/replacement_focus_image.dart`, `test/` y APK.

- [ ] Ejecutar `flutter test` y exigir cero fallos.
- [ ] Ejecutar `dart analyze` sobre los archivos modificados y exigir cero errores.
- [ ] Compilar `flutter build apk --debug --target-platform android-arm64 --no-pub`.
- [ ] Verificar `TABR70000000012091 device`.
- [ ] Instalar con `adb -s TABR70000000012091 install -r build/app/outputs/flutter-apk/app-debug.apk`.
- [ ] Abrir `com.example.scv_ptbg/.MainActivity`.
