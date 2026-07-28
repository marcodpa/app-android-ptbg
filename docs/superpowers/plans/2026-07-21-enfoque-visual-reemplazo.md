# Enfoque visual de reemplazo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar la imagen oficial del conjunto y aclarar exclusivamente los componentes que no seran reemplazados.

**Architecture:** Un resolver puro asocia cada valor de `PUNTOS` con el asset, proporcion y regiones normalizadas por componente. Un widget reutilizable dibuja el fondo aclarado y superpone la imagen original recortada por las regiones seleccionadas; `ReplacementScreen` solo entrega el equipo y la seleccion.

**Tech Stack:** Flutter, Dart, Material 3, flutter_test.

## Global Constraints

- Reutilizar `EquipoVisualResolver.fromEquipo(equipo).cleanAsset`.
- La seleccion vacia y la seleccion de todos los componentes muestran la imagen completa normal.
- Con seleccion parcial, el fondo usa opacidad 0.22 y las regiones elegidas opacidad 1.0.
- Las coordenadas son normalizadas entre 0 y 1.
- No modificar MariaDB ni las imagenes de vibracion.
- El proyecto no contiene repositorio Git; no se incluyen commits.

---

### Task 1: Resolver de layouts visuales

**Files:**
- Create: `lib/models/replacement_visual_layout.dart`
- Test: `test/replacement_visual_layout_test.dart`

**Interfaces:**
- Produces: `ReplacementVisualLayout`, `ReplacementVisualResolver.fromPuntos(int)` y `regionsFor(Set<ReplacementComponent>)`.

- [ ] Write failing tests for PUNTOS 1 through 9, component coverage and multi-selection region union.
- [ ] Run `flutter test test/replacement_visual_layout_test.dart`; expect failure because the model does not exist.
- [ ] Implement layouts with the current clean assets, exact image aspect ratios and non-empty normalized rectangles for every selectable component.
- [ ] Run the focused test; expect all tests to pass.

### Task 2: Widget de imagen enfocada

**Files:**
- Create: `lib/widgets/replacement_focus_image.dart`
- Test: `test/replacement_focus_image_test.dart`

**Interfaces:**
- Consumes: `Equipo equipo`, `Set<ReplacementComponent> selected`.
- Produces: `ReplacementFocusImage` with keys `replacement-image-full`, `replacement-image-faded` and `replacement-image-focused` for verifiable render states.

- [ ] Write failing widget tests for empty, partial and complete selection states.
- [ ] Run `flutter test test/replacement_focus_image_test.dart`; expect failure because the widget does not exist.
- [ ] Implement stable 220 px maximum viewport, exact aspect-ratio sizing, faded full image, clipped selected image, teal outlines and asset error fallback.
- [ ] Run the focused test; expect all tests to pass.

### Task 3: Integracion y entrega

**Files:**
- Modify: `lib/screens/replacement_screen.dart`
- Modify: `test/replacement_screen_test.dart`

**Interfaces:**
- Consumes: `ReplacementFocusImage(equipo: widget.equipo, selected: _selected)`.
- Produces: identical focus view in capture and review screens.

- [ ] Add failing assertions that capture and review contain `ReplacementFocusImage`.
- [ ] Insert the widget above component selection and below the equipment header in both states.
- [ ] Run `flutter test`; expect all project tests to pass.
- [ ] Run `dart analyze lib test`; require no analyzer errors.
- [ ] Build with `flutter build apk --debug --target-platform android-arm64 --no-pub`.
- [ ] Install with `adb -s TABR70000000012091 install -r build/app/outputs/flutter-apk/app-debug.apk` and launch `com.example.scv_ptbg/.MainActivity`.
