import 'dart:convert';

/// Un equipo registrado en campo que todavia no existe en la planta.
///
/// Se guarda en la tablet y viaja por USB, como las mediciones y las ordenes.
/// Al subir se reparte en varias tablas: la identidad va a MOT_EQUIPO, la placa
/// del motor a MOT_DATA, y cada pieza restante a su maestra.
///
/// Mientras no suba, el equipo se ve en la lista de la tablet marcado "sin
/// enviar" y no se puede medir: una medicion contra una LOCALIZACION que el
/// servidor no conoce se rechazaria al sincronizar.
class EquipoNuevo {
  const EquipoNuevo({
    required this.uuid,
    required this.localizacion,
    required this.equipo,
    required this.codeSys,
    required this.sistema,
    required this.subsistema,
    required this.tagname,
    required this.codeQr,
    required this.ptEq,
    required this.codeConjunto,
    required this.familiaCompat,
    required this.motor,
    this.piezas = const [],
    this.usuario,
    this.cargo,
    required this.fecha,
    required this.hora,
    this.sincronizado = false,
    this.errorSync,
  });

  final String uuid;

  /// Identidad del equipo. La asigna la app tomando la siguiente libre.
  final int localizacion;

  final String equipo;
  final int codeSys;
  final String sistema;
  final String subsistema;

  /// TAG del SCADA (MOT_EQUIPO.TAGNAME).
  final String tagname;

  /// Lo que codifica la etiqueta fisica (MOT_EQUIPO.CODE_QR).
  final String codeQr;

  /// Tipo visual 1..9. Decide la foto y el plan de puntos de medicion.
  final int ptEq;

  /// Prefijo del conjunto: 10, 11, 12... Es la primera parte del CODE_QR.
  final int codeConjunto;

  /// Familia de compatibilidad. Nunca va vacia.
  ///
  /// TODO equipo pertenece a una familia, incluso los que hoy no comparten
  /// piezas con nadie: los tres del sistema contra incendio tienen una cada
  /// uno. La razon es que manana puede entrar un equipo compatible y tiene que
  /// haber una familia a la que sumarlo; si el equipo quedara sin familia, ese
  /// segundo equipo no tendria con quien emparejarse.
  ///
  /// Con [familiaNueva] se pide una familia propia y el numero definitivo lo
  /// pone el servidor al subir, que es el unico que ve la planta entera.
  ///
  /// No se deduce del sistema ni del subsistema: VENT TURB y VENT GEN comparten
  /// los dos y son familias distintas, y la familia de los patines cruza tres
  /// sistemas. Por eso se pregunta y se guarda aparte.
  final int familiaCompat;

  /// Pide una familia propia, todavia sin numero.
  static const familiaNueva = 0;

  bool get pideFamiliaNueva => familiaCompat == familiaNueva;

  final FichaMotor motor;

  /// Bomba, caja o ventilador segun el tipo. Solo marca, modelo y serial:
  /// es lo mismo que captura el reemplazo para esas piezas.
  final List<PiezaEquipo> piezas;

  final String? usuario;
  final String? cargo;
  final String fecha;
  final String hora;
  final bool sincronizado;
  final String? errorSync;

  /// Un equipo sin enviar no se puede medir todavia.
  bool get puedeMedirse => sincronizado;

  String get titulo => equipo.trim().isEmpty ? 'LOC-$localizacion' : equipo;

  /// Que piezas lleva un equipo segun su tipo visual.
  ///
  /// Es la misma reparticion que usa el reemplazo: si cambiara alli tiene que
  /// cambiar aqui, o se registrarian equipos a los que despues no se les puede
  /// reemplazar una de sus piezas.
  static List<int> tiposDePieza(int ptEq) {
    if (const {1, 2, 3, 7, 8, 9}.contains(ptEq)) return const [2]; // bomba
    if (const {4, 5}.contains(ptEq)) return const [4]; // ventilador
    if (ptEq == 6) return const [3, 2]; // caja y bomba
    return const [];
  }

  static String _texto(Object? v) => (v ?? '').toString().trim();

  static String? _textoONulo(Object? v) {
    final t = _texto(v);
    return t.isEmpty ? null : t;
  }

  static int _entero(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_texto(v)) ?? 0;
  }

  factory EquipoNuevo.fromMap(Map<String, dynamic> map) {
    final crudo = _texto(map['piezas_json']);
    final piezas = <PiezaEquipo>[];
    if (crudo.isNotEmpty) {
      try {
        final decoded = jsonDecode(crudo);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              piezas.add(PiezaEquipo.fromMap(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {
        // Registro viejo o corrupto: mejor el equipo sin piezas que perderlo.
      }
    }
    return EquipoNuevo(
      uuid: _texto(map['uuid']),
      localizacion: _entero(map['localizacion']),
      equipo: _texto(map['equipo']),
      codeSys: _entero(map['code_sys']),
      sistema: _texto(map['sistema']),
      subsistema: _texto(map['subsistema']),
      tagname: _texto(map['tagname']),
      codeQr: _texto(map['code_qr']),
      ptEq: _entero(map['pt_eq']),
      codeConjunto: _entero(map['code_conjunto']),
      familiaCompat: _entero(map['familia_compat']),
      motor: FichaMotor.fromMap(map),
      piezas: piezas,
      usuario: _textoONulo(map['usuario']),
      cargo: _textoONulo(map['cargo']),
      fecha: _texto(map['fecha']),
      hora: _texto(map['hora']),
      sincronizado: _entero(map['sincronizado']) == 1,
      errorSync: _textoONulo(map['error_sync']),
    );
  }

  Map<String, dynamic> toDbMap() => {
        'uuid': uuid,
        'localizacion': localizacion,
        'equipo': equipo,
        'code_sys': codeSys,
        'sistema': sistema,
        'subsistema': subsistema,
        'tagname': tagname,
        'code_qr': codeQr,
        'pt_eq': ptEq,
        'code_conjunto': codeConjunto,
        'familia_compat': familiaCompat,
        ...motor.toDbMap(),
        'piezas_json':
            jsonEncode(piezas.map((p) => p.toMap()).toList(growable: false)),
        'usuario': usuario,
        'cargo': cargo,
        'fecha': fecha,
        'hora': hora,
        'sincronizado': sincronizado ? 1 : 0,
        'error_sync': errorSync,
      };
}

/// Placa del motor. Es la unica pieza que lleva ficha completa, igual que en
/// el reemplazo: las demas maestras no tienen estas columnas.
class FichaMotor {
  const FichaMotor({
    required this.marca,
    required this.modelo,
    required this.serial,
    required this.hp,
    required this.arranque,
    required this.voltaje,
    required this.corriente,
    required this.sf,
    required this.ciclo,
    required this.ph,
    required this.rpm,
    required this.frame,
    required this.brgsDrive,
    required this.brgsOpp,
    this.lubricacion = '',
    this.motoresLub = '',
    this.cantMotLub,
    this.elecMotLub,
    this.manMotLub,
    this.elementoLub = '',
    this.cantElemLub,
    this.elecElemLub,
    this.manElemLub,
    this.sinLubricacion = false,
  });

  final String marca;
  final String modelo;
  final String serial;
  final String hp;
  final String arranque;
  final String voltaje;
  final String corriente;
  final String sf;
  final String ciclo;
  final String ph;
  final String rpm;
  final String frame;
  final String brgsDrive;
  final String brgsOpp;

  final String lubricacion;
  final String motoresLub;
  final double? cantMotLub;
  final double? elecMotLub;
  final double? manMotLub;
  final String elementoLub;
  final double? cantElemLub;
  final double? elecElemLub;
  final double? manElemLub;

  /// El equipo no se lubrica: rodamientos sellados o sin graseras.
  ///
  /// Sin esta salida un motor sellado no se podria registrar nunca, porque el
  /// bloque de lubricacion es obligatorio como todo lo demas.
  final bool sinLubricacion;

  static String _t(Object? v) => (v ?? '').toString().trim();
  static double? _d(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(_t(v).replaceAll(',', '.'));
  }

  factory FichaMotor.fromMap(Map<String, dynamic> m) => FichaMotor(
        marca: _t(m['marca']),
        modelo: _t(m['modelo']),
        serial: _t(m['serial']),
        hp: _t(m['hp']),
        arranque: _t(m['arranque']),
        voltaje: _t(m['voltaje']),
        corriente: _t(m['corriente']),
        sf: _t(m['sf']),
        ciclo: _t(m['ciclo']),
        ph: _t(m['ph']),
        rpm: _t(m['rpm']),
        frame: _t(m['frame']),
        brgsDrive: _t(m['brgs_drive']),
        brgsOpp: _t(m['brgs_opp']),
        lubricacion: _t(m['lubricacion']),
        motoresLub: _t(m['motores_lub']),
        cantMotLub: _d(m['cant_mot_lub']),
        elecMotLub: _d(m['elec_mot_lub']),
        manMotLub: _d(m['man_mot_lub']),
        elementoLub: _t(m['elemento_lub']),
        cantElemLub: _d(m['cant_elem_lub']),
        elecElemLub: _d(m['elec_elem_lub']),
        manElemLub: _d(m['man_elem_lub']),
        sinLubricacion: (m['sin_lubricacion'] ?? 0).toString() == '1',
      );

  Map<String, dynamic> toDbMap() => {
        'marca': marca,
        'modelo': modelo,
        'serial': serial,
        'hp': hp,
        'arranque': arranque,
        'voltaje': voltaje,
        'corriente': corriente,
        'sf': sf,
        'ciclo': ciclo,
        'ph': ph,
        'rpm': rpm,
        'frame': frame,
        'brgs_drive': brgsDrive,
        'brgs_opp': brgsOpp,
        'lubricacion': lubricacion,
        'motores_lub': motoresLub,
        'cant_mot_lub': cantMotLub,
        'elec_mot_lub': elecMotLub,
        'man_mot_lub': manMotLub,
        'elemento_lub': elementoLub,
        'cant_elem_lub': cantElemLub,
        'elec_elem_lub': elecElemLub,
        'man_elem_lub': manElemLub,
        'sin_lubricacion': sinLubricacion ? 1 : 0,
      };
}

/// Bomba, caja o ventilador que acompanan al motor.
class PiezaEquipo {
  const PiezaEquipo({
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.serial,
  });

  /// 2 Bomba, 3 Caja, 4 Ventilador. El 1 (Motor) va en [FichaMotor].
  final int tipo;
  final String marca;
  final String modelo;
  final String serial;

  String get nombreTipo {
    switch (tipo) {
      case 2:
        return 'Bomba';
      case 3:
        return 'Caja';
      case 4:
        return 'Ventilador';
      default:
        return 'Componente';
    }
  }

  factory PiezaEquipo.fromMap(Map<String, dynamic> m) => PiezaEquipo(
        tipo: int.tryParse('${m['tipo'] ?? 0}') ?? 0,
        marca: (m['marca'] ?? '').toString().trim(),
        modelo: (m['modelo'] ?? '').toString().trim(),
        serial: (m['serial'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toMap() => {
        'tipo': tipo,
        'marca': marca,
        'modelo': modelo,
        'serial': serial,
      };
}
