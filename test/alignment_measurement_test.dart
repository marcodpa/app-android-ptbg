import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/alignment_measurement.dart';
import 'package:scv_ptbg/models/alignment_plan.dart';

void main() {
  group('AlignmentPlanResolver', () {
    test('PUNTOS 1, 2 y 9 usan solo MOTOR-BOMBA', () {
      for (final puntos in const [1, 2, 9]) {
        final sections = AlignmentPlanResolver.fromPuntos(puntos);

        expect(sections, hasLength(1));
        expect(sections.single.title, 'ALINEACIÓN MOTOR–BOMBA');
        expect(
          sections
              .expand((section) => section.fields)
              .map((field) => field.column),
          const [
            'AMB_ANGULO_V',
            'AMB_ANGULO_H',
            'AMB_COMPENSACION_V',
            'AMB_COMPENSACION_H',
          ],
        );
      }
    });

    test('PUNTOS 6 usa MOTOR-CAJA y CAJA-BOMBA', () {
      final sections = AlignmentPlanResolver.fromPuntos(6);

      expect(sections, hasLength(2));
      expect(
        sections.map((section) => section.title),
        const ['ALINEACIÓN MOTOR–CAJA', 'ALINEACIÓN CAJA–BOMBA'],
      );
      expect(
        sections
            .expand((section) => section.fields)
            .map((field) => field.column),
        const [
          'ACM_ANGULO_V',
          'ACM_ANGULO_H',
          'ACM_COMPENSACION_V',
          'ACM_COMPENSACION_H',
          'ACB_ANGULO_V',
          'ACB_ANGULO_H',
          'ACB_COMPENSACION_V',
          'ACB_COMPENSACION_H',
        ],
      );
    });

    test('otros tipos no son elegibles', () {
      for (final puntos in const [0, 3, 4, 5, 7, 8, 10]) {
        expect(AlignmentPlanResolver.isEligible(puntos), isFalse);
        expect(AlignmentPlanResolver.fromPuntos(puntos), isEmpty);
      }
    });
  });

  group('parseAlignmentValue', () {
    test('acepta signo, entero y hasta dos decimales con coma', () {
      expect(parseAlignmentValue('-1,03'), -1.03);
      expect(parseAlignmentValue('1,03'), 1.03);
      expect(parseAlignmentValue('0'), 0);
      expect(parseAlignmentValue(' 25,4 '), 25.4);
    });

    test('rechaza punto, más de dos decimales y texto', () {
      expect(parseAlignmentValue('0.05'), isNull);
      expect(parseAlignmentValue('1,234'), isNull);
      expect(parseAlignmentValue(''), isNull);
      expect(parseAlignmentValue('abc'), isNull);
    });
  });

  test('serializa 12 columnas y conserva las no aplicables como NULL', () {
    const measurement = AlignmentMeasurement(
      uuid: 'aln-1',
      localizacion: 12,
      sistema: 'BG-1',
      puntos: 1,
      fecha: '2026-07-28',
      hora: '09:20:00',
      valores: {
        'AMB_ANGULO_V': -1.03,
        'AMB_ANGULO_H': 0.05,
        'AMB_COMPENSACION_V': 0,
        'AMB_COMPENSACION_H': 2.4,
      },
      observaciones: 'Correcto',
      responsable: 'Operador',
      cargo: 'MECÁNICO',
      marca: 'Marca',
      modelo: 'Modelo',
      serial: 'Serie',
      odt: null,
    );

    final db = measurement.toDbMap();
    final restored = AlignmentMeasurement.fromMap(db);

    expect(db['AMB_ANGULO_V'], -1.03);
    expect(db['ACM_ANGULO_V'], isNull);
    expect(db['ACB_COMPENSACION_H'], isNull);
    expect(restored.valores['AMB_ANGULO_V'], -1.03);
    expect(restored.odt, isNull);
    expect(restored.puntos, 1);
    expect(restored.sincronizado, isFalse);
  });

  test('fromRemoteMap conserva texto, signo y estado remoto', () {
    final measurement = AlignmentMeasurement.fromRemoteMap(const {
      'ID': 81,
      'LOCALIZACION': 20,
      'SISTEMA': 'BG-2',
      'PUNTOS': 6,
      'FECHA': '2026-07-28',
      'HORA': '10:00:00',
      'ACM_ANGULO_V': '-0.25',
      'ACB_COMPENSACION_H': '1,05',
      'USUARIO': 'Ana',
      'CARGO': 'Técnico',
      'ODT': null,
    });

    expect(measurement.uuid, 'remote-81');
    expect(measurement.valores['ACM_ANGULO_V'], -0.25);
    expect(measurement.valores['ACB_COMPENSACION_H'], 1.05);
    expect(measurement.responsable, 'Ana');
    expect(measurement.sincronizado, isTrue);
  });
}
