import 'coercion.dart';

double? parseLubricationValue(Object? value) => decimalDe(value);

int _lubricationInt(Object? value) => enteroDe(value);

DateTime _lubricationDateTime(String fecha, String hora) {
  // Acepta tambien dd/MM/yyyy y dd-MM-yyyy, no solo ISO. Antes cualquier
  // fecha no-ISO caia a epoch 0 y esa lubricacion se hundia al final del
  // historial sin que nadie lo notara; el parser de temperatura siempre
  // manejo estos formatos y este habia quedado con la version de 3 lineas.
  final soloFecha = fecha.split('T').first.trim();
  final directa = DateTime.tryParse('${soloFecha}T$hora');
  if (directa != null) return directa;
  final partes = soloFecha.split(RegExp(r'[/-]'));
  if (partes.length == 3 && partes[0].length <= 2) {
    final iso = '${partes[2].padLeft(4, '20')}-'
        '${partes[1].padLeft(2, '0')}-${partes[0].padLeft(2, '0')}';
    final volteada = DateTime.tryParse('${iso}T$hora');
    if (volteada != null) return volteada;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

Map<String, double?> _lubricationValues(Map<String, dynamic> source) {
  return {
    for (var i = 1; i <= 9; i++)
      if (parseLubricationValue(source['L$i'] ?? source['l$i']) != null)
        'L$i': parseLubricationValue(source['L$i'] ?? source['l$i']),
  };
}

class LubricationMeasurement {
  const LubricationMeasurement({
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

  factory LubricationMeasurement.fromMap(Map<String, dynamic> map) {
    return LubricationMeasurement(
      uuid: (map['uuid'] ?? '').toString(),
      localizacion: _lubricationInt(map['localizacion'] ?? map['LOCALIZACION']),
      sistema: (map['sistema'] ?? map['SISTEMA'] ?? '').toString(),
      fecha: (map['fecha'] ?? map['FECHA'] ?? '').toString(),
      hora: (map['hora'] ?? map['HORA'] ?? '').toString(),
      valores: _lubricationValues(map),
      observaciones: (map['observaciones'] ?? map['OBSERVACIONES'])?.toString(),
      responsable: (map['responsable'] ?? map['USUARIO'] ?? map['RESPONSABLE'])
          ?.toString(),
      cargo: (map['cargo'] ?? map['CARGO'])?.toString(),
      marca: (map['marca'] ?? map['MARCA'])?.toString(),
      modelo: (map['modelo'] ?? map['MODELO'])?.toString(),
      serial: (map['serial'] ?? map['SERIAL'])?.toString(),
      odt: map['odt'] == null && map['ODT'] == null
          ? null
          : _lubricationInt(map['odt'] ?? map['ODT']),
      sincronizado: _lubricationInt(map['sincronizado']) == 1,
      errorSync: map['error_sync']?.toString(),
    );
  }

  Map<String, dynamic> toDbMap() => {
    'uuid': uuid,
    'localizacion': localizacion,
    'sistema': sistema,
    'fecha': fecha,
    'hora': hora,
    for (var i = 1; i <= 9; i++) 'L$i': valores['L$i'],
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

  LubricationMeasurement copyWith({
    Map<String, double?>? valores,
    String? observaciones,
    // Quien lo hizo, su cargo y la orden de trabajo se pueden corregir. Son
    // los que mas se equivocan al capturar con prisa y antes no habia forma
    // de arreglarlos desde la tablet: habia que borrar el registro y volver
    // a tomar todas las lecturas.
    String? responsable,
    String? cargo,
    int? odt,
    // La fecha y la hora tambien: una medicion capturada con la fecha
    // equivocada desordena el historial del equipo. Solo el administrador
    // llega al editor, y el cambio queda en la bitacora.
    String? fecha,
    String? hora,
    bool? sincronizado,
    String? errorSync,
    bool clearError = false,
  }) {
    return LubricationMeasurement(
      uuid: uuid,
      localizacion: localizacion,
      sistema: sistema,
      fecha: fecha ?? this.fecha,
      hora: hora ?? this.hora,
      valores: valores ?? this.valores,
      observaciones: observaciones ?? this.observaciones,
      responsable: responsable ?? this.responsable,
      cargo: cargo ?? this.cargo,
      marca: marca,
      modelo: modelo,
      serial: serial,
      odt: odt ?? this.odt,
      sincronizado: sincronizado ?? this.sincronizado,
      errorSync: clearError ? null : errorSync ?? this.errorSync,
    );
  }

  DateTime get fechaHora => _lubricationDateTime(fecha, hora);
}

typedef LubricationReading = LubricationMeasurement;
