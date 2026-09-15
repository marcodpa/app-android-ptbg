import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/data/mock_data.dart';

/// La cantidad y los sistemas vienen de MariaDB, no de una lista fija.
/// El exportador tiene pruebas para catalogos de 51, 56, 57 y 120 equipos.
void main() {
  test('el catalogo base tiene equipos identificables sin cantidad fija', () {
    expect(mockEquipos, isNotEmpty);
    expect(catalogoBaseVersion, greaterThan(0));
    expect(mockEquipos.length, catalogoBaseCantidad);
    expect(DateTime.tryParse(catalogoBaseFechaUtc), isNotNull);
    expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(catalogoBaseSha256), isTrue);
    for (final equipo in mockEquipos) {
      expect(equipo.id, greaterThan(0));
      expect(equipo.localizacion, greaterThan(0));
      expect(equipo.equipo.trim(), isNotEmpty);
      expect(equipo.qrCode, isNotNull);
      expect(equipo.qrCode!.trim(), isNotEmpty);
    }
  });

  test('tipo visual conserva los puntos de MariaDB, incluso cero', () {
    for (final equipo in mockEquipos) {
      expect(equipo.ptEq, equipo.puntos);
    }
  });

  test('ningun equipo del base repite ID', () {
    expect(mockEquipos.map((e) => e.id).toSet().length, mockEquipos.length);
  });

  test('ningun equipo del base repite localizacion', () {
    // La localizacion es la clave con la que se cruzan mediciones, fichas y
    // planillas: una repetida mezclaria el historial de dos equipos.
    final localizaciones = mockEquipos.map((e) => e.localizacion).toList();
    expect(localizaciones.toSet().length, localizaciones.length);
  });
}
