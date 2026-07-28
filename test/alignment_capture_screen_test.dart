import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/screens/alignment_capture_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _motorPump = Equipo(
  id: 1,
  codeSys: 1,
  equipo: 'MOTOR BOMBA',
  localizacion: 9,
  puntos: 1,
  ptEq: 1,
  sistema: 'BG-1',
);

const _motorGearboxPump = Equipo(
  id: 2,
  codeSys: 1,
  equipo: 'MOTOR CAJA BOMBA',
  localizacion: 20,
  puntos: 6,
  ptEq: 6,
  sistema: 'BG-2',
);

const _finFan = Equipo(
  id: 3,
  codeSys: 1,
  equipo: 'FIN-FAN',
  localizacion: 30,
  puntos: 4,
  ptEq: 4,
  sistema: 'ENFRIAMIENTO',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'responsable': 'Ana',
      'cargo': 'MECÁNICO',
    });
  });

  testWidgets('MOTOR-BOMBA muestra referencia y campos agrupados', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlignmentCaptureScreen(
          equipo: _motorPump,
          onSave: (_) async {},
        ),
      ),
    );

    expect(find.text('ALINEACIÓN MOTOR–BOMBA'), findsOneWidget);
    expect(
      find.byKey(const Key('alignment-reference-motor-pump')),
      findsOneWidget,
    );
    expect(find.text('Referencia de alineación correcta'), findsOneWidget);
    expect(find.text('Ángulo'), findsOneWidget);
    expect(find.text('Compensación'), findsOneWidget);
    expect(find.text('Ejemplo: 0,05'), findsNWidgets(4));
    expect(find.text('Ángulo vertical'), findsOneWidget);
    expect(find.textContaining('anterior'), findsNothing);
  });

  testWidgets('PUNTOS 6 muestra las dos alineaciones completas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlignmentCaptureScreen(
          equipo: _motorGearboxPump,
          onSave: (_) async {},
        ),
      ),
    );

    expect(find.text('ALINEACIÓN MOTOR–CAJA'), findsOneWidget);
    expect(find.text('ALINEACIÓN CAJA–BOMBA'), findsOneWidget);
    expect(
      find.byKey(const Key('alignment-reference-motor-gearbox-pump')),
      findsOneWidget,
    );
    expect(find.text('Motor–Caja'), findsOneWidget);
    expect(find.text('Caja–Bomba'), findsOneWidget);
    expect(find.text('Ángulo'), findsNWidgets(2));
    expect(find.text('Compensación'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNWidgets(9));
  });

  testWidgets('todos los campos son obligatorios y solo aceptan coma', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlignmentCaptureScreen(
          equipo: _motorPump,
          onSave: (_) async {},
        ),
      ),
    );

    tester
        .widget<ElevatedButton>(
          find.byKey(const Key('alignment-save-button')),
        )
        .onPressed!();
    await tester.pump();
    expect(find.text('Valor obligatorio'), findsNWidgets(4));

    for (final column in const [
      'AMB_ANGULO_V',
      'AMB_ANGULO_H',
      'AMB_COMPENSACION_V',
      'AMB_COMPENSACION_H',
    ]) {
      await tester.enterText(find.byKey(Key('alignment-$column')), '0.25');
    }
    tester
        .widget<ElevatedButton>(
          find.byKey(const Key('alignment-save-button')),
        )
        .onPressed!();
    await tester.pump();
    expect(find.text('Use coma y máximo 2 decimales'), findsNWidgets(4));

    await tester.enterText(
      find.byKey(const Key('alignment-AMB_ANGULO_V')),
      '1,234',
    );
    tester
        .widget<ElevatedButton>(
          find.byKey(const Key('alignment-save-button')),
        )
        .onPressed!();
    await tester.pump();
    expect(find.text('Use coma y máximo 2 decimales'), findsWidgets);
  });

  testWidgets('guarda valores negativos y cero localmente', (tester) async {
    AlignmentMeasurement? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AlignmentCaptureScreen(
          equipo: _motorPump,
          onSave: (measurement) async => saved = measurement,
        ),
      ),
    );

    final values = {
      'AMB_ANGULO_V': '-1,03',
      'AMB_ANGULO_H': '0',
      'AMB_COMPENSACION_V': '0,05',
      'AMB_COMPENSACION_H': '2',
    };
    for (final entry in values.entries) {
      await tester.enterText(
        find.byKey(Key('alignment-${entry.key}')),
        entry.value,
      );
    }
    tester
        .widget<ElevatedButton>(
          find.byKey(const Key('alignment-save-button')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved?.valores['AMB_ANGULO_V'], -1.03);
    expect(saved?.valores['AMB_ANGULO_H'], 0);
    expect(saved?.odt, isNull);
    expect(
      find.text(
        'Alineación guardada en la tablet para subirla por USB',
      ),
      findsOneWidget,
    );
  });

  test('captura no contiene ningún transporte remoto', () {
    final source =
        File('lib/screens/alignment_capture_screen.dart').readAsStringSync();

    expect(source, isNot(contains('ApiService')));
    expect(source, isNot(contains('http')));
    expect(source, isNot(contains('MariaDB')));
  });

  testWidgets('bloquea captura directa para FIN-FAN', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AlignmentCaptureScreen(equipo: _finFan),
      ),
    );

    expect(
      find.text('Alineación no disponible para este equipo'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('alignment-save-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('alignment-reference-motor-pump')),
      findsNothing,
    );
  });
}
