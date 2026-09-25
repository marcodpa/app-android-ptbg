import 'package:sqflite/sqflite.dart';

import '../models/historial_servicio.dart';
import '../models/servicio_reciente.dart';

/// Lee el mismo espejo de la planta que usa el historial por equipo.
/// No mezcla copias locales sincronizadas con tablas remotas: hacerlo causa
/// duplicados y resucita registros eliminados o corregidos en MariaDB.
class RecentServices {
  static const remoteSources = <String, String>{
    'vibracion': 'MEDICIONES_REMOTAS',
    'temperatura': 'TEMPERATURAS_REMOTAS',
    'lubricacion': 'LUBRICACIONES_REMOTAS',
    'alineacion': 'ALINEACIONES_REMOTAS',
  };

  // Estos servicios todavia usan una unica tabla local para su historial.
  static const localSources = <String, String>{
    'reemplazo': 'REEMPLAZOS_LOCAL',
    'coupling': 'CAMBIOS_COUPLING_LOCAL',
    'limpieza_plato': 'LIMPIEZAS_PLATO_LOCAL',
    'checklist_compresor': 'CHECKLIST_COMPRESOR_LOCAL',
    'black_start': 'CHECKLIST_BLACK_START_LOCAL',
  };

  static Future<List<ServicioReciente>> read(DatabaseExecutor db,
      {int limit = 4}) async {
    if (limit <= 0) return const [];
    final existing = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
        .map((row) => row['name'].toString())
        .toSet();
    final rows = <Map<String, dynamic>>[];
    for (final source in {...remoteSources, ...localSources}.entries) {
      // Una tabla opcional ausente no debe ocultar el resto del historial.
      if (!existing.contains(source.value)) continue;
      final remote = remoteSources.containsKey(source.key);
      final location =
          source.key == 'black_start' ? 'NULL AS localizacion' : 'localizacion';
      final values = await db.rawQuery(
        'SELECT $location, fecha, hora'
        '${remote ? ', fecha_hora_iso' : ''} FROM ${source.value}'
        '${remote ? '' : ' WHERE sincronizado = 1'}',
      );
      rows.addAll(values.map((row) => <String, dynamic>{
            ...row,
            'servicio': source.key,
          }));
    }
    return ordered(rows, limit: limit);
  }

  /// Las fechas antiguas de planta pueden ser d/M/yyyy. Normaliza antes de
  /// limitar, con el mismo criterio que el historial y el PDF. Los empates
  /// se resuelven de forma estable, independientemente del orden de descarga.
  static List<ServicioReciente> ordered(List<Map<String, dynamic>> rows,
      {int limit = 4}) {
    if (limit <= 0) return const [];
    final unique = <String, ServicioReciente>{};
    for (final row in rows) {
      if (TipoServicio.porCodigo(row['servicio']?.toString()) == null) continue;
      final time = claveHistorial(row);
      final normalized = ServicioReciente.deFila({
        ...row,
        if (!time.startsWith('0000')) 'fecha': time.substring(0, 10),
        if (!time.startsWith('0000')) 'hora': time.substring(11),
      })!;
      final key = '$time|${normalized.tipo.codigo}|'
          '${normalized.localizacion?.toString().padLeft(12, '0') ?? ''}';
      // Una tarjeta por servicio/equipo/instante. No se modifica ninguna
      // fila del historial (un reemplazo puede tener varios componentes).
      unique.putIfAbsent(key, () => normalized);
    }
    final keys = unique.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.take(limit).map((key) => unique[key]!).toList();
  }
}
