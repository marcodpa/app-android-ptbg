import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:scv_ptbg/db/recent_services.dart';
import 'package:scv_ptbg/models/servicio_reciente.dart';

class ReadOnlyHistoryDb implements DatabaseExecutor {
  ReadOnlyHistoryDb(this.tables);
  final Map<String, List<Map<String, Object?>>> tables;
  final queries = <String>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    queries.add(sql);
    if (sql.contains('sqlite_master')) {
      return tables.keys
          .map((name) => <String, Object?>{'name': name})
          .toList();
    }
    final table = RegExp(r'FROM (\w+)').firstMatch(sql)!.group(1)!;
    return tables[table]!
        .where((row) =>
            !sql.contains('sincronizado = 1') || row['sincronizado'] == 1)
        .map((row) => <String, Object?>{
              ...row,
              if (sql.contains('NULL AS localizacion')) 'localizacion': null,
            })
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'No se permite escribir datos: ${invocation.memberName}');
}

Map<String, Object?> vibration(int loc, String date, String time) => {
      'localizacion': loc,
      'fecha': date,
      'hora': time,
      'fecha_hora_iso': '${date}T$time',
    };

List<String> cards(List<ServicioReciente> rows) => rows
    .map((row) =>
        '${row.tipo.codigo}|${row.localizacion}|${row.fecha}|${row.hora}')
    .toList();

void main() {
  test('tablet nueva y antigua muestran mismas vibraciones del 16', () async {
    final remote = [
      vibration(26, '2026-09-16', '10:43:24'),
      vibration(27, '2026-09-16', '10:27:43'),
      vibration(28, '2026-09-16', '10:22:01'),
      vibration(23, '2026-09-15', '08:39:22'),
    ];
    final r7 = ReadOnlyHistoryDb({
      'MEDICIONES_REMOTAS': remote,
      'MEDICIONES_LOCAL':
          remote.map((row) => {...row, 'sincronizado': 1}).toList(),
    });
    final r9 = ReadOnlyHistoryDb({
      'MEDICIONES_REMOTAS': remote.reversed.toList(),
      'MEDICIONES_LOCAL': [],
    });
    final oldTablet = await RecentServices.read(r7);
    expect(cards(await RecentServices.read(r9)), cards(oldTablet));
    expect(oldTablet.map((row) => row.localizacion), [26, 27, 28, 23]);
    expect(r7.queries.any((sql) => sql.contains('FROM MEDICIONES_LOCAL')),
        isFalse);
  });

  test('no revive mediciones borradas del espejo ni incluye pendientes',
      () async {
    final local = [
      {...vibration(26, '2026-09-22', '10:43:24'), 'sincronizado': 1},
      {...vibration(27, '2026-09-22', '10:43:24'), 'sincronizado': 0},
    ];
    final db = ReadOnlyHistoryDb(
        {'MEDICIONES_REMOTAS': [], 'MEDICIONES_LOCAL': local});
    expect(await RecentServices.read(db), isEmpty);
    expect(db.tables['MEDICIONES_LOCAL'], local);
  });

  test('normaliza fechas antes de limitar y no duplica tarjetas', () {
    final rows = [
      {
        'servicio': 'vibracion',
        'localizacion': 26,
        'fecha': '16/09/2026',
        'hora': '10:43:24'
      },
      {'servicio': 'vibracion', ...vibration(26, '2026-09-16', '10:43:24')},
      {
        'servicio': 'vibracion',
        'localizacion': 27,
        'fecha': '30/01/2026',
        'hora': '15:00'
      },
      {
        'servicio': 'temperatura',
        'localizacion': 26,
        'fecha': '2026-09-16',
        'hora': '10:43:24'
      },
      {
        'servicio': 'checklist_compresor',
        'localizacion': 55,
        'fecha': '3/9/2026',
        'hora': '9:04'
      },
    ];
    final result = RecentServices.ordered(rows);
    expect(result, hasLength(4));
    expect(result.first.fecha, '2026-09-16');
    expect(result[2].fecha, '2026-09-03');
    expect(result.last.fecha, '2026-01-30');
    expect(
        cards(RecentServices.ordered(rows.reversed.toList())), cards(result));
  });

  test('tablas ausentes no ocultan otras; checklist pendiente no aparece',
      () async {
    final db = ReadOnlyHistoryDb({
      'CHECKLIST_BLACK_START_LOCAL': [
        {'fecha': '2026-09-03', 'hora': '10:00', 'sincronizado': 1},
        {'fecha': '2026-09-22', 'hora': '10:00', 'sincronizado': 0},
      ],
      'MEDICIONES_REMOTAS': [vibration(26, '2026-09-16', '10:43:24')],
    });
    final result = await RecentServices.read(db);
    expect(result, hasLength(2));
    expect(result.first.tipo, TipoServicio.vibracion);
    expect(result.last.tipo, TipoServicio.blackStart);
    expect(result.last.localizacion, isNull);
  });

  test('todos los tipos incluidos se reconocen y los espejos no usan locales',
      () {
    for (final name in {
      ...RecentServices.remoteSources,
      ...RecentServices.localSources
    }.keys) {
      expect(TipoServicio.porCodigo(name), isNotNull);
    }
    expect(RecentServices.remoteSources.keys.toSet(),
        {'vibracion', 'temperatura', 'alineacion', 'lubricacion'});
    expect(
        RecentServices.remoteSources.keys
            .toSet()
            .intersection(RecentServices.localSources.keys.toSet()),
        isEmpty);
  });

  test('limite cero y tipos desconocidos no quitan espacio a servicios validos',
      () {
    final rows = [
      {'servicio': 'desconocido', 'fecha': '2026-10-01', 'hora': '10:00'},
      {'servicio': 'vibracion', ...vibration(1, '2026-09-16', '10:00:00')},
    ];
    expect(RecentServices.ordered(rows, limit: 0), isEmpty);
    expect(RecentServices.ordered(rows, limit: 1).single.tipo,
        TipoServicio.vibracion);
  });
}
