const alignmentValueColumns = <String>[
  'AMB_ANGULO_V',
  'AMB_ANGULO_H',
  'AMB_COMPENSACION_V',
  'AMB_COMPENSACION_H',
  'ACM_ANGULO_V',
  'ACM_ANGULO_H',
  'ACM_COMPENSACION_V',
  'ACM_COMPENSACION_H',
  'ACB_ANGULO_V',
  'ACB_ANGULO_H',
  'ACB_COMPENSACION_V',
  'ACB_COMPENSACION_H',
];

double? parseAlignmentValue(String input) {
  final value = input.trim();
  if (!RegExp(r'^-?\d+(,\d{1,2})?$').hasMatch(value)) return null;
  return double.tryParse(value.replaceFirst(',', '.'));
}

double? _alignmentDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim().replaceAll(',', '.'));
}

int _alignmentInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String? _alignmentText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text.toUpperCase() == 'NULL' ? null : text;
}

Map<String, double?> _alignmentValues(Map<String, dynamic> source) => {
      for (final column in alignmentValueColumns)
        column:
            _alignmentDouble(source[column] ?? source[column.toLowerCase()]),
    };

int _alignmentPuntos(
  Map<String, dynamic> source,
  Map<String, double?> values,
) {
  final explicit = _alignmentInt(source['puntos'] ?? source['PUNTOS']);
  if (explicit != 0) return explicit;
  final hasGearbox = values.entries.any(
    (entry) =>
        (entry.key.startsWith('ACM_') || entry.key.startsWith('ACB_')) &&
        entry.value != null,
  );
  return hasGearbox ? 6 : 1;
}

class AlignmentMeasurement {
  const AlignmentMeasurement({
    required this.uuid,
    required this.localizacion,
    required this.sistema,
    required this.puntos,
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

  final String uuid;
  final int localizacion;
  final String sistema;
  final int puntos;
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

  factory AlignmentMeasurement.fromMap(Map<String, dynamic> map) {
    final values = _alignmentValues(map);
    return AlignmentMeasurement(
      uuid: (map['uuid'] ?? '').toString(),
      localizacion: _alignmentInt(map['localizacion'] ?? map['LOCALIZACION']),
      sistema: (map['sistema'] ?? map['SISTEMA'] ?? '').toString(),
      puntos: _alignmentPuntos(map, values),
      fecha: (map['fecha'] ?? map['FECHA'] ?? '').toString(),
      hora: (map['hora'] ?? map['HORA'] ?? '').toString(),
      valores: values,
      observaciones:
          _alignmentText(map['observaciones'] ?? map['OBSERVACIONES']),
      responsable: _alignmentText(
        map['responsable'] ?? map['USUARIO'] ?? map['RESPONSABLE'],
      ),
      cargo: _alignmentText(map['cargo'] ?? map['CARGO']),
      marca: _alignmentText(map['marca'] ?? map['MARCA']),
      modelo: _alignmentText(map['modelo'] ?? map['MODELO']),
      serial: _alignmentText(map['serial'] ?? map['SERIAL']),
      odt: map['odt'] == null && map['ODT'] == null
          ? null
          : _alignmentInt(map['odt'] ?? map['ODT']),
      sincronizado: _alignmentInt(map['sincronizado']) == 1,
      errorSync: _alignmentText(map['error_sync']),
    );
  }

  factory AlignmentMeasurement.fromRemoteMap(Map<String, dynamic> map) {
    final remoteId = map['ID'] ?? map['id'];
    return AlignmentMeasurement.fromMap({
      ...map,
      'uuid': map['uuid'] ?? 'remote-${remoteId ?? ''}',
      'sincronizado': 1,
      'error_sync': null,
    });
  }

  Map<String, dynamic> toDbMap() => {
        'uuid': uuid,
        'localizacion': localizacion,
        'sistema': sistema,
        'puntos': puntos,
        'fecha': fecha,
        'hora': hora,
        for (final column in alignmentValueColumns) column: valores[column],
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

  AlignmentMeasurement copyWith({
    Map<String, double?>? valores,
    String? observaciones,
    bool clearObservaciones = false,
    bool? sincronizado,
    String? errorSync,
    bool clearError = false,
  }) {
    return AlignmentMeasurement(
      uuid: uuid,
      localizacion: localizacion,
      sistema: sistema,
      puntos: puntos,
      fecha: fecha,
      hora: hora,
      valores: valores ?? this.valores,
      observaciones:
          clearObservaciones ? null : observaciones ?? this.observaciones,
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
