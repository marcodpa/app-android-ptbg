import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/equipo_visual_config.dart';
import 'package:scv_ptbg/models/measurement_quality.dart';
import 'package:scv_ptbg/models/models.dart';

Equipo _equipo({
  required int localizacion,
  required String nombre,
  required int ptEq,
}) {
  return Equipo(
    id: localizacion,
    codeSys: 1,
    equipo: nombre,
    localizacion: localizacion,
    qrCode: 'PTBG-${localizacion.toString().padLeft(3, '0')}',
    puntos: 4,
    ptEq: ptEq,
    sistema: localizacion < 8 ? 'TURBINA BG-1' : 'TURBINA BG-2',
  );
}

void main() {
  group('preview visual por QR', () {
    test('mantiene imagen de ventiladores aunque PUNTOS venga como finfan', () {
      for (final lc in [4, 5, 6, 7, 11, 12, 13, 14]) {
        final config = EquipoVisualResolver.previewFromEquipo(
          _equipo(localizacion: lc, nombre: 'VENT TURB A', ptEq: 5),
        );

        expect(config.id, 'ventiladores');
        expect(config.cleanAsset, 'assets/images/visual_ventiladores.jpg');
      }
    });

    test('mantiene imagen de finfan aunque PUNTOS venga como ventilador', () {
      for (final lc in [15, 16, 17, 18]) {
        final config = EquipoVisualResolver.previewFromEquipo(
          _equipo(localizacion: lc, nombre: 'FINFAN A', ptEq: 4),
        );

        expect(config.id, 'finfan');
        expect(config.cleanAsset, 'assets/images/visual_finfan.jpg');
      }
    });
  });

  group('puntos visuales sprint y jockey', () {
    test('jockey muestra dos puntos de motor y dos de bomba', () {
      final config = EquipoVisualResolver.fromEquipo(
        _equipo(localizacion: 32, nombre: '10FW-02', ptEq: 7),
      );

      expect(config.puntos.map((p) => p.nombre), [
        'Motor - lado libre',
        'Motor - lado acople',
        'Bomba - lado acople',
        'Bomba - lado libre',
      ]);
    });

    test('sprint muestra dos puntos de motor y dos de bomba', () {
      final config = EquipoVisualResolver.fromEquipo(
        _equipo(localizacion: 20, nombre: 'SPRINT', ptEq: 8),
      );

      expect(config.puntos.map((p) => p.nombre), [
        'Motor - lado libre',
        'Motor - lado acople',
        'Bomba - lado acople',
        'Bomba - lado libre',
      ]);
    });
  });

  group('puntos visuales NOX', () {
    test('intercambia solo posicion visual de puntos 5 y 6', () {
      final config = EquipoVisualResolver.fromEquipo(
        _equipo(localizacion: 1, nombre: 'NOX LIQUIDA', ptEq: 6),
      );

      final p5 = config.punto(5);
      final p6 = config.punto(6);

      expect(config.id, 'nox');
      expect(p5.nombre, 'Bomba lado acople');
      expect(p5.x, 0.7328);
      expect(p5.y, 0.5420);
      expect(p6.nombre, 'Bomba lado libre');
      expect(p6.x, 0.6556);
      expect(p6.y, 0.4403);
    });
  });

  group('indicador de vibracion', () {
    test('clasifica valores normales, alerta y error probable', () {
      expect(
          VibrationQuality.fromValue(null).level, VibrationQualityLevel.empty);
      expect(
          VibrationQuality.fromValue(2.7).level, VibrationQualityLevel.normal);
      expect(
          VibrationQuality.fromValue(5.0).level, VibrationQualityLevel.warning);
      expect(
          VibrationQuality.fromValue(12.0).level, VibrationQualityLevel.danger);
      expect(VibrationQuality.fromValue(55.0).level,
          VibrationQualityLevel.extreme);
    });
  });
}
