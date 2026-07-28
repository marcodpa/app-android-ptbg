import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/alignment_measurement.dart';
import 'package:scv_ptbg/screens/mediciones_screen.dart';

void main() {
  testWidgets('historial MOTOR-BOMBA muestra signo, unidades y observación', (
    tester,
  ) async {
    const measurement = AlignmentMeasurement(
      uuid: 'aln-1',
      localizacion: 9,
      sistema: 'BG-1',
      puntos: 1,
      fecha: '2026-07-28',
      hora: '09:20:00',
      valores: {
        'AMB_ANGULO_V': -1.03,
        'AMB_ANGULO_H': 0.05,
        'AMB_COMPENSACION_V': 0,
        'AMB_COMPENSACION_H': 2.4,
        'ACM_ANGULO_V': 99,
      },
      observaciones: 'Ajuste terminado',
      errorSync: 'USB desconectado',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlignmentHistoryCard(measurement: measurement),
        ),
      ),
    );

    expect(find.text('ALINEACIÓN MOTOR–BOMBA'), findsOneWidget);
    expect(find.text('-1,03 mm/100 mm'), findsOneWidget);
    expect(find.text('0,00 mm'), findsOneWidget);
    expect(find.text('Ajuste terminado'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('USB desconectado'), findsOneWidget);
    expect(find.text('ALINEACIÓN MOTOR–CAJA'), findsNothing);
    expect(find.text('99,00 mm/100 mm'), findsNothing);
  });

  test('mezcla historial sin ocultar pendientes y ordena fechas mixtas', () {
    const pending = AlignmentMeasurement(
      uuid: 'local-1',
      localizacion: 9,
      sistema: 'BG-1',
      puntos: 1,
      fecha: '28/07/2026',
      hora: '11:00:00',
      valores: {'AMB_ANGULO_V': 0},
      errorSync: 'pendiente',
    );
    const duplicateRemote = AlignmentMeasurement(
      uuid: 'remote-1',
      localizacion: 9,
      sistema: 'BG-1',
      puntos: 1,
      fecha: '28/07/2026',
      hora: '11:00:00',
      valores: {'AMB_ANGULO_V': 0},
      sincronizado: true,
    );
    const olderIso = AlignmentMeasurement(
      uuid: 'remote-2',
      localizacion: 9,
      sistema: 'OTRO SISTEMA',
      puntos: 1,
      fecha: '2026-07-27',
      hora: '12:00:00',
      valores: {'AMB_ANGULO_V': 0},
      sincronizado: true,
    );

    final merged = mergeAlignmentHistory(
      local: const [pending],
      remote: const [duplicateRemote, olderIso],
    );

    expect(merged, hasLength(2));
    expect(merged.first.uuid, 'local-1');
    expect(merged.first.errorSync, 'pendiente');
    expect(merged.last.sistema, 'OTRO SISTEMA');
  });

  testWidgets('historial PUNTOS 6 muestra MOTOR-CAJA y CAJA-BOMBA', (
    tester,
  ) async {
    const measurement = AlignmentMeasurement(
      uuid: 'remote-2',
      localizacion: 20,
      sistema: 'BG-2',
      puntos: 6,
      fecha: '2026-07-28',
      hora: '10:00:00',
      valores: {
        'ACM_ANGULO_V': -0.25,
        'ACM_ANGULO_H': 0,
        'ACM_COMPENSACION_V': 0.1,
        'ACM_COMPENSACION_H': 0.2,
        'ACB_ANGULO_V': 0.3,
        'ACB_ANGULO_H': 0.4,
        'ACB_COMPENSACION_V': 0.5,
        'ACB_COMPENSACION_H': 0.6,
      },
      sincronizado: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AlignmentHistoryCard(measurement: measurement),
          ),
        ),
      ),
    );

    expect(find.text('ALINEACIÓN MOTOR–CAJA'), findsOneWidget);
    expect(find.text('ALINEACIÓN CAJA–BOMBA'), findsOneWidget);
    expect(find.text('Sincronizada'), findsOneWidget);
    expect(find.text('ALINEACIÓN MOTOR–BOMBA'), findsNothing);
  });
}
