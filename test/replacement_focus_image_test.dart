import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/replacement_visual_layout.dart';
import 'package:scv_ptbg/widgets/replacement_focus_image.dart';

const _equipo = Equipo(
  id: 2,
  codeSys: 1,
  equipo: 'NOX-LIQUIDO',
  localizacion: 2,
  puntos: 6,
  ptEq: 6,
  sistema: 'TURBINA BG-1',
);

void main() {
  test('finfan usa la misma imagen corregida que vibraciones', () {
    const finfan = Equipo(
      id: 15,
      codeSys: 1,
      equipo: 'FIN FAN A',
      localizacion: 15,
      puntos: 4,
      ptEq: 4,
      sistema: 'TURBINA BG-1',
    );

    final layout = ReplacementVisualResolver.fromEquipo(finfan);

    expect(layout?.asset, 'assets/images/visual_finfan.jpg');
  });

  test('ventilador conserva su imagen aunque PUNTOS venga como finfan', () {
    const ventilador = Equipo(
      id: 4,
      codeSys: 1,
      equipo: 'VENT TURB A',
      localizacion: 4,
      puntos: 5,
      ptEq: 5,
      sistema: 'TURBINA BG-1',
    );

    final layout = ReplacementVisualResolver.fromEquipo(ventilador);

    expect(layout?.asset, 'assets/images/visual_ventiladores.jpg');
  });

  Future<void> pumpViewer(
    WidgetTester tester,
    Set<ReplacementComponent> selected,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplacementFocusImage(
            equipo: _equipo,
            selected: selected,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin seleccion muestra la imagen completa normal',
      (tester) async {
    await pumpViewer(tester, {});

    expect(find.byKey(const Key('replacement-viewer-frame')), findsOneWidget);
    expect(find.byKey(const Key('replacement-viewer-header')), findsOneWidget);
    expect(
        find.byKey(const Key('replacement-selection-badge')), findsOneWidget);
    expect(find.text('Componentes del equipo'), findsOneWidget);
    expect(find.text('Sin seleccionar'), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-full')), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-faded')), findsNothing);
    expect(find.byKey(const Key('replacement-image-focused')), findsNothing);
  });

  testWidgets('seleccion parcial aclara el fondo y conserva el foco',
      (tester) async {
    await pumpViewer(tester, {ReplacementComponent.motor});

    expect(find.text('1 seleccionado'), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-full')), findsNothing);
    expect(find.byKey(const Key('replacement-image-faded')), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-focused')), findsOneWidget);

    final faded = tester.widget<Opacity>(
      find.byKey(const Key('replacement-image-faded')),
    );
    expect(faded.opacity, 0.22);
  });

  testWidgets('muestra la cantidad cuando hay varios componentes',
      (tester) async {
    await pumpViewer(tester, {
      ReplacementComponent.motor,
      ReplacementComponent.gearbox,
    });

    expect(find.text('2 seleccionados'), findsOneWidget);
  });

  testWidgets('todos seleccionados muestran el conjunto completo normal',
      (tester) async {
    await pumpViewer(tester, {
      ReplacementComponent.motor,
      ReplacementComponent.gearbox,
      ReplacementComponent.pump,
    });

    expect(find.byKey(const Key('replacement-image-full')), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-faded')), findsNothing);
    expect(find.byKey(const Key('replacement-image-focused')), findsNothing);
  });
}
