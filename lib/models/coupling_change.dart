class CouplingChange {
  const CouplingChange({
    required this.uuid,
    required this.localizacion,
    required this.sistema,
    required this.fecha,
    required this.hora,
    this.coupling = false,
    this.inserto = false,
    this.modeloCoupling = '',
    this.observaciones = '',
    this.responsable = '',
    this.cargo = '',
    this.marca = '',
    this.modelo = '',
    this.serial = '',
    this.odt,
    this.sincronizado = false,
    this.errorSync,
  });

  final String uuid;
  final int localizacion;
  final String sistema;
  final String fecha;
  final String hora;

  /// Se cambio el coupling. Puede cambiarse el inserto sin tocar el coupling,
  /// el coupling sin tocar el inserto, o ambos: por eso son dos banderas
  /// independientes y no una sola respuesta.
  final bool coupling;
  final bool inserto;
  final String modeloCoupling;
  final String observaciones;
  final String responsable;
  final String cargo;
  final String marca;
  final String modelo;
  final String serial;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  factory CouplingChange.fromMap(Map<String, dynamic> map) => CouplingChange(
        uuid: (map['uuid'] ?? '').toString(),
        localizacion: _toInt(map['localizacion'] ?? map['LOCALIZACION']),
        sistema: (map['sistema'] ?? map['SISTEMA'] ?? '').toString(),
        fecha: (map['fecha'] ?? map['FECHA'] ?? '').toString(),
        hora: (map['hora'] ?? map['HORA'] ?? '').toString(),
        coupling: _toInt(map['coupling'] ?? map['COUPLING']) == 1,
        inserto: _toInt(map['inserto'] ?? map['INSERTO']) == 1,
        modeloCoupling:
            (map['modelo_cplg'] ?? map['MODELO_CPLG'] ?? '').toString(),
        observaciones:
            (map['observaciones'] ?? map['OBSERVACIONES'] ?? '').toString(),
        responsable: (map['responsable'] ?? map['USUARIO'] ?? '').toString(),
        cargo: (map['cargo'] ?? map['CARGO'] ?? '').toString(),
        marca: (map['marca'] ?? map['MARCA'] ?? '').toString(),
        modelo: (map['modelo'] ?? map['MODELO'] ?? '').toString(),
        serial: (map['serial'] ?? map['SERIAL'] ?? '').toString(),
        odt: _nullableInt(map['odt'] ?? map['ODT']),
        sincronizado: _toInt(map['sincronizado']) == 1,
        errorSync: map['error_sync']?.toString(),
      );

  Map<String, dynamic> toDbMap() => {
        'uuid': uuid,
        'localizacion': localizacion,
        'sistema': sistema,
        'fecha': fecha,
        'hora': hora,
        'coupling': coupling ? 1 : 0,
        'inserto': inserto ? 1 : 0,
        'modelo_cplg': modeloCoupling.trim(),
        'observaciones': observaciones.trim(),
        'responsable': responsable.trim(),
        'cargo': cargo.trim(),
        'marca': marca.trim(),
        'modelo': modelo.trim(),
        'serial': serial.trim(),
        'odt': odt,
        'sincronizado': sincronizado ? 1 : 0,
        'error_sync': errorSync,
      };
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  return _toInt(value);
}
