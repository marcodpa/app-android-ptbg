import 'coercion.dart';

/// Check list del generador de arranque en negro (formato SF-OP-FOR-036).
///
/// El black start es un equipo unico: no hay uno por sistema ni por turbina,
/// hay uno solo en la planta. Por eso su registro no lleva localizacion ni
/// nombre de equipo como el resto —no hace falta decir cual, solo hay uno— y
/// por eso entra por su propia tarjeta en vez de por la lista de equipos.
///
/// Tampoco se le miden vibracion, temperatura ni lo demas: se le revisan seis
/// parametros de operacion y cuatro componentes, y eso es todo su
/// mantenimiento.
class ChecklistBlackStart {
  const ChecklistBlackStart({
    required this.uuid,
    required this.fecha,
    required this.hora,
    required this.parametros,
    required this.componentes,
    this.observaciones = '',
    this.usuario,
    this.cargo,
    this.odt,
    this.sincronizado = false,
    this.errorSync,
  });

  final String uuid;
  final String fecha;
  final String hora;

  /// Los seis valores medidos, en el orden del formato.
  ///
  /// Van como texto y no como numero porque en el papel a veces se anota un
  /// rango o un "no registra", y forzar un numero obligaria al tecnico a
  /// inventarse uno.
  final List<String> parametros;

  /// Los cuatro componentes: true = APTO, false = NO APTO.
  final List<bool> componentes;

  final String observaciones;
  final String? usuario;
  final String? cargo;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  /// Parametros y variables operativas, con su unidad tal como esta impresa.
  static const parametrosNombres = <String>[
    'HORAS DE TRABAJO (Hrs)',
    'NIVEL DE REFRIGERANTE (%)',
    'NIVEL DE COMBUSTIBLE (%)',
    'NIVEL DE ACEITE (%)',
    'VOLTAJE DE BATERIAS (V DC)',
    'AMPERAJE DE BATERIAS (Amp DC)',
  ];

  /// Columna de cada parametro en MOT_BLKS_CHKL, en el mismo orden.
  static const parametrosColumnas = <String>[
    'trabajo_hrs',
    'refrigerante_lvl',
    'combustible_lvl',
    'aceite_lvl',
    'voltaje_bat',
    'amperaje_bat',
  ];

  /// Estados y verificaciones de componentes.
  static const componentesNombres = <String>[
    'CONDICIONES DE FILTROS DE ACEITE',
    'CONDICIONES DE FILTROS DE AIRE',
    'CONDICIONES DE PANEL DE CONTROL',
    'CONDICIONES DE CORREA',
  ];

  static const componentesColumnas = <String>[
    'filtro_aceite',
    'filtro_aire',
    'panel_control',
    'correa',
  ];

  /// Cuantos componentes quedaron NO APTO.
  int get noAptos => componentes.where((c) => !c).length;

  bool get conforme => noAptos == 0;

  static String _texto(Object? v) => textoDe(v);
  static String? _textoONulo(Object? v) => textoONuloDe(v);
  static int _entero(Object? v) => enteroDe(v);

  factory ChecklistBlackStart.fromMap(Map<String, dynamic> m) =>
      ChecklistBlackStart(
        uuid: _texto(m['uuid']),
        fecha: _texto(m['fecha']),
        hora: _texto(m['hora']),
        parametros: [
          for (final columna in parametrosColumnas) _texto(m[columna]),
        ],
        componentes: [
          for (final columna in componentesColumnas) _entero(m[columna]) == 1,
        ],
        observaciones: _texto(m['observaciones']),
        usuario: _textoONulo(m['usuario']),
        cargo: _textoONulo(m['cargo']),
        odt: m['odt'] == null ? null : _entero(m['odt']),
        sincronizado: _entero(m['sincronizado']) == 1,
        errorSync: _textoONulo(m['error_sync']),
      );

  Map<String, dynamic> toDbMap() {
    final mapa = <String, dynamic>{
      'uuid': uuid,
      'fecha': fecha,
      'hora': hora,
      'observaciones': observaciones,
      'usuario': usuario,
      'cargo': cargo,
      'odt': odt,
      'sincronizado': sincronizado ? 1 : 0,
      'error_sync': errorSync,
    };
    for (var i = 0; i < parametrosColumnas.length; i++) {
      mapa[parametrosColumnas[i]] = parametros[i];
    }
    for (var i = 0; i < componentesColumnas.length; i++) {
      mapa[componentesColumnas[i]] = componentes[i] ? 1 : 0;
    }
    return mapa;
  }
}
