import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/data/mock_data.dart';
import 'package:scv_ptbg/models/qr_code_matcher.dart';

void main() {
  test('reconoce QR nuevos generados con CODE_QR exacto', () {
    final examples = <String, int>{
      '11-MOT-6241': 1,
      '12-MOT-6090': 18,
      'SCI ELECTRIC MOTOR': 31,
      'DIESEL MOTOR': 32,
      'JOCKEY MOTOR': 33,
      '17-06-DO_EM101_S': 43,
      '10-RW-CP-002B': 51,
    };

    for (final entry in examples.entries) {
      final keys = qrKeys(entry.key);
      final equipo = mockEquipos.firstWhere(
        (e) => equipoMatchesQr(e, keys),
        orElse: () => throw StateError('No encontro ${entry.key}'),
      );
      expect(equipo.localizacion, entry.value);
    }
  });

  test('respeta letra final cuando varios QR comparten los mismos numeros', () {
    final examples = <String, int>{
      '11-DW-CP-002A': 23,
      '11-DW-CP-002B': 24,
      '11-DW-CP-002C': 25,
      '11-FO-CP-004A': 34,
      '11-FO-CP-004B': 35,
      '11-FO-CP-004C': 36,
      '10-PW-CP-001A': 48,
      '10-PW-CP-001B': 49,
      '10-RW-CP-002A': 50,
      '10-RW-CP-002B': 51,
    };

    for (final entry in examples.entries) {
      final equipo = mockEquipos.firstWhere(
        (e) => equipoMatchesQr(e, qrKeys(entry.key)),
        orElse: () => throw StateError('No encontro ${entry.key}'),
      );
      expect(equipo.localizacion, entry.value);
    }
  });

  test('mantiene compatibilidad con QR numericos viejos', () {
    expect(qrKeys('PTBG-004'), contains('4'));
    expect(qrKeys('LOC-004'), contains('4'));
    expect(qrKeys('6241'), contains('MOT-6241'));
    expect(qrKeys('11-DW-CP-002B'), isNot(contains('11002')));
  });

  test('extrae CODE_QR desde URL, JSON y texto con llave', () {
    final variants = <String>[
      'https://ptbg.local/equipo?CODE_QR=11-MOT-6241',
      '{"CODE_QR":"11-MOT-6241"}',
      'QR_CONTENT=11-MOT-6241',
      'qr_code=11-MOT-6241&origen=impreso',
    ];

    for (final raw in variants) {
      final equipo = mockEquipos.firstWhere(
        (e) => equipoMatchesQr(e, qrKeys(raw)),
        orElse: () => throw StateError('No encontro $raw'),
      );
      expect(equipo.localizacion, 1);
    }
  });
}
