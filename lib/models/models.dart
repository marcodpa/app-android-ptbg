// ════════════════════════════════════════════════════════════
export 'alignment_measurement.dart';
export 'alignment_plan.dart';

// Modelos que reflejan EXACTAMENTE las tablas de MariaDB
// ════════════════════════════════════════════════════════════

// ── Equipo (tabla oficial PTBG_DAT.MOT_EQUIP + MOT_SYSTEM + MOT_DATA) ────────────
// MOT_EQUIP: ID, CODE_SYS, EQUIPO, LOCALIZACION, NAME_SYS_1, NAME_SYS_2,
//            CODE_QR, PUNTOS, TAGNAME
// MOT_DATA:  UBICACION, MARCA, MODELO, SERIAL, VOLTAJE, CORRIENTE,
//            RPM, SF, HP, FRAME, ARRANQUE, PH, TENSION, LUBRICACION
class Equipo {
  final int id;
  final int codeSys;
  final String equipo;
  final int localizacion;
  final String? qrCode;

  /// Cantidad de puntos antigua. Se mantiene por compatibilidad,
  /// pero la pantalla de medición usa la configuración visual.
  final int puntos;

  /// Tipo visual del equipo. Debe venir DIRECTAMENTE de MOT_EQUIP.PUNTOS.
  /// No se calcula por nombre ni por localización: la base de datos manda.
  final int ptEq;

  final String sistema;
  final String subsistema;
  final String? scada;

  /// Familia de compatibilidad, si la planta se la asigno.
  ///
  /// Null en los equipos originales: esos se resuelven con la lista fija del
  /// codigo. Los registrados en campo la traen porque se pregunta al crearlos.
  final int? familiaCompat;

  final EquipoInfo? info;

  const Equipo({
    required this.id,
    required this.codeSys,
    required this.equipo,
    required this.localizacion,
    this.qrCode,
    required this.puntos,
    this.ptEq = 0,
    required this.sistema,
    this.subsistema = '',
    this.scada,
    this.familiaCompat,
    this.info,
  });

  factory Equipo.fromJson(Map<String, dynamic> j) {
    final localizacion = _int(
      j['LOCALIZACION'] ??
          j['localizacion'] ??
          j['LC_EQ'] ??
          j['lc_eq'] ??
          j['lcEq'] ??
          0,
    );

    final id = _int(j['ID'] ?? j['id'] ?? j['ID_EQ'] ?? j['idEq'] ?? 0);
    final codeSys = _int(
      j['CODE_SYS'] ?? j['codeSys'] ?? j['CD_SYS'] ?? j['cdSys'] ?? 0,
    );
    final equipo = (j['EQUIPO'] ?? j['equipo'] ?? '').toString();
    final sistema = (j['SISTEMA'] ??
            j['sistema'] ??
            j['NAME_SYS_1'] ??
            j['nameSys1'] ??
            j['SS_EQ'] ??
            j['ssEq'] ??
            '')
        .toString();
    final subsistema = (j['SUBSISTEMA'] ??
            j['subsistema'] ??
            j['NAME_SYS_2'] ??
            j['nameSys2'] ??
            '')
        .toString();
    final scada =
        (j['SCADA'] ?? j['scada'] ?? j['TG_EQ'] ?? j['tgEq'])?.toString();
    final qrCode =
        (j['QR_CODE'] ?? j['qrCode'] ?? j['CD_QR'] ?? j['cdQr'])?.toString();

    // En la estructura oficial PTBG_DAT, el tipo visual viene de MOT_EQUIP.PUNTOS.
    // También aceptamos alias viejos para no romper cachés o respuestas anteriores.
    final rawPtEq = _int(
      j['PT_EQ'] ??
          j['ptEq'] ??
          j['pt_eq'] ??
          j['PTEQ'] ??
          j['TIPO_VISUAL'] ??
          j['tipoVisual'] ??
          j['PUNTOS'] ??
          j['puntos'] ??
          0,
    );

    final nestedInfo = j['INFO'] ?? j['info'];
    EquipoInfo? parsedInfo;

    if (nestedInfo is Map) {
      parsedInfo = EquipoInfo.fromJson(
        Map<String, dynamic>.from(nestedInfo),
        fallbackLocalizacion: localizacion,
      );
    } else {
      parsedInfo = EquipoInfo.fromJson(j, fallbackLocalizacion: localizacion);
      if (parsedInfo.isEmpty) parsedInfo = null;
    }

    return Equipo(
      id: id,
      codeSys: codeSys,
      equipo: equipo,
      localizacion: localizacion,
      qrCode: qrCode,
      puntos: _int(
        j['NUM_PUNTOS'] ??
            j['numPuntos'] ??
            j['PUNTOS_MEDICION'] ??
            j['PUNTOS'] ??
            j['puntos'] ??
            0,
      ),
      ptEq: rawPtEq,
      sistema: sistema,
      subsistema: subsistema,
      scada: scada,
      familiaCompat: _intONulo(
        j['FAMILIA_COMPAT'] ?? j['familia_compat'] ?? j['familiaCompat'],
      ),
      info: parsedInfo,
    );
  }

  static int? _intONulo(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'codeSys': codeSys,
        'equipo': equipo,
        'localizacion': localizacion,
        'qrCode': qrCode,
        'puntos': puntos,
        // Guardamos el tipo visual que vino desde MOT_EQUIP.PUNTOS, sin recalcularlo.
        'ptEq': ptEq,
        'sistema': sistema,
        'subsistema': subsistema,
        'scada': scada,
        'familiaCompat': familiaCompat,
        'info': info?.toMap(),
      };

  Equipo copyWith({
    EquipoInfo? info,
    int? ptEq,
    String? subsistema,
    int? familiaCompat,
  }) =>
      Equipo(
        id: id,
        codeSys: codeSys,
        equipo: equipo,
        localizacion: localizacion,
        qrCode: qrCode,
        puntos: puntos,
        ptEq: ptEq ?? this.ptEq,
        sistema: sistema,
        subsistema: subsistema ?? this.subsistema,
        scada: scada,
        familiaCompat: familiaCompat ?? this.familiaCompat,
        info: info ?? this.info,
      );

  /// Texto principal para QR.
  /// Si la base trae CD_QR/TG_EQ se muestra ese valor.
  /// Si no trae nada, usamos LC_EQ puro porque los nuevos QR impresos
  /// contienen solamente el número de localización: 1, 2, 3...
  String get qrDisplay => (qrCode != null && qrCode!.trim().isNotEmpty)
      ? qrCode!.trim()
      : localizacion.toString();

  /// Tipo visual final que usa la app para escoger imagen.
  /// Regla estricta: solo usa MOT_EQUIP.PUNTOS.
  /// Si PUNTOS viene nulo, 0 o fuera de 1..9, muestra tipo 1 como fallback seguro.
  int get visualType => resolverTipoVisual(rawPtEq: ptEq);

  static int resolverTipoVisual({required int rawPtEq}) {
    if (rawPtEq >= 1 && rawPtEq <= 10) return rawPtEq;
    return 1;
  }

  static int _int(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
}

class EquipoInfo {
  final int localizacion;
  final String? marca;
  final String? serial;
  final String? modelo;
  final String? hp;
  final String? start;
  final String? volts;
  final String? fla;
  final String? sf;
  final String? hz;
  final String? ph;
  final String? rpm;
  final String? brgsDrive;
  final String? brgsOpp;
  final String? lubricacion;
  final String? motoresLub;
  final double? cantMotLub;
  final double? elecMotLub;
  final double? manMotLub;
  final String? elementoLub;
  final double? cantElemLub;
  final double? elecElemLub;
  final double? manElemLub;

  const EquipoInfo({
    required this.localizacion,
    this.marca,
    this.serial,
    this.modelo,
    this.hp,
    this.start,
    this.volts,
    this.fla,
    this.sf,
    this.hz,
    this.ph,
    this.rpm,
    this.brgsDrive,
    this.brgsOpp,
    this.lubricacion,
    this.motoresLub,
    this.cantMotLub,
    this.elecMotLub,
    this.manMotLub,
    this.elementoLub,
    this.cantElemLub,
    this.elecElemLub,
    this.manElemLub,
  });

  bool get isEmpty =>
      _blank(marca) &&
      _blank(serial) &&
      _blank(modelo) &&
      _blank(hp) &&
      _blank(start) &&
      _blank(volts) &&
      _blank(fla) &&
      _blank(sf) &&
      _blank(hz) &&
      _blank(ph) &&
      _blank(rpm) &&
      _blank(brgsDrive) &&
      _blank(brgsOpp) &&
      _blank(lubricacion) &&
      _blank(motoresLub) &&
      _blank(elementoLub);

  factory EquipoInfo.fromJson(
    Map<String, dynamic> j, {
    int? fallbackLocalizacion,
  }) {
    return EquipoInfo(
      localizacion: _int(
        j['LC_EQ'] ??
            j['localizacion'] ??
            j['LOCALIZACION'] ??
            j['UBICACION'] ??
            j['ubicacion'] ??
            fallbackLocalizacion ??
            0,
      ),
      marca: _str(
        j['MARCA_INFO'] ?? j['MARCA'] ?? j['marca'] ?? j['marcaInfo'],
      ),
      serial: _str(
        j['SERIAL_INFO'] ?? j['SERIAL'] ?? j['serial'] ?? j['serialInfo'],
      ),
      modelo: _str(
        j['MODEL_INFO'] ??
            j['MODELO_INFO'] ??
            j['MODELO'] ??
            j['modelo'] ??
            j['modelInfo'],
      ),
      hp: _str(j['HP_INFO'] ?? j['HP'] ?? j['hp'] ?? j['hpInfo']),
      start: _str(
        j['START_INFO'] ??
            j['ARRANQUE_INFO'] ??
            j['ARRANQUE'] ??
            j['start'] ??
            j['startInfo'],
      ),
      volts: _str(
        j['VOLTS_INFO'] ??
            j['VOLTAJE_INFO'] ??
            j['VOLTAJE'] ??
            j['TENSION'] ??
            j['volts'] ??
            j['voltsInfo'],
      ),
      fla: _str(
        j['FLA_INFO'] ??
            j['CORRIENTE_INFO'] ??
            j['CORRIENTE'] ??
            j['fla'] ??
            j['flaInfo'],
      ),
      sf: _str(j['SF_INFO'] ?? j['SF'] ?? j['sf'] ?? j['sfInfo']),
      hz: _str(
        j['HZ_INFO'] ?? j['CICLO_INFO'] ?? j['CICLO'] ?? j['hz'] ?? j['hzInfo'],
      ),
      ph: _str(j['PH_INFO'] ?? j['PH'] ?? j['ph'] ?? j['phInfo']),
      rpm: _str(j['RPM_INFO'] ?? j['RPM'] ?? j['rpm'] ?? j['rpmInfo']),
      brgsDrive: _str(
        j['BRGS_DRIVE_INFO'] ??
            j['BRGS_DRIVE'] ??
            j['brgsDrive'] ??
            j['brgs_drive'],
      ),
      brgsOpp: _str(
        j['BRGS_OPP_INFO'] ?? j['BRGS_OPP'] ?? j['brgsOpp'] ?? j['brgs_opp'],
      ),
      lubricacion: _str(
        j['LUBRICACION_INFO'] ?? j['LUBRICACION'] ?? j['lubricacion'],
      ),
      motoresLub: _str(j['MOTORES_LUB'] ?? j['motoresLub'] ?? j['motores_lub']),
      cantMotLub: _double(
        j['CANT_MOT_LUB'] ?? j['cantMotLub'] ?? j['cant_mot_lub'],
      ),
      elecMotLub: _double(
        j['ELEC_MOT_LUB'] ?? j['elecMotLub'] ?? j['elec_mot_lub'],
      ),
      manMotLub: _double(
        j['MAN_MOT_LUB'] ?? j['manMotLub'] ?? j['man_mot_lub'],
      ),
      elementoLub: _str(
        j['ELEMENTO_LUB'] ?? j['elementoLub'] ?? j['elemento_lub'],
      ),
      cantElemLub: _double(
        j['CANT_ELEM_LUB'] ?? j['cantElemLub'] ?? j['cant_elem_lub'],
      ),
      elecElemLub: _double(
        j['ELEC_ELEM_LUB'] ?? j['elecElemLub'] ?? j['elec_elem_lub'],
      ),
      manElemLub: _double(
        j['MAN_ELEM_LUB'] ?? j['manElemLub'] ?? j['man_elem_lub'],
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'localizacion': localizacion,
        'marca': marca,
        'serial': serial,
        'modelo': modelo,
        'hp': hp,
        'start': start,
        'volts': volts,
        'fla': fla,
        'sf': sf,
        'hz': hz,
        'ph': ph,
        'rpm': rpm,
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
      };

  String get shortSerial => _clean(serial, fallback: 'Sin serial');
  String get shortModelo => _clean(modelo, fallback: 'Sin modelo');
  String get shortMarca => _clean(marca, fallback: 'Sin marca');

  static bool _blank(String? v) {
    if (v == null) return true;
    final t = v.trim();
    return t.isEmpty ||
        t.toUpperCase() == 'NULL' ||
        t.toUpperCase() == 'SIN DATOS';
  }

  static String _clean(String? v, {String fallback = 'Sin datos'}) {
    if (_blank(v)) return fallback;
    return v!.trim();
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'NULL') return null;
    return s;
  }

  static int _int(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
  static double? _double(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final text = v.toString().trim().replaceAll(',', '.');
    final direct = double.tryParse(text);
    if (direct != null) return direct;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }
}

// ── MedicionStep — paso de captura guiada ─────────────────────────────
class MedicionStep {
  /// Número mostrado al operador dentro de la secuencia del equipo.
  /// Ejemplo: el tercer punto físico se muestra como Punto 3.
  final int puntoN;

  /// Punto gráfico usado para escoger la imagen y la posición del marcador.
  /// Puede ser distinto de [puntoN] cuando una misma ilustración representa
  /// dos apoyos del motor o de la bomba.
  final int visualPuntoN;

  /// Número real de columna en MDB_VIBR_MUES.
  /// Ejemplo: Punto 3 (Bomba lado libre) escribe H5/V5/A5.
  final int dbPuntoN;

  final String eje; // H, V o A
  final String etiqueta; // nombre físico del punto
  double? valor;
  String? observacion;

  MedicionStep({
    required this.puntoN,
    int? visualPuntoN,
    int? dbPuntoN,
    required this.eje,
    required this.etiqueta,
  })  : visualPuntoN = visualPuntoN ?? puntoN,
        dbPuntoN = dbPuntoN ?? puntoN;

  // Columna real en MDB_VIBR_MUES: H1..H9, V1..V9, A1..A9.
  String get dbColumn => '$eje$dbPuntoN';
}

// ── MedicionLocal — tabla SQLite local ───────────────────────────────
// Refleja MOT_VIBR_MUES: FECHA, HORA, SISTEMA, LOCALIZACION, H1-H9, V1-V9, A1-A9, RMS, OBSERVACIONES
class MedicionLocal {
  final String uuid;
  final int localizacion;
  final String sistema;
  final String fecha;
  final String hora;
  final Map<String, double?> valores; // H1..A9
  final double? rms;
  final String? observaciones;
  final String? responsable;
  final String? cargo;
  final String? marca;
  final String? modelo;
  final String? serial;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  const MedicionLocal({
    required this.uuid,
    required this.localizacion,
    required this.sistema,
    required this.fecha,
    required this.hora,
    required this.valores,
    this.rms,
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

  factory MedicionLocal.fromMap(Map<String, dynamic> m) => MedicionLocal(
        uuid: (m['uuid'] ?? '').toString(),
        localizacion: _toInt(m['localizacion'] ?? m['LOCALIZACION']),
        sistema: (m['sistema'] ?? m['SISTEMA'] ?? '').toString(),
        fecha: (m['fecha'] ?? m['FECHA'] ?? '').toString(),
        hora: (m['hora'] ?? m['HORA'] ?? '').toString(),
        rms: _toDouble(m['rms'] ?? m['RMS']),
        observaciones: (m['observaciones'] ?? m['OBSERVACIONES'])?.toString(),
        responsable:
            (m['responsable'] ?? m['USUARIO'] ?? m['RESPONSABLE'])?.toString(),
        cargo: (m['cargo'] ?? m['CARGO'])?.toString(),
        marca: (m['marca'] ?? m['MARCA'])?.toString(),
        modelo: (m['modelo'] ?? m['MODELO'])?.toString(),
        serial: (m['serial'] ?? m['SERIAL'])?.toString(),
        odt: m['odt'] == null && m['ODT'] == null
            ? null
            : _toInt(m['odt'] ?? m['ODT']),
        sincronizado: _toInt(m['sincronizado']) == 1,
        errorSync: m['error_sync']?.toString(),
        valores: _vals(m),
      );

  static Map<String, double?> _vals(Map<String, dynamic> m) {
    final v = <String, double?>{};
    for (final ax in ['H', 'V', 'A']) {
      for (int i = 1; i <= 9; i++) {
        final k = '$ax$i';
        final raw = m[k] ?? m[k.toLowerCase()];
        final value = _toDouble(raw);
        if (value != null) v[k] = value;
      }
    }
    return v;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }
}

// ── UltimaLectura — última fila de MOT_VIBR_MUES para un equipo ──────
class UltimaLectura {
  final int localizacion;
  final String fecha;
  final String hora;
  final Map<String, double?> valores;
  final double? rms;

  const UltimaLectura({
    required this.localizacion,
    required this.fecha,
    required this.hora,
    required this.valores,
    this.rms,
  });

  factory UltimaLectura.fromJson(Map<String, dynamic> j) => UltimaLectura(
        localizacion: _int(j['LOCALIZACION'] ?? j['localizacion'] ?? 0),
        fecha: (j['FECHA'] ?? j['fecha'] ?? '').toString(),
        hora: (j['HORA'] ?? j['hora'] ?? '').toString(),
        rms: _double(j['RMS'] ?? j['rms']),
        valores: () {
          final v = <String, double?>{};
          for (final ax in ['H', 'V', 'A']) {
            for (int i = 1; i <= 9; i++) {
              final k = '$ax$i';
              final value = _double(j[k] ?? j[k.toLowerCase()]);
              if (value != null) v[k] = value;
            }
          }
          return v;
        }(),
      );

  /// Fecha/hora normalizada para decidir cuál lectura es realmente la última.
  DateTime get fechaHora {
    final f = fecha.trim();
    final h = hora.trim();

    final isoFecha = f.contains('T')
        ? f.split('T').first
        : f.contains(' ')
            ? f.split(' ').first
            : f;
    final isoHora = h.contains('T')
        ? h.split('T').last
        : h.contains(' ')
            ? h.split(' ').last
            : h;

    final iso = DateTime.tryParse(
      '${isoFecha}T${isoHora.isEmpty ? '00:00:00' : isoHora}',
    );
    if (iso != null) return iso;

    final match = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
    ).firstMatch(isoFecha);
    if (match != null) {
      final parts = isoHora.split(':');
      var year = int.tryParse(match.group(3) ?? '') ?? 1970;
      if (year < 100) year += 2000;
      return DateTime(
        year,
        int.tryParse(match.group(2) ?? '') ?? 1,
        int.tryParse(match.group(1) ?? '') ?? 1,
        parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        parts.length > 2 ? int.tryParse(parts[2].split('.').first) ?? 0 : 0,
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _double(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}
