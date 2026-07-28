import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/temperature_measurement.dart';
import 'package:scv_ptbg/screens/mediciones_screen.dart';

void main() {
  testWidgets('historial muestra valores de temperatura y estado pendiente',
      (tester) async {
    const measurement = TemperatureMeasurement(
      uuid: 'temp-1',
      localizacion: 15,
      sistema: 'TURBINA BG-1',
      fecha: '2026-07-22',
      hora: '10:30:00',
      valores: {'T1': 41.5, 'T10': 55},
      observaciones: 'Correa revisada',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TemperatureHistoryCard(measurement: measurement),
        ),
      ),
    );

    expect(find.text('LOC-15 · TURBINA BG-1'), findsOneWidget);
    expect(find.text('T1  41.50 °C'), findsOneWidget);
    expect(find.text('T10  55.00 °C'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Correa revisada'), findsOneWidget);
  });

  testWidgets('historial conserva cero Celsius en una columna aplicable',
      (tester) async {
    const measurement = TemperatureMeasurement(
      uuid: 'temp-zero',
      localizacion: 15,
      sistema: 'FIN-FAN',
      fecha: '2026-07-22',
      hora: '10:31:00',
      valores: {'T1': 0, 'T3': 0},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TemperatureHistoryCard(
            measurement: measurement,
            applicableColumns: {'T1', 'T2', 'T9', 'T10'},
          ),
        ),
      ),
    );

    expect(find.text('T1  0.00 °C'), findsOneWidget);
    expect(find.text('T3  0.00 °C'), findsNothing);
  });
}
