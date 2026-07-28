import 'models.dart';

/// Una fila histórica descargada desde MariaDB.
///
/// La API puede devolver las claves en mayúsculas o minúsculas. Este modelo
/// acepta ambos formatos y genera una fecha/hora normalizada para ordenar las
/// mediciones correctamente en la tablet.
class MedicionRemota {
  final int id;
  final int localizacion;
  final String equipo;
  final String tagname;
  final String fecha;
  final String hora;
  final Map<String, double?> valores;
  final double? rms;
  final String observaciones;
  final String responsable;
  final String cargo;
  final String marca;
  final String modelo;
  final String serial;

  const MedicionRemota({
    required this.id,
    required this.localizacion,
    required this.equipo,
    required this.tagname,
    required this.fecha,
    required this.hora,
    required this.valores,
    required this.rms,
    required this.observaciones,
    this.responsable = '',
    this.cargo = '',
    this.marca = '',
    this.modelo = '',
    this.serial = '',
  });

  factory MedicionRemota.fromJson(Map<String, dynamic> json) {
    final lower = <String, dynamic>{};
    for (final entry in json.entries) {
      lower[entry.key.toLowerCase()] = entry.value;
    }

    dynamic read(String key) => json[key] ?? lower[key.toLowerCase()];

    final valores = <String, double?>{};
    for (int p = 1; p <= 9; p++) {
      for (final eje in const ['H', 'V', 'A']) {
        final key = '$eje$p';
        final value = _toDouble(read(key));
        if (value != null) valores[key] = value;
      }
    }

    return MedicionRemota(
      id: _toInt(read('ID') ?? read('ID_MUESTRA') ?? read('ID_REMOTO')),
      localizacion: _toInt(
        read('LOCALIZACION') ?? read('LC_EQ') ?? read('UBICACION'),
      ),
      equipo: _cleanText(
        read('EQUIPO') ?? read('NOMBRE_EQUIPO') ?? read('SISTEMA'),
        fallback: 'Equipo sin nombre',
      ),
      tagname: _cleanText(
        read('TAGNAME') ?? read('SCADA') ?? read('TAG'),
        fallback: 'Sin tag',
      ),
      fecha: _cleanText(read('FECHA')),
      hora: _cleanText(read('HORA')),
      valores: valores,
      rms: _toDouble(read('RMS')),
      observaciones: _cleanText(
        read('OBSERVACIONES') ?? read('OBSERVACION'),
      ),
      responsable: _cleanText(read('USUARIO') ?? read('RESPONSABLE')),
      cargo: _cleanText(read('CARGO')),
      marca: _cleanText(read('MARCA')),
      modelo: _cleanText(read('MODELO')),
      serial: _cleanText(read('SERIAL')),
    );
  }

  /// Clave estable para evitar duplicados en SQLite.
  String get remoteKey {
    if (id > 0) return 'ID:$id';
    return 'LOC:$localizacion|${fecha.trim()}|${hora.trim()}';
  }

  /// Fecha/hora usada para ordenar. Acepta ISO, dd/MM/yyyy y dd-MM-yyyy.
  DateTime get fechaHora => parseFechaHora(fecha, hora);

  String get fechaHoraIso => fechaHora.toIso8601String();

  UltimaLectura toUltimaLectura() => UltimaLectura(
        localizacion: localizacion,
        fecha: fecha,
        hora: hora,
        valores: Map<String, double?>.from(valores),
        rms: rms,
      );

  Map<String, dynamic> toDbMap() {
    final map = <String, dynamic>{
      'remote_key': remoteKey,
      'id_remoto': id,
      'localizacion': localizacion,
      'equipo': equipo,
      'tagname': tagname,
      'fecha': fecha,
      'hora': hora,
      'fecha_hora_iso': fechaHoraIso,
      'RMS': rms,
      'observaciones': observaciones,
      'responsable': responsable,
      'cargo': cargo,
      'marca': marca,
      'modelo': modelo,
      'serial': serial,
    };
    map.addAll(valores);
    return map;
  }

  static DateTime parseFechaHora(String fecha, String hora) {
    final f = fecha.trim();
    final h = hora.trim();

    // ISO completo o combinación ISO fecha + hora.
    for (final candidate in <String>[
      if (f.isNotEmpty && h.isNotEmpty) '${_soloFecha(f)}T${_soloHora(h)}',
      if (f.isNotEmpty && h.isNotEmpty) '${_soloFecha(f)} ${_soloHora(h)}',
      f,
    ]) {
      final parsed = DateTime.tryParse(candidate);
      if (parsed != null) return parsed;
    }

    // Formatos habituales dd/MM/yyyy o dd-MM-yyyy.
    final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$')
        .firstMatch(_soloFecha(f));
    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '') ?? 1;
      final month = int.tryParse(match.group(2) ?? '') ?? 1;
      var year = int.tryParse(match.group(3) ?? '') ?? 1970;
      if (year < 100) year += 2000;
      final time = _timeParts(h);
      return DateTime(year, month, day, time.$1, time.$2, time.$3);
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _soloFecha(String value) {
    final text = value.trim();
    if (text.contains('T')) return text.split('T').first;
    if (text.contains(' ')) return text.split(' ').first;
    return text;
  }

  static String _soloHora(String value) {
    var text = value.trim();
    if (text.contains('T')) text = text.split('T').last;
    if (text.contains(' ')) text = text.split(' ').last;
    if (text.endsWith('Z')) text = text.substring(0, text.length - 1);
    return text;
  }

  static (int, int, int) _timeParts(String value) {
    final clean = _soloHora(value);
    final parts = clean.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final secondText = parts.length > 2 ? parts[2].split('.').first : '0';
    final second = int.tryParse(secondText) ?? 0;
    return (hour, minute, second);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static String _cleanText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return fallback;
    return text;
  }
}
