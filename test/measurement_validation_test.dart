import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/measurement_validation.dart';
import 'package:scv_ptbg/models/measurement_quality.dart';

void main() {
  group('validaciones numéricas', () {
    test('acepta coma y punto decimal', () {
      expect(MeasurementValidation.parseDecimal('12,5'), 12.5);
      expect(MeasurementValidation.parseDecimal('-2.25'), -2.25);
    });

    test('rechaza formatos ambiguos y valores no numéricos', () {
      expect(MeasurementValidation.parseDecimal('1.2.3'), isNull);
      expect(MeasurementValidation.parseDecimal('12 °C'), isNull);
      expect(MeasurementValidation.parseDecimal('NaN'), isNull);
      expect(MeasurementValidation.parseDecimal('Infinity'), isNull);
    });

    test('valida límites de temperatura', () {
      expect(
        MeasurementValidation.requiredRange(
          '-100',
          min: MeasurementValidation.temperatureMin,
          max: MeasurementValidation.temperatureMax,
          unit: '°C',
        ),
        isNull,
      );
      expect(
        MeasurementValidation.requiredRange(
          '1001',
          min: MeasurementValidation.temperatureMin,
          max: MeasurementValidation.temperatureMax,
          unit: '°C',
        ),
        contains('Rango permitido'),
      );
    });

    test('rechaza negativos en vibración y lubricación', () {
      expect(
        MeasurementValidation.requiredRange(
          '-1',
          min: MeasurementValidation.vibrationMin,
          max: MeasurementValidation.vibrationMax,
          unit: 'mm/s',
        ),
        isNotNull,
      );
      expect(
        MeasurementValidation.requiredRange(
          '-0,1',
          min: MeasurementValidation.lubricationMin,
          max: MeasurementValidation.lubricationMax,
          unit: 'g',
        ),
        isNotNull,
      );
    });
  });

  group('alertas informativas no bloqueantes', () {
    test('vibración 30 muestra Alto inmediatamente', () {
      expect(VibrationQuality.fromValue(30).label, 'Alto');
      expect(VibrationQuality.fromValue(3).label, 'Bajo');
      expect(VibrationQuality.fromValue(6).label, 'Medio');
      expect(VibrationQuality.fromValue(55).label, 'Muy alto');
    });
    test('temperatura cambia entre varios niveles', () {
      expect(MeasurementAdvisory.temperature(50).level,
          MeasurementAdvisoryLevel.normal);
      expect(MeasurementAdvisory.temperature(85).level,
          MeasurementAdvisoryLevel.attention);
      expect(MeasurementAdvisory.temperature(110).level,
          MeasurementAdvisoryLevel.high);
      expect(MeasurementAdvisory.temperature(180).level,
          MeasurementAdvisoryLevel.critical);
    });

    test('alineación y lubricación generan avisos sin invalidar el número', () {
      expect(MeasurementAdvisory.alignment(.25).level,
          MeasurementAdvisoryLevel.high);
      expect(MeasurementAdvisory.lubrication(200, 100).level,
          MeasurementAdvisoryLevel.critical);
      expect(MeasurementValidation.requiredNumber('200'), isNull);
    });
  });
}
