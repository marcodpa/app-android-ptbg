import 'coercion.dart';

/// Ajuste de correa de un ventilador o un fin-fan.
///
/// Solo los equipos de tipo 4 (fin-fan) y 5 (ventilador) llevan correa; el
/// resto se mueve por acople directo. El formato oficial ya tenia su linea
/// ("AJUSTE DE CORREAS: SI / NO ; TENSION"), pero no habia donde llenarla
/// desde la tablet: la casilla se imprimia siempre vacia.
///
/// Viaja a MOT_AJC_REG en la planta.
class AjusteCorrea {
  const AjusteCorrea({
    required this.uuid,
    required this.localizacion,
    required this.sistema,
    required this.fecha,
    required this.hora,
    this.ajustada = false,
    this.tension,
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

  /// Si se ajusto la correa en esta visita. Un NO tambien es un registro
  /// valido: deja constancia de que se reviso y no hizo falta tocarla.
  final bool ajustada;

  /// Tension medida, en las unidades del tensiometro de la planta. Va nula
  /// cuando no se midio: en el papel esa casilla tambien se deja en blanco.
  final double? tension;

  final String observaciones;
  final String responsable;
  final String cargo;
  final String marca;
  final String modelo;
  final String serial;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  /// Los tipos de equipo que llevan correa.
  static const tiposConCorrea = {4, 5};

  static bool aplicaA(int puntos) => tiposConCorrea.contains(puntos);

  factory AjusteCorrea.fromMap(Map<String, dynamic> map) => AjusteCorrea(
        uuid: textoDe(map['uuid'] ?? map['UUID']),
        localizacion: enteroDe(map['localizacion'] ?? map['LOCALIZACION']),
        sistema: textoDe(map['sistema'] ?? map['SISTEMA']),
        fecha: textoDe(map['fecha'] ?? map['FECHA']),
        hora: textoDe(map['hora'] ?? map['HORA']),
        ajustada: enteroDe(map['ajustada'] ?? map['AJUSTADA']) == 1,
        tension: decimalDe(map['tension'] ?? map['TENSION']),
        observaciones: textoDe(map['observaciones'] ?? map['OBSERVACIONES']),
        responsable: textoDe(map['responsable'] ?? map['USUARIO']),
        cargo: textoDe(map['cargo'] ?? map['CARGO']),
        marca: textoDe(map['marca'] ?? map['MARCA']),
        modelo: textoDe(map['modelo'] ?? map['MODELO']),
        serial: textoDe(map['serial'] ?? map['SERIAL']),
        odt: _enteroONulo(map['odt'] ?? map['ODT']),
        sincronizado: enteroDe(map['sincronizado']) == 1,
        errorSync: textoONuloDe(map['error_sync']),
      );

  Map<String, dynamic> toDbMap() => {
        'uuid': uuid,
        'localizacion': localizacion,
        'sistema': sistema,
        'fecha': fecha,
        'hora': hora,
        'ajustada': ajustada ? 1 : 0,
        'tension': tension,
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

/// El ODT puede no existir todavia: un ajuste suelto no abre orden propia.
int? _enteroONulo(Object? valor) {
  if (valor == null || valor.toString().trim().isEmpty) return null;
  return enteroDe(valor);
}
