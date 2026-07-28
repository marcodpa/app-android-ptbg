double? parseTemperature(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim().replaceAll(',', '.'));
}

int _temperatureInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

DateTime _temperatureDateTime(String fecha, String hora) {
  final date = fecha.trim().split('T').first.split(' ').first;
  final time = hora.trim().contains('T')
      ? hora.trim().split('T').last
      : hora.trim().split(' ').last;
  final parsed = DateTime.tryParse(
    '${date}T${time.isEmpty ? '00:00:00' : time}',
  );
  if (parsed != null) return parsed;

  final match =
      RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(date);
  if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
  final timeParts = time.split(':');
  var year = int.tryParse(match.group(3) ?? '') ?? 1970;
  if (year < 100) year += 2000;
  return DateTime(
    year,
    int.tryParse(match.group(2) ?? '') ?? 1,
    int.tryParse(match.group(1) ?? '') ?? 1,
    timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 0 : 0,
    timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0,
    timeParts.length > 2 ? int.tryParse(timeParts[2].split('.').first) ?? 0 : 0,
  );
}

Map<String, double?> _temperatureValues(Map<String, dynamic> source) {
  final values = <String, double?>{};
  for (var i = 1; i <= 10; i++) {
    final column = 'T$i';
    final value =
        parseTemperature(source[column] ?? source[column.toLowerCase()]);
    if (value != null) values[column] = value;
  }
  return values;
}

class TemperatureMeasurement {
  final String uuid;
  final int localizacion;
  final String sistema;
  final String fecha;
  final String hora;
  final Map<String, double?> valores;
  final String? observaciones;
  final String? responsable;
  final String? cargo;
  final String? marca;
  final String? modelo;
  final String? serial;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  const TemperatureMeasurement({
    required this.uuid,
    required this.localizacion,
    required this.sistema,
    required this.fecha,
    required this.hora,
    required this.valores,
    this.observaciones,
    this.responsable,
    this.cargo,
    this.marca,
    this.modelo,
    this.serial,
    this.odt,
    this.sincronizado = false,
    this.errorSync,
  });

  factory TemperatureMeasurement.fromMap(Map<String, dynamic> map) {
    return TemperatureMeasurement(
      uuid: (map['uuid'] ?? '').toString(),
      localizacion: _temperatureInt(map['localizacion'] ?? map['LOCALIZACION']),
      sistema: (map['sistema'] ?? map['SISTEMA'] ?? '').toString(),
      fecha: (map['fecha'] ?? map['FECHA'] ?? '').toString(),
      hora: (map['hora'] ?? map['HORA'] ?? '').toString(),
      valores: _temperatureValues(map),
      observaciones: (map['observaciones'] ?? map['OBSERVACIONES'])?.toString(),
      responsable: (map['responsable'] ?? map['USUARIO'] ?? map['RESPONSABLE'])
          ?.toString(),
      cargo: (map['cargo'] ?? map['CARGO'])?.toString(),
      marca: (map['marca'] ?? map['MARCA'])?.toString(),
      modelo: (map['modelo'] ?? map['MODELO'])?.toString(),
      serial: (map['serial'] ?? map['SERIAL'])?.toString(),
      odt: map['odt'] == null && map['ODT'] == null
          ? null
          : _temperatureInt(map['odt'] ?? map['ODT']),
      sincronizado: _temperatureInt(map['sincronizado']) == 1,
      errorSync: map['error_sync']?.toString(),
    );
  }

  Map<String, dynamic> toDbMap() {
    final map = <String, dynamic>{
      'uuid': uuid,
      'localizacion': localizacion,
      'sistema': sistema,
      'fecha': fecha,
      'hora': hora,
      'observaciones': observaciones,
      'responsable': responsable,
      'cargo': cargo,
      'marca': marca,
      'modelo': modelo,
      'serial': serial,
      'odt': odt,
      'sincronizado': sincronizado ? 1 : 0,
      'error_sync': errorSync,
    };
    for (var i = 1; i <= 10; i++) {
      map['T$i'] = valores['T$i'];
    }
    return map;
  }

  TemperatureMeasurement copyWith({
    bool? sincronizado,
    String? errorSync,
    bool clearError = false,
  }) {
    return TemperatureMeasurement(
      uuid: uuid,
      localizacion: localizacion,
      sistema: sistema,
      fecha: fecha,
      hora: hora,
      valores: valores,
      observaciones: observaciones,
      responsable: responsable,
      cargo: cargo,
      marca: marca,
      modelo: modelo,
      serial: serial,
      odt: odt,
      sincronizado: sincronizado ?? this.sincronizado,
      errorSync: clearError ? null : errorSync ?? this.errorSync,
    );
  }
}

class TemperatureReading {
  final int localizacion;
  final String fecha;
  final String hora;
  final Map<String, double?> valores;
  final String? sistema;
  final String? observaciones;
  final String? responsable;
  final String? cargo;
  final String? marca;
  final String? modelo;
  final String? serial;
  final int? odt;

  const TemperatureReading({
    required this.localizacion,
    required this.fecha,
    required this.hora,
    required this.valores,
    this.sistema,
    this.observaciones,
    this.responsable,
    this.cargo,
    this.marca,
    this.modelo,
    this.serial,
    this.odt,
  });

  factory TemperatureReading.fromJson(Map<String, dynamic> json) {
    return TemperatureReading(
      localizacion:
          _temperatureInt(json['LOCALIZACION'] ?? json['localizacion']),
      fecha: (json['FECHA'] ?? json['fecha'] ?? '').toString(),
      hora: (json['HORA'] ?? json['hora'] ?? '').toString(),
      valores: _temperatureValues(json),
      sistema: (json['SISTEMA'] ?? json['sistema'])?.toString(),
      observaciones:
          (json['OBSERVACIONES'] ?? json['observaciones'])?.toString(),
      responsable:
          (json['USUARIO'] ?? json['RESPONSABLE'] ?? json['responsable'])
              ?.toString(),
      cargo: (json['CARGO'] ?? json['cargo'])?.toString(),
      marca: (json['MARCA'] ?? json['marca'])?.toString(),
      modelo: (json['MODELO'] ?? json['modelo'])?.toString(),
      serial: (json['SERIAL'] ?? json['serial'])?.toString(),
      odt: json['ODT'] == null && json['odt'] == null
          ? null
          : _temperatureInt(json['ODT'] ?? json['odt']),
    );
  }

  DateTime get fechaHora => _temperatureDateTime(fecha, hora);
}
