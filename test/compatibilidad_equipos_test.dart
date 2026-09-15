import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/compatibilidad_equipos.dart';

void main() {
  group('familias de compatibilidad', () {
    test('una pieza solo sirve dentro de su familia', () {
      // NOX (2, 3, 9, 10): entre ellas si.
      expect(
        CompatibilidadEquipos.compatible(origen: 2, destino: 10),
        isTrue,
      );
      // Un motor de NOX no sirve en un Fin Fan (15..18).
      expect(
        CompatibilidadEquipos.compatible(origen: 2, destino: 15),
        isFalse,
      );
    });

    test('las familias declaradas agrupan sus ubicaciones', () {
      const pares = <List<int>>[
        [1, 8], // Booster
        [4, 12], // Ventiladores de turbina
        [6, 14], // Ventiladores de generador
        [19, 21], // Arrancador hidraulico
        [20, 22], // Sprint
        [23, 51], // Patines
        [40, 42], // Bombas de transferencia
        [43, 45], // Motores de centrifugadoras
      ];
      for (final par in pares) {
        expect(
          CompatibilidadEquipos.compatible(origen: par[0], destino: par[1]),
          isTrue,
          reason: 'LOC ${par[0]} y ${par[1]} son de la misma familia',
        );
      }
    });

    test('el sistema contra incendio es unico por ubicacion', () {
      // 31, 32 y 33 no comparten piezas ni entre ellas.
      expect(
        CompatibilidadEquipos.compatible(origen: 31, destino: 32),
        isFalse,
      );
      expect(
        CompatibilidadEquipos.compatible(origen: 31, destino: 31),
        isTrue,
      );
    });

    test('una pieza nueva sirve para cualquier equipo', () {
      // Sin ubicacion previa no hay dato para decidir: esconderla dejaria al
      // mecanico sin repuesto por falta de informacion, no por incompatibilidad.
      for (final destino in const [1, 15, 31, 43]) {
        expect(
          CompatibilidadEquipos.compatible(origen: null, destino: destino),
          isTrue,
        );
        expect(
          CompatibilidadEquipos.compatible(origen: 0, destino: destino),
          isTrue,
        );
      }
    });

    test('ninguna ubicacion aparece en dos familias', () {
      final vistas = <int, int>{};
      for (final familia in CompatibilidadEquipos.familias) {
        for (final ubicacion in familia.ubicaciones) {
          expect(
            vistas.containsKey(ubicacion),
            isFalse,
            reason: 'LOC $ubicacion esta en las familias '
                '${vistas[ubicacion]} y ${familia.id}',
          );
          vistas[ubicacion] = familia.id;
        }
      }
    });
  });
}
