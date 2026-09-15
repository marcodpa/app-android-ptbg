import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/compatibilidad_equipos.dart';
import 'package:scv_ptbg/models/equipo_nuevo.dart';

void main() {
  setUp(() => CompatibilidadEquipos.cargarAsignadas(const {}));

  group('que piezas lleva cada tipo de equipo', () {
    test('el tipo 6 (NOX) lleva caja y bomba ademas del motor', () {
      expect(EquipoNuevo.tiposDePieza(6), [3, 2]);
    });

    test('los tipos de bomba llevan bomba', () {
      for (final tipo in [1, 2, 3, 7, 8, 9]) {
        expect(EquipoNuevo.tiposDePieza(tipo), [2], reason: 'tipo $tipo');
      }
    });

    test('los ventiladores llevan ventilador', () {
      for (final tipo in [4, 5]) {
        expect(EquipoNuevo.tiposDePieza(tipo), [4], reason: 'tipo $tipo');
      }
    });

    test('un tipo fuera de 1..9 no declara piezas', () {
      expect(EquipoNuevo.tiposDePieza(0), isEmpty);
      expect(EquipoNuevo.tiposDePieza(10), isEmpty);
    });
  });

  group('familia de un equipo registrado en campo', () {
    test('sin familia asignada queda aislado', () {
      // Es el comportamiento de un equipo unico: solo recibe lo que salio de el.
      expect(
        CompatibilidadEquipos.compatible(origen: 2, destino: 52),
        isFalse,
      );
    });

    test('al asignarle una familia acepta las piezas de esa familia', () {
      // La 52 se declara del grupo NOX, que son las ubicaciones 2, 3, 9 y 10.
      CompatibilidadEquipos.cargarAsignadas(const {52: 2});
      expect(CompatibilidadEquipos.compatible(origen: 2, destino: 52), isTrue);
      expect(CompatibilidadEquipos.compatible(origen: 9, destino: 52), isTrue);
      // Y sigue rechazando las de otra familia.
      expect(CompatibilidadEquipos.compatible(origen: 1, destino: 52), isFalse);
    });

    test('tambien en sentido contrario: su pieza sirve en la familia', () {
      CompatibilidadEquipos.cargarAsignadas(const {52: 2});
      expect(CompatibilidadEquipos.compatible(origen: 52, destino: 3), isTrue);
      expect(CompatibilidadEquipos.compatible(origen: 52, destino: 4), isFalse);
    });

    test('cargar de nuevo reemplaza, no acumula', () {
      // La planta manda: si alli le corrigieron la familia, la vieja no puede
      // sobrevivir en la tablet.
      CompatibilidadEquipos.cargarAsignadas(const {52: 2});
      CompatibilidadEquipos.cargarAsignadas(const {52: 1});
      expect(CompatibilidadEquipos.compatible(origen: 2, destino: 52), isFalse);
      expect(CompatibilidadEquipos.compatible(origen: 8, destino: 52), isTrue);
    });

    test('no altera las 51 ubicaciones originales', () {
      CompatibilidadEquipos.cargarAsignadas(const {52: 2});
      expect(CompatibilidadEquipos.compatible(origen: 4, destino: 5), isTrue);
      expect(CompatibilidadEquipos.compatible(origen: 4, destino: 6), isFalse);
      expect(CompatibilidadEquipos.compatible(origen: 31, destino: 32), isFalse);
    });
  });
}
