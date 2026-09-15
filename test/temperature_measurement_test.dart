import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/equipo_visual_config.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/temperature_measurement.dart';
import 'package:scv_ptbg/models/temperature_plan.dart';

void main() {
  group('TemperaturePlanResolver', () {
    test('mapea motor y bomba a T1 T2 T5 T6', () {
      for (final puntos in const [1, 2, 3, 7, 8, 9, 0]) {
        expect(
          TemperaturePlanResolver.fromPuntos(puntos)
              .map((step) => step.dbColumn),
          const ['T1', 'T2', 'T5', 'T6'],
        );
      }
    });

    test('incluye correa T10 en FIN-FAN', () {
      final plan = TemperaturePlanResolver.fromPuntos(4);

      expect(
          plan.map((step) => step.dbColumn), const ['T1', 'T2', 'T9', 'T10']);
      expect(plan.last.label, 'Correa (FIN-FAN)');
      expect(plan.last.visualPointNumber, 4);
    });

    test('mapea ventilador a T7 y T8', () {
      expect(
        TemperaturePlanResolver.fromPuntos(5).map((step) => step.dbColumn),
        const ['T1', 'T2', 'T7', 'T8'],
      );
    });

    test('mapea motor caja y bomba a T1 hasta T6', () {
      expect(
        TemperaturePlanResolver.fromPuntos(6).map((step) => step.dbColumn),
        const ['T1', 'T2', 'T3', 'T4', 'T5', 'T6'],
      );
    });
  });

  test('TemperatureMeasurement conserva decimales y ODT nulo', () {
    const measurement = TemperatureMeasurement(
      uuid: 'temp-1',
      localizacion: 12,
      sistema: 'BG-1',
      fecha: '2026-07-22',
      hora: '10:30:00',
      valores: {'T1': 41.5, 'T2': 42},
      observaciones: 'Normal',
      responsable: 'Operador',
      cargo: 'MECANICO',
      odt: null,
    );

    final restored = TemperatureMeasurement.fromMap(measurement.toDbMap());

    expect(restored.valores, {'T1': 41.5, 'T2': 42.0});
    expect(restored.odt, isNull);
    expect(parseTemperature('40,25'), 40.25);
    expect(parseTemperature('texto'), isNull);
  });

  test('TemperatureReading interpreta T1 a T10', () {
    final reading = TemperatureReading.fromJson(const {
      'LOCALIZACION': 4,
      'FECHA': '2026-07-22',
      'HORA': '09:00:00',
      'T1': '39,5',
      'T10': 51,
    });

    expect(reading.valores, {'T1': 39.5, 'T10': 51.0});
    expect(reading.fechaHora, DateTime(2026, 7, 22, 9));
  });

  test('el plan de temperatura usa referencias visuales distintas', () {
    const finFan = Equipo(
      id: 1,
      codeSys: 1,
      equipo: 'FIN-FAN',
      localizacion: 15,
      puntos: 4,
      ptEq: 4,
      sistema: 'BG-1',
    );
    const ventilador = Equipo(
      id: 2,
      codeSys: 1,
      equipo: 'VENTILADOR',
      localizacion: 4,
      puntos: 4,
      ptEq: 5,
      sistema: 'BG-1',
    );

    final finFanVisual = EquipoVisualResolver.fromEquipo(finFan);
    final ventiladorVisual = EquipoVisualResolver.fromEquipo(ventilador);

    expect(finFanVisual.punto(4).nombre, 'Correa FIN-FAN');
    final punto3 = ventiladorVisual.punto(3);
    final punto4 = ventiladorVisual.punto(4);
    expect(Offset(punto3.x, punto3.y), isNot(Offset(punto4.x, punto4.y)));
  });
}
