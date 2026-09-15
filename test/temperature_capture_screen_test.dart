import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/screens/temperature_capture_screen.dart';

const _equipo = Equipo(
  id: 4,
  codeSys: 1,
  equipo: 'FIN-FAN A',
  localizacion: 15,
  qrCode: 'FIN-FAN-A',
  puntos: 4,
  ptEq: 4,
  sistema: 'TURBINA BG-1',
);

void main() {
  testWidgets('muestra el nivel mientras se escribe, sin pulsar Siguiente',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TemperatureCaptureScreen(
          equipo: _equipo,
          enableRemote: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('temperature-value-field')),
      '120',
    );
    await tester.pump();

    expect(find.textContaining('Alto:'), findsOneWidget);
    expect(find.text('T1'), findsWidgets);
  });

  testWidgets('captura una temperatura en Celsius por punto', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TemperatureCaptureScreen(
          equipo: _equipo,
          enableRemote: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medición de temperatura'), findsOneWidget);
    expect(find.text('°C'), findsWidgets);
    expect(find.text('T1'), findsWidgets);
    expect(find.text('Horizontal'), findsNothing);
    expect(find.textContaining('mm/s'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('temperature-value-field')),
      '42,5',
    );
    await tester.tap(find.byKey(const Key('temperature-next-button')));
    await tester.pump();

    expect(find.text('T2'), findsWidgets);
  });

  testWidgets('FIN-FAN incluye el paso T10 para la correa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TemperatureCaptureScreen(
          equipo: _equipo,
          enableRemote: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byKey(const Key('temperature-value-field')),
        '${40 + i}',
      );
      await tester.tap(find.byKey(const Key('temperature-next-button')));
      await tester.pump();
    }

    expect(find.text('T10'), findsWidgets);
    expect(find.text('Correa (FIN-FAN)'), findsOneWidget);
  });

  test('captura no sube temperatura; sincronizacion lo hace despues', () {
    final source = File(
      'lib/screens/temperature_capture_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('syncTemperature(')));
  });
}
