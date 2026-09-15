import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/historial_servicio.dart';

/// El criterio unico de "los ultimos N" de un equipo. Estos casos vienen de
/// datos reales de la tablet: MariaDB guarda la fecha como texto en varios
/// formatos y el orden alfabetico ponia el 30 de enero por encima del 14 de
/// julio.
void main() {
  group('claveHistorial', () {
    test('manda fecha_hora_iso cuando existe', () {
      expect(
        claveHistorial({
          'fecha': '16/06/2026',
          'hora': '12:38:26',
          'fecha_hora_iso': '2026-06-16T12:38:26',
        }),
        '2026-06-16T12:38:26',
      );
    });

    test('normaliza los cinco formatos vistos en MOT_VIBR_MUES', () {
      expect(claveHistorial({'fecha': '2026-08-25', 'hora': '08:15:07'}),
          '2026-08-25T08:15:07');
      expect(claveHistorial({'fecha': '30/01/2026', 'hora': '15:00'}),
          '2026-01-30T15:00:00');
      expect(claveHistorial({'fecha': '5/8/2026', 'hora': '9:30'}),
          '2026-08-05T09:30:00');
      // Un DATETIME de MariaDB llega con la medianoche pegada.
      expect(claveHistorial({'fecha': '2026-08-25 00:00:00', 'hora': '10:07:43'}),
          '2026-08-25T10:07:43');
      // Un iso en el epoch delata fecha ilegible: no manda.
      expect(claveHistorial({'fecha': '2026-08-25', 'hora': '08:00:00',
              'fecha_hora_iso': '1970-01-01T00:00:00'}),
          '2026-08-25T08:00:00');
    });

    test('lo ilegible se va al fondo, nunca arriba', () {
      expect(claveHistorial({'fecha': 'SIN FECHA', 'hora': ''}),
          '0000-01-01T00:00:00');
    });
  });

  group('depurarYOrdenarHistorial', () {
    test('el 27 de marzo le gana al 30 de enero aunque el texto diga otra cosa',
        () {
      final filas = depurarYOrdenarHistorial([
        {'fecha': '30/01/2026', 'hora': '15:00', '_source': 'MEDICIONES_REMOTAS'},
        {'fecha': '27/03/2026', 'hora': '08:00', '_source': 'MEDICIONES_REMOTAS'},
        {'fecha': '2026-07-14', 'hora': '10:07:43', '_source': 'MEDICIONES_REMOTAS'},
      ]);
      expect(filas.map((f) => f['fecha']).toList(),
          ['2026-07-14', '27/03/2026', '30/01/2026']);
    });

    test('la copia remota de una medicion ya sincronizada no duplica', () {
      final filas = depurarYOrdenarHistorial([
        {
          'uuid': 'u-1',
          'fecha': '2026-08-25',
          'hora': '08:15:07',
          'odt': 4521,
          '_source': 'MEDICIONES_LOCAL',
        },
        {
          'remote_key': 'ID:88',
          'fecha': '2026-08-25',
          'hora': '08:15:07',
          'fecha_hora_iso': '2026-08-25T08:15:07',
          '_source': 'MEDICIONES_REMOTAS',
        },
      ]);
      expect(filas, hasLength(1));
      // Gana la local: es la que tiene ODT y observaciones completas.
      expect(filas.single['uuid'], 'u-1');
    });

    test('un reemplazo con varias piezas al mismo instante conserva todas', () {
      final filas = depurarYOrdenarHistorial([
        {'uuid': 'r-motor', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'REEMPLAZOS_LOCAL'},
        {'uuid': 'r-bomba', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'REEMPLAZOS_LOCAL'},
      ]);
      expect(filas, hasLength(2));
    });

    test('dos remotas del mismo instante colapsan en una', () {
      final filas = depurarYOrdenarHistorial([
        {'remote_key': 'ID:1', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'MEDICIONES_REMOTAS'},
        {'remote_key': 'ID:2', 'fecha': '20/08/2026', 'hora': '10:00',
          '_source': 'MEDICIONES_REMOTAS'},
      ]);
      expect(filas, hasLength(1));
    });

    test('con lista vacia devuelve lista vacia, sin lanzar', () {
      expect(depurarYOrdenarHistorial([]), isEmpty);
    });

    test('local y remota separadas por UN segundo NO colapsan', () {
      // El dedupe agrupa por instante exacto. Si el reloj de MariaDB guardo
      // la copia con un segundo de diferencia, son instantes distintos y se
      // conservan ambas: preferible un duplicado visible a perder una fila.
      final filas = depurarYOrdenarHistorial([
        {'uuid': 'u-1', 'fecha': '2026-08-25', 'hora': '08:15:07',
          '_source': 'MEDICIONES_LOCAL'},
        {'remote_key': 'ID:88', 'fecha': '2026-08-25', 'hora': '08:15:08',
          'fecha_hora_iso': '2026-08-25T08:15:08',
          '_source': 'MEDICIONES_REMOTAS'},
      ]);
      expect(filas, hasLength(2));
      // Y la remota (un segundo despues) queda arriba por ser mas reciente.
      expect(filas.first['remote_key'], 'ID:88');
    });

    test('dos locales de TABLAS distintas al mismo instante se conservan', () {
      // Un check list y una medicion pueden compartir instante si se
      // guardaron en la misma pasada. Ambas terminan en '_LOCAL' y ambas son
      // verdad: ninguna es copia de la otra, ninguna debe sobrar.
      final filas = depurarYOrdenarHistorial([
        {'uuid': 'm-1', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'MEDICIONES_LOCAL'},
        {'uuid': 'c-1', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'CHECKLIST_COMPRESOR_LOCAL'},
      ]);
      expect(filas, hasLength(2));
    });

    test('el orden de entrada se respeta entre filas con la misma clave', () {
      // Tres piezas de un reemplazo al mismo instante: el orden en que se
      // escribieron (motor, bomba, acople) es el orden en que el tecnico las
      // registro y asi deben listarse siempre, corrida tras corrida.
      final filas = depurarYOrdenarHistorial([
        {'uuid': 'r-motor', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'REEMPLAZOS_LOCAL'},
        {'uuid': 'r-bomba', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'REEMPLAZOS_LOCAL'},
        {'uuid': 'r-acople', 'fecha': '2026-08-20', 'hora': '10:00:00',
          '_source': 'REEMPLAZOS_LOCAL'},
        // Una fila de otro dia en medio no debe alterar ese orden relativo.
        {'uuid': 'viejo', 'fecha': '2026-08-19', 'hora': '09:00:00',
          '_source': 'MEDICIONES_LOCAL'},
      ]);
      expect(filas.map((f) => f['uuid']).toList(),
          ['r-motor', 'r-bomba', 'r-acople', 'viejo']);
    });
  });

  group('claveHistorial adversario', () {
    test('el 29 de febrero de un anio no bisiesto pasa como clave valida', () {
      // 2026 no es bisiesto: el 29/02/2026 no existe en el calendario. La
      // funcion solo valida rangos (dia 1-31, mes 1-12), no el calendario
      // real, asi que produce '2026-02-29' en vez de mandarlo al fondo.
      // COMPORTAMIENTO DOCUMENTADO: una fecha imposible pero "bien formada"
      // ordena como si existiera. Para ordenar es inocuo (queda entre el 28/02
      // y el 01/03); no se considera bug porque la clave es solo para ordenar.
      expect(claveHistorial({'fecha': '29/02/2026', 'hora': '08:00'}),
          '2026-02-29T08:00:00');
      // El rango si se valida: dia 32 o mes 13 van al fondo.
      expect(claveHistorial({'fecha': '32/01/2026', 'hora': '08:00'}),
          '0000-01-01T00:00:00');
      expect(claveHistorial({'fecha': '01/13/2026', 'hora': '08:00'}),
          '0000-01-01T00:00:00');
    });

    test('fecha vacia y fila sin ninguna clave van al fondo', () {
      expect(claveHistorial({'fecha': '', 'hora': '10:00:00'}),
          '0000-01-01T00:00:00');
      // Una fila totalmente huerfana (sin fecha, hora ni iso) tampoco lanza.
      expect(claveHistorial({}), '0000-01-01T00:00:00');
      // Con null explicito en las tres columnas, igual.
      expect(
        claveHistorial({'fecha': null, 'hora': null, 'fecha_hora_iso': null}),
        '0000-01-01T00:00:00',
      );
    });

    test("hora '9:5' (minutos de un digito) no se entiende y cae a medianoche",
        () {
      // Los formatos reconocidos exigen minutos de dos digitos. '9:5' no
      // aparece en las tablas reales; si llegara, la fila conserva su fecha
      // pero pierde la hora: ordena como las 00:00:00 de ese dia.
      // COMPORTAMIENTO DOCUMENTADO, no bug: degrada con gracia, no lanza.
      expect(claveHistorial({'fecha': '2026-08-25', 'hora': '9:5'}),
          '2026-08-25T00:00:00');
    });

    test('un fecha_hora_iso corto (solo fecha) no manda: cae a fecha y hora',
        () {
      // La columna normalizada debe traer los 19 caracteres completos
      // ('2026-08-25T08:15:07'). Si un sync viejo dejo solo la fecha, se
      // ignora y la clave se arma con las columnas crudas.
      expect(
        claveHistorial({
          'fecha_hora_iso': '2026-08-25',
          'fecha': '26/08/2026',
          'hora': '07:00',
        }),
        '2026-08-26T07:00:00',
      );
      // Y si ademas la fecha cruda es ilegible, al fondo: el iso corto no
      // rescata ni siquiera su propia fecha.
      expect(claveHistorial({'fecha_hora_iso': '2026-08-25'}),
          '0000-01-01T00:00:00');
    });
  });
}
