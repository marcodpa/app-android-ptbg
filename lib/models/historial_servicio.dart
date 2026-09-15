/// El criterio unico para ordenar y depurar el historial de un equipo.
///
/// Existia una version distinta de "los ultimos 5" en cada sitio: la pantalla
/// ordenaba texto, el PDF parseaba fechas con otra receta y MariaDB tiene las
/// suyas guardadas en cinco formatos ('2026-08-25', '25/08/2026', '5/8/2026',
/// con y sin hora pegada). Por eso el reporte, la tablet y la base no
/// coincidian. Este es ahora EL criterio; equipment_report.py aplica el mismo
/// del lado de la laptop.
library;

/// Clave ISO ordenable ('2026-08-25T08:15:07') para una fila de historial.
///
/// Prefiere fecha_hora_iso (la columna ya normalizada que traen las tablas
/// REMOTAS); si no existe o quedo en el epoch (fecha ilegible), normaliza
/// fecha y hora a mano. Lo ilegible se va al fondo, nunca arriba.
String claveHistorial(Map<String, dynamic> fila) {
  final iso = (fila['fecha_hora_iso'] ?? '').toString().trim();
  if (iso.length >= 19 && !iso.startsWith('1970')) {
    return iso.substring(0, 19);
  }
  final fecha = _fechaIso((fila['fecha'] ?? '').toString());
  if (fecha == null) return '0000-01-01T00:00:00';
  return '${fecha}T${_horaNormalizada((fila['hora'] ?? '').toString())}';
}

String? _fechaIso(String cruda) {
  // 'DATETIME' de MariaDB llega como '2026-08-25 00:00:00': la hora sobra.
  var texto = cruda.trim();
  final espacio = texto.indexOf(' ');
  if (espacio > 0) texto = texto.substring(0, espacio);

  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(texto)) return texto;

  final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(texto);
  if (dmy != null) {
    final dia = int.parse(dmy.group(1)!);
    final mes = int.parse(dmy.group(2)!);
    if (dia < 1 || dia > 31 || mes < 1 || mes > 12) return null;
    return '${dmy.group(3)}-${mes.toString().padLeft(2, '0')}-'
        '${dia.toString().padLeft(2, '0')}';
  }
  return null;
}

String _horaNormalizada(String cruda) {
  final texto = cruda.trim();
  if (RegExp(r'^\d{2}:\d{2}:\d{2}').hasMatch(texto)) {
    return texto.substring(0, 8);
  }
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(texto)) return '$texto:00';
  if (RegExp(r'^\d{1}:\d{2}$').hasMatch(texto)) return '0$texto:00';
  return '00:00:00';
}

/// Quita las copias remotas de lo que ya esta en la tabla local y ordena del
/// mas reciente al mas viejo.
///
/// Una medicion sincronizada vive dos veces en la tablet: en su tabla *_LOCAL
/// y como espejo bajado de MariaDB en *_REMOTAS. Sus claves no se pueden
/// cruzar (la local tiene uuid, la remota un 'ID:n' de MariaDB), asi que se
/// agrupa por instante: si a la misma fecha y hora hay fila local, esa manda
/// y la remota sobra. Se conservan TODAS las locales del grupo porque un
/// reemplazo escribe una fila por componente con el mismo instante.
///
/// Cada fila debe traer '_source' con el nombre de su tabla de origen.
List<Map<String, dynamic>> depurarYOrdenarHistorial(
  List<Map<String, dynamic>> filas,
) {
  final grupos = <String, List<Map<String, dynamic>>>{};
  for (final fila in filas) {
    grupos.putIfAbsent(claveHistorial(fila), () => []).add(fila);
  }

  final resultado = <Map<String, dynamic>>[];
  for (final entrada in grupos.entries) {
    final locales = entrada.value
        .where((f) => (f['_source'] ?? '').toString().endsWith('_LOCAL'))
        .toList();
    resultado.addAll(locales.isNotEmpty ? locales : [entrada.value.first]);
  }

  resultado.sort((a, b) => claveHistorial(b).compareTo(claveHistorial(a)));
  return resultado;
}
