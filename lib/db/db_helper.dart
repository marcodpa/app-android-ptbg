import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/medicion_remota.dart';
import '../models/qr_code_matcher.dart' as qr_matcher;
import '../models/replacement_request.dart';
import '../models/temperature_measurement.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._();
  static Database? _db;
  DbHelper._();

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'scv_ptbg.db');
    return openDatabase(
      path,
      version: 9,
      onCreate: _create,
      onUpgrade: _upgrade,
      onOpen: (db) async {
        await _ensureSchema(db);
      },
    );
  }

  Future<void> _create(Database db, int version) async {
    await _createBaseTables(db);
    await _ensureSchema(db);
  }

  Future<void> _upgrade(Database db, int oldV, int newV) async {
    await _createBaseTables(db);
    await _ensureSchema(db);
  }

  Future<void> _createBaseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS EQUIPOS (
        ID            INTEGER PRIMARY KEY,
        CODE_SYS      INTEGER,
        EQUIPO        TEXT,
        LOCALIZACION  INTEGER UNIQUE,
        QR_CODE       TEXT,
        PUNTOS        INTEGER DEFAULT 0,
        PT_EQ         INTEGER DEFAULT 0,
        SISTEMA       TEXT,
        SUBSISTEMA    TEXT,
        SCADA         TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS EQUIPO_INFO (
        localizacion INTEGER PRIMARY KEY,
        marca        TEXT,
        serial       TEXT,
        modelo       TEXT,
        hp           TEXT,
        start        TEXT,
        volts        TEXT,
        fla          TEXT,
        sf           TEXT,
        hz           TEXT,
        ph           TEXT,
        rpm          TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS USUARIOS (
        id       INTEGER PRIMARY KEY,
        usuario  TEXT UNIQUE,
        cargo    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS MEDICIONES_LOCAL (
        uuid          TEXT PRIMARY KEY,
        localizacion  INTEGER,
        sistema       TEXT,
        fecha         TEXT,
        hora          TEXT,
        H1 REAL, V1 REAL, A1 REAL,
        H2 REAL, V2 REAL, A2 REAL,
        H3 REAL, V3 REAL, A3 REAL,
        H4 REAL, V4 REAL, A4 REAL,
        H5 REAL, V5 REAL, A5 REAL,
        H6 REAL, V6 REAL, A6 REAL,
        H7 REAL, V7 REAL, A7 REAL,
        H8 REAL, V8 REAL, A8 REAL,
        H9 REAL, V9 REAL, A9 REAL,
        RMS           REAL,
        observaciones TEXT,
        responsable   TEXT,
        cargo         TEXT,
        marca         TEXT,
        modelo        TEXT,
        serial        TEXT,
        sincronizado  INTEGER DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ULTIMA_LECTURA (
        localizacion  INTEGER PRIMARY KEY,
        fecha         TEXT,
        hora          TEXT,
        fecha_hora_iso TEXT,
        H1 REAL, V1 REAL, A1 REAL,
        H2 REAL, V2 REAL, A2 REAL,
        H3 REAL, V3 REAL, A3 REAL,
        H4 REAL, V4 REAL, A4 REAL,
        H5 REAL, V5 REAL, A5 REAL,
        H6 REAL, V6 REAL, A6 REAL,
        H7 REAL, V7 REAL, A7 REAL,
        H8 REAL, V8 REAL, A8 REAL,
        H9 REAL, V9 REAL, A9 REAL,
        RMS REAL
      )
    ''');

    await _createRemoteMeasurementTable(db);
    await _createReplacementTable(db);
    await _createTemperatureTables(db);
    await _createAlignmentTables(db);
  }

  Future<void> _createAlignmentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ALINEACIONES_LOCAL (
        uuid                TEXT PRIMARY KEY,
        localizacion        INTEGER NOT NULL,
        sistema             TEXT,
        puntos              INTEGER NOT NULL DEFAULT 0,
        fecha               TEXT,
        hora                TEXT,
        AMB_ANGULO_V REAL,
        AMB_ANGULO_H REAL,
        AMB_COMPENSACION_V REAL,
        AMB_COMPENSACION_H REAL,
        ACM_ANGULO_V REAL,
        ACM_ANGULO_H REAL,
        ACM_COMPENSACION_V REAL,
        ACM_COMPENSACION_H REAL,
        ACB_ANGULO_V REAL,
        ACB_ANGULO_H REAL,
        ACB_COMPENSACION_V REAL,
        ACB_COMPENSACION_H REAL,
        observaciones       TEXT,
        responsable         TEXT,
        cargo               TEXT,
        marca               TEXT,
        modelo              TEXT,
        serial              TEXT,
        odt                 INTEGER,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync          TEXT,
        created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_ALINEACIONES_PENDING
      ON ALINEACIONES_LOCAL(sincronizado, created_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ALINEACIONES_REMOTAS (
        remote_key          TEXT PRIMARY KEY,
        localizacion        INTEGER NOT NULL,
        sistema             TEXT,
        puntos              INTEGER NOT NULL DEFAULT 0,
        fecha               TEXT,
        hora                TEXT,
        fecha_hora_iso      TEXT,
        AMB_ANGULO_V REAL,
        AMB_ANGULO_H REAL,
        AMB_COMPENSACION_V REAL,
        AMB_COMPENSACION_H REAL,
        ACM_ANGULO_V REAL,
        ACM_ANGULO_H REAL,
        ACM_COMPENSACION_V REAL,
        ACM_COMPENSACION_H REAL,
        ACB_ANGULO_V REAL,
        ACB_ANGULO_H REAL,
        ACB_COMPENSACION_V REAL,
        ACB_COMPENSACION_H REAL,
        observaciones       TEXT,
        responsable         TEXT,
        cargo               TEXT,
        marca               TEXT,
        modelo              TEXT,
        serial              TEXT,
        odt                 INTEGER,
        updated_at          TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_ALINEACIONES_REMOTAS_FECHA
      ON ALINEACIONES_REMOTAS(fecha_hora_iso DESC)
    ''');
  }

  Future<void> _createTemperatureTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS TEMPERATURAS_LOCAL (
        uuid          TEXT PRIMARY KEY,
        localizacion  INTEGER NOT NULL,
        sistema       TEXT,
        fecha         TEXT,
        hora          TEXT,
        T1 REAL, T2 REAL, T3 REAL, T4 REAL, T5 REAL,
        T6 REAL, T7 REAL, T8 REAL, T9 REAL, T10 REAL,
        observaciones TEXT,
        responsable   TEXT,
        cargo         TEXT,
        marca         TEXT,
        modelo        TEXT,
        serial        TEXT,
        odt           INTEGER,
        sincronizado  INTEGER DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_TEMP_LOCAL_PENDING
      ON TEMPERATURAS_LOCAL(sincronizado, created_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ULTIMA_TEMPERATURA (
        localizacion   INTEGER PRIMARY KEY,
        fecha          TEXT,
        hora           TEXT,
        fecha_hora_iso TEXT,
        T1 REAL, T2 REAL, T3 REAL, T4 REAL, T5 REAL,
        T6 REAL, T7 REAL, T8 REAL, T9 REAL, T10 REAL,
        sistema        TEXT,
        observaciones  TEXT,
        responsable    TEXT,
        cargo          TEXT,
        marca          TEXT,
        modelo         TEXT,
        serial         TEXT,
        odt            INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS TEMPERATURAS_REMOTAS (
        remote_key      TEXT PRIMARY KEY,
        localizacion    INTEGER NOT NULL,
        sistema         TEXT,
        fecha           TEXT,
        hora            TEXT,
        fecha_hora_iso  TEXT,
        T1 REAL, T2 REAL, T3 REAL, T4 REAL, T5 REAL,
        T6 REAL, T7 REAL, T8 REAL, T9 REAL, T10 REAL,
        observaciones   TEXT,
        responsable     TEXT,
        cargo           TEXT,
        marca           TEXT,
        modelo          TEXT,
        serial          TEXT,
        odt             INTEGER,
        updated_at      TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_TEMP_REMOTA_FECHA
      ON TEMPERATURAS_REMOTAS(fecha_hora_iso DESC)
    ''');
  }

  Future<void> _createReplacementTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS REEMPLAZOS_LOCAL (
        uuid            TEXT PRIMARY KEY,
        operation_uuid  TEXT NOT NULL,
        localizacion    INTEGER NOT NULL,
        code_conjunto   INTEGER NOT NULL,
        equipo          INTEGER NOT NULL,
        marca           TEXT NOT NULL,
        modelo          TEXT NOT NULL,
        serial          TEXT NOT NULL,
        actualizar_especificaciones INTEGER NOT NULL DEFAULT 0,
        voltaje         TEXT,
        corriente       TEXT,
        rpm             TEXT,
        sf              TEXT,
        hp              TEXT,
        frame           TEXT,
        brgs_drive      TEXT,
        brgs_opp        TEXT,
        ciclo           TEXT,
        arranque        TEXT,
        ph              TEXT,
        tension         TEXT,
        lubricacion     TEXT,
        fecha           TEXT NOT NULL,
        hora            TEXT NOT NULL,
        sincronizado    INTEGER DEFAULT 0,
        error_sync      TEXT,
        created_at      TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_REEMPLAZOS_PENDING
      ON REEMPLAZOS_LOCAL(sincronizado, created_at)
    ''');
  }

  Future<void> _createRemoteMeasurementTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MEDICIONES_REMOTAS (
        remote_key      TEXT PRIMARY KEY,
        id_remoto       INTEGER,
        localizacion    INTEGER NOT NULL,
        equipo          TEXT,
        tagname         TEXT,
        fecha           TEXT,
        hora            TEXT,
        fecha_hora_iso  TEXT,
        H1 REAL, V1 REAL, A1 REAL,
        H2 REAL, V2 REAL, A2 REAL,
        H3 REAL, V3 REAL, A3 REAL,
        H4 REAL, V4 REAL, A4 REAL,
        H5 REAL, V5 REAL, A5 REAL,
        H6 REAL, V6 REAL, A6 REAL,
        H7 REAL, V7 REAL, A7 REAL,
        H8 REAL, V8 REAL, A8 REAL,
        H9 REAL, V9 REAL, A9 REAL,
        RMS             REAL,
        observaciones   TEXT,
        responsable     TEXT,
        cargo           TEXT,
        marca           TEXT,
        modelo          TEXT,
        serial          TEXT,
        updated_at      TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_MED_REMOTA_LOC_FECHA
      ON MEDICIONES_REMOTAS(localizacion, fecha_hora_iso DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_MED_REMOTA_FECHA
      ON MEDICIONES_REMOTAS(fecha_hora_iso DESC)
    ''');
  }

  Future<void> _ensureSchema(Database db) async {
    await _createRemoteMeasurementTable(db);
    await _createReplacementTable(db);
    await _createTemperatureTables(db);
    await _createAlignmentTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS USUARIOS (
        id       INTEGER PRIMARY KEY,
        usuario  TEXT UNIQUE,
        cargo    TEXT
      )
    ''');

    await _addColumnIfMissing(db, 'EQUIPOS', 'PT_EQ', 'INTEGER DEFAULT 0');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SCADA', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'PUNTOS', 'INTEGER DEFAULT 0');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SISTEMA', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SUBSISTEMA', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'responsable', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'cargo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'marca', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'modelo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'serial', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_REMOTAS', 'responsable', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_REMOTAS', 'cargo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_REMOTAS', 'marca', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_REMOTAS', 'modelo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_REMOTAS', 'serial', 'TEXT');
    for (final column in const [
      'voltaje',
      'corriente',
      'rpm',
      'sf',
      'hp',
      'frame',
      'brgs_drive',
      'brgs_opp',
      'ciclo',
      'arranque',
      'ph',
      'tension',
      'lubricacion',
    ]) {
      await _addColumnIfMissing(db, 'REEMPLAZOS_LOCAL', column, 'TEXT');
    }
    await _addColumnIfMissing(
      db,
      'REEMPLAZOS_LOCAL',
      'actualizar_especificaciones',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'start', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'volts', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'fla', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'sf', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'hz', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'ph', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'rpm', 'TEXT');

    await _addColumnIfMissing(db, 'ULTIMA_LECTURA', 'fecha_hora_iso', 'TEXT');
    for (final eje in const ['H', 'V', 'A']) {
      for (int punto = 1; punto <= 9; punto++) {
        await _addColumnIfMissing(
          db,
          'ULTIMA_LECTURA',
          '$eje$punto',
          'REAL',
        );
        await _addColumnIfMissing(
          db,
          'MEDICIONES_LOCAL',
          '$eje$punto',
          'REAL',
        );
      }
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) =>
        (c['name'] ?? '').toString().toUpperCase() == column.toUpperCase());
    if (!exists) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      } catch (_) {}
    }
  }

  // ── EQUIPOS ───────────────────────────────────────────────────────

  Future<void> clearEquiposCache() async {
    final db = await database;
    await db.delete('EQUIPOS');
    await db.delete('EQUIPO_INFO');
  }

  Future<void> upsertEquipos(List<Equipo> equipos) async {
    final db = await database;
    final batch = db.batch();

    for (final e in equipos) {
      batch.insert(
        'EQUIPOS',
        {
          'ID': e.id,
          'CODE_SYS': e.codeSys,
          'EQUIPO': e.equipo,
          'LOCALIZACION': e.localizacion,
          'QR_CODE': e.qrDisplay,
          'PUNTOS': e.puntos,
          'PT_EQ': e.ptEq,
          'SISTEMA': e.sistema,
          'SUBSISTEMA': e.subsistema,
          'SCADA': e.scada,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final info = e.info;
      if (info != null && !info.isEmpty) {
        batch.insert(
          'EQUIPO_INFO',
          info.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    await batch.commit(noResult: true);
  }

  Future<List<Equipo>> getAllEquipos() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        e.ID,
        e.CODE_SYS,
        e.EQUIPO,
        e.LOCALIZACION,
        e.QR_CODE,
        e.PUNTOS,
        e.PT_EQ,
        e.SISTEMA,
        e.SUBSISTEMA,
        e.SCADA,
        i.marca,
        i.serial,
        i.modelo,
        i.hp,
        i.start,
        i.volts,
        i.fla,
        i.sf,
        i.hz,
        i.ph,
        i.rpm
      FROM EQUIPOS e
      LEFT JOIN EQUIPO_INFO i ON i.localizacion = e.LOCALIZACION
      ORDER BY e.SISTEMA, e.LOCALIZACION
    ''');

    return rows.map(_equipoFromDbRow).toList();
  }

  Future<Equipo?> getEquipoByQr(String qr) async {
    final db = await database;
    final keys = _qrKeysDb(qr).toList();
    if (keys.isEmpty) return null;

    final placeholders = List.filled(keys.length, '?').join(',');
    final params = <Object?>[
      ...keys, // QR_CODE exacto normalizado
      ...keys, // SCADA/TG_EQ exacto normalizado
      ...keys, // QR_CODE sin guiones/espacios
      ...keys, // SCADA/TG_EQ sin guiones/espacios
      ...keys, // LOCALIZACION
      ...keys, // ID
    ];

    final rows = await db.rawQuery('''
      SELECT
        e.ID,
        e.CODE_SYS,
        e.EQUIPO,
        e.LOCALIZACION,
        e.QR_CODE,
        e.PUNTOS,
        e.PT_EQ,
        e.SISTEMA,
        e.SUBSISTEMA,
        e.SCADA,
        i.marca,
        i.serial,
        i.modelo,
        i.hp,
        i.start,
        i.volts,
        i.fla,
        i.sf,
        i.hz,
        i.ph,
        i.rpm
      FROM EQUIPOS e
      LEFT JOIN EQUIPO_INFO i ON i.localizacion = e.LOCALIZACION
      WHERE UPPER(TRIM(COALESCE(e.QR_CODE, ''))) IN ($placeholders)
         OR UPPER(TRIM(COALESCE(e.SCADA, ''))) IN ($placeholders)
         OR UPPER(REPLACE(REPLACE(REPLACE(TRIM(COALESCE(e.QR_CODE, '')), '-', ''), ' ', ''), '_', '')) IN ($placeholders)
         OR UPPER(REPLACE(REPLACE(REPLACE(TRIM(COALESCE(e.SCADA, '')), '-', ''), ' ', ''), '_', '')) IN ($placeholders)
         OR CAST(e.LOCALIZACION AS TEXT) IN ($placeholders)
         OR CAST(e.ID AS TEXT) IN ($placeholders)
      LIMIT 1
    ''', params);

    if (rows.isEmpty) return null;
    return _equipoFromDbRow(rows.first);
  }

  Future<Equipo?> getEquipoByLocalizacion(int localizacion) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        e.ID,
        e.CODE_SYS,
        e.EQUIPO,
        e.LOCALIZACION,
        e.QR_CODE,
        e.PUNTOS,
        e.PT_EQ,
        e.SISTEMA,
        e.SUBSISTEMA,
        e.SCADA,
        i.marca,
        i.serial,
        i.modelo,
        i.hp,
        i.start,
        i.volts,
        i.fla,
        i.sf,
        i.hz,
        i.ph,
        i.rpm
      FROM EQUIPOS e
      LEFT JOIN EQUIPO_INFO i ON i.localizacion = e.LOCALIZACION
      WHERE e.LOCALIZACION = ?
      LIMIT 1
    ''', [localizacion]);

    if (rows.isEmpty) return null;
    return _equipoFromDbRow(rows.first);
  }

  Equipo _equipoFromDbRow(Map<String, Object?> r) {
    final localizacion = _toInt(r['LOCALIZACION']);
    final info = EquipoInfo.fromJson(
      {
        'LC_EQ': localizacion,
        'MARCA_INFO': r['marca'],
        'SERIAL_INFO': r['serial'],
        'MODEL_INFO': r['modelo'],
        'HP_INFO': r['hp'],
        'START_INFO': r['start'],
        'VOLTS_INFO': r['volts'],
        'FLA_INFO': r['fla'],
        'SF_INFO': r['sf'],
        'HZ_INFO': r['hz'],
        'PH_INFO': r['ph'],
        'RPM_INFO': r['rpm'],
      },
      fallbackLocalizacion: localizacion,
    );

    return Equipo(
      id: _toInt(r['ID']),
      codeSys: _toInt(r['CODE_SYS']),
      equipo: (r['EQUIPO'] ?? '').toString(),
      localizacion: localizacion,
      qrCode: r['QR_CODE']?.toString(),
      puntos: _toInt(r['PUNTOS']),
      ptEq: _toInt(r['PT_EQ']),
      sistema: (r['SISTEMA'] ?? '').toString(),
      subsistema: (r['SUBSISTEMA'] ?? '').toString(),
      scada: r['SCADA']?.toString(),
      info: info.isEmpty ? null : info,
    );
  }

  // ── INFO EQUIPO (PTBG_DAT.MOT_DATA) ─────────────────────────────────

  Future<void> upsertEquipoInfo(EquipoInfo info) async {
    final db = await database;
    await db.insert(
      'EQUIPO_INFO',
      info.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EquipoInfo?> getEquipoInfo(int localizacion) async {
    final db = await database;
    final rows = await db.query(
      'EQUIPO_INFO',
      where: 'localizacion = ?',
      whereArgs: [localizacion],
    );
    if (rows.isEmpty) return null;

    final info = EquipoInfo.fromJson(
      Map<String, dynamic>.from(rows.first),
      fallbackLocalizacion: localizacion,
    );

    return info.isEmpty ? null : info;
  }

  // ── MEDICIONES LOCAL ──────────────────────────────────────────────

  Future<void> insertMedicion(MedicionLocal m) async {
    final db = await database;
    final map = <String, dynamic>{
      'uuid': m.uuid,
      'localizacion': m.localizacion,
      'sistema': m.sistema,
      'fecha': m.fecha,
      'hora': m.hora,
      'RMS': m.rms,
      'observaciones': m.observaciones,
      'responsable': m.responsable,
      'cargo': m.cargo,
      'marca': m.marca,
      'modelo': m.modelo,
      'serial': m.serial,
      'sincronizado': 0,
    };

    for (final e in m.valores.entries) {
      map[e.key] = e.value;
    }

    await db.insert(
      'MEDICIONES_LOCAL',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Una captura nueva también debe convertirse inmediatamente en la última
    // lectura visible del equipo, incluso cuando la tablet está offline.
    await upsertUltimaLectura(
      UltimaLectura(
        localizacion: m.localizacion,
        fecha: m.fecha,
        hora: m.hora,
        valores: Map<String, double?>.from(m.valores),
        rms: m.rms,
      ),
    );
  }

  Future<void> updateMedicionLocal(MedicionLocal m) async {
    final db = await database;
    final map = <String, dynamic>{
      'localizacion': m.localizacion,
      'sistema': m.sistema,
      'fecha': m.fecha,
      'hora': m.hora,
      'RMS': m.rms,
      'observaciones': m.observaciones,
      'responsable': m.responsable,
      'cargo': m.cargo,
      'marca': m.marca,
      'modelo': m.modelo,
      'serial': m.serial,
      'error_sync': null,
    };

    for (final eje in const ['H', 'V', 'A']) {
      for (int punto = 1; punto <= 9; punto++) {
        final key = '$eje$punto';
        map[key] = m.valores[key];
      }
    }

    await db.update(
      'MEDICIONES_LOCAL',
      map,
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [m.uuid],
    );

    await upsertUltimaLectura(
      UltimaLectura(
        localizacion: m.localizacion,
        fecha: m.fecha,
        hora: m.hora,
        valores: Map<String, double?>.from(m.valores),
        rms: m.rms,
      ),
    );
  }

  Future<void> deleteMedicionLocal(String uuid) async {
    final db = await database;
    await db.delete(
      'MEDICIONES_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
  }

  Future<List<MedicionLocal>> getPendientes() async {
    final db = await database;
    final rows = await db.query(
      'MEDICIONES_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) => MedicionLocal.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<MedicionLocal>> getSincronizadasHoy() async {
    final db = await database;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.query(
      'MEDICIONES_LOCAL',
      where: 'sincronizado = 1 AND fecha = ?',
      whereArgs: [hoy],
    );
    return rows
        .map((r) => MedicionLocal.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<int> countErrores() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM MEDICIONES_LOCAL WHERE error_sync IS NOT NULL',
    );
    return _toInt(r.first['c']);
  }

  Future<void> markSincronizado(String uuid) async {
    final db = await database;
    await db.update(
      'MEDICIONES_LOCAL',
      {'sincronizado': 1, 'error_sync': null},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> markError(String uuid, String error) async {
    final db = await database;
    await db.update(
      'MEDICIONES_LOCAL',
      {'error_sync': error},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> clearErrors() async {
    final db = await database;
    await db.update(
      'MEDICIONES_LOCAL',
      {'error_sync': null},
      where: 'error_sync IS NOT NULL',
    );
  }

  // ── TEMPERATURAS LOCAL ────────────────────────────────────────────

  Future<void> insertTemperature(TemperatureMeasurement measurement) async {
    final db = await database;
    await db.insert(
      'TEMPERATURAS_LOCAL',
      measurement.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await upsertLatestTemperature(
        TemperatureReading(
          localizacion: measurement.localizacion,
          fecha: measurement.fecha,
          hora: measurement.hora,
          valores: Map<String, double?>.from(measurement.valores),
          sistema: measurement.sistema,
          observaciones: measurement.observaciones,
          responsable: measurement.responsable,
          cargo: measurement.cargo,
          marca: measurement.marca,
          modelo: measurement.modelo,
          serial: measurement.serial,
          odt: measurement.odt,
        ),
      );
    } catch (_) {
      // La muestra local ya está segura. La caché se reconstruye al sincronizar.
    }
  }

  Future<void> updateTemperature(TemperatureMeasurement measurement) async {
    final db = await database;
    final map = measurement.toDbMap()
      ..remove('uuid')
      ..remove('sincronizado')
      ..['error_sync'] = null;
    await db.update(
      'TEMPERATURAS_LOCAL',
      map,
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [measurement.uuid],
    );
  }

  Future<List<TemperatureMeasurement>> getPendingTemperatures() async {
    final db = await database;
    final rows = await db.query(
      'TEMPERATURAS_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => TemperatureMeasurement.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  Future<List<TemperatureMeasurement>> getLocalTemperatures() async {
    final db = await database;
    final rows = await db.query(
      'TEMPERATURAS_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
    );
    return rows
        .map((row) => TemperatureMeasurement.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  Future<int> countSyncedTemperaturesToday() async {
    final db = await database;
    final today = _datePart(DateTime.now());
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM TEMPERATURAS_LOCAL '
      'WHERE sincronizado = 1 AND fecha = ?',
      [today],
    );
    return _toInt(rows.first['c']);
  }

  Future<int> countTemperatureErrors() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM TEMPERATURAS_LOCAL '
      'WHERE error_sync IS NOT NULL',
    );
    return _toInt(rows.first['c']);
  }

  Future<void> clearTemperatureErrors() async {
    final db = await database;
    await db.update(
      'TEMPERATURAS_LOCAL',
      {'error_sync': null},
      where: 'error_sync IS NOT NULL',
    );
  }

  Future<void> markTemperatureSynced(String uuid) async {
    final db = await database;
    await db.update(
      'TEMPERATURAS_LOCAL',
      {'sincronizado': 1, 'error_sync': null},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> markTemperatureError(String uuid, String error) async {
    final db = await database;
    await db.update(
      'TEMPERATURAS_LOCAL',
      {'error_sync': error},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> upsertLatestTemperature(TemperatureReading reading) async {
    final db = await database;
    final current = await getLatestTemperature(reading.localizacion);
    if (current != null && current.fechaHora.isAfter(reading.fechaHora)) {
      return;
    }
    final map = <String, dynamic>{
      'localizacion': reading.localizacion,
      'fecha': reading.fecha,
      'hora': reading.hora,
      'fecha_hora_iso': reading.fechaHora.toIso8601String(),
      'sistema': reading.sistema,
      'observaciones': reading.observaciones,
      'responsable': reading.responsable,
      'cargo': reading.cargo,
      'marca': reading.marca,
      'modelo': reading.modelo,
      'serial': reading.serial,
      'odt': reading.odt,
    };
    for (var i = 1; i <= 10; i++) {
      map['T$i'] = reading.valores['T$i'];
    }
    await db.insert(
      'ULTIMA_TEMPERATURA',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TemperatureReading?> getLatestTemperature(int localizacion) async {
    final db = await database;
    final rows = await db.query(
      'ULTIMA_TEMPERATURA',
      where: 'localizacion = ?',
      whereArgs: [localizacion],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TemperatureReading.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<void> replaceRemoteTemperatureHistory(
    List<TemperatureReading> readings,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('TEMPERATURAS_REMOTAS');
      for (final reading in readings) {
        final map = <String, dynamic>{
          'remote_key':
              '${reading.localizacion}|${reading.fecha}|${reading.hora}',
          'localizacion': reading.localizacion,
          'sistema': reading.sistema,
          'fecha': reading.fecha,
          'hora': reading.hora,
          'fecha_hora_iso': reading.fechaHora.toIso8601String(),
          'observaciones': reading.observaciones,
          'responsable': reading.responsable,
          'cargo': reading.cargo,
          'marca': reading.marca,
          'modelo': reading.modelo,
          'serial': reading.serial,
          'odt': reading.odt,
        };
        for (var i = 1; i <= 10; i++) {
          map['T$i'] = reading.valores['T$i'];
        }
        await txn.insert(
          'TEMPERATURAS_REMOTAS',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    for (final reading in readings) {
      await upsertLatestTemperature(reading);
    }
  }

  Future<List<TemperatureReading>> getRemoteTemperatureHistory() async {
    final db = await database;
    final rows = await db.query(
      'TEMPERATURAS_REMOTAS',
      orderBy: 'fecha_hora_iso DESC',
    );
    return rows
        .map((row) =>
            TemperatureReading.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ── ALINEACIONES LOCAL Y CACHÉ REMOTA ─────────────────────────────

  Future<void> insertAlignment(AlignmentMeasurement measurement) async {
    final db = await database;
    await db.insert(
      'ALINEACIONES_LOCAL',
      measurement.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AlignmentMeasurement>> getPendingAlignments() async {
    final db = await database;
    final rows = await db.query(
      'ALINEACIONES_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => AlignmentMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<AlignmentMeasurement>> getLocalAlignments() async {
    final db = await database;
    final rows = await db.query(
      'ALINEACIONES_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
    );
    return rows
        .map(
          (row) => AlignmentMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<void> updateAlignment(AlignmentMeasurement measurement) async {
    final db = await database;
    final map = measurement.toDbMap()
      ..remove('uuid')
      ..remove('sincronizado')
      ..['error_sync'] = null;
    await db.update(
      'ALINEACIONES_LOCAL',
      map,
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [measurement.uuid],
    );
  }

  Future<void> deleteAlignment(String uuid) async {
    final db = await database;
    await db.delete(
      'ALINEACIONES_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
  }

  Future<void> markAlignmentSynced(String uuid) async {
    final db = await database;
    await db.update(
      'ALINEACIONES_LOCAL',
      {'sincronizado': 1, 'error_sync': null},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> markAlignmentError(String uuid, String error) async {
    final db = await database;
    await db.update(
      'ALINEACIONES_LOCAL',
      {'error_sync': error},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> clearAlignmentErrors() async {
    final db = await database;
    await db.update(
      'ALINEACIONES_LOCAL',
      {'error_sync': null},
      where: 'error_sync IS NOT NULL',
    );
  }

  Future<int> countAlignmentErrors() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ALINEACIONES_LOCAL '
      'WHERE error_sync IS NOT NULL',
    );
    return _toInt(rows.first['c']);
  }

  Future<int> countSyncedAlignmentsToday() async {
    final db = await database;
    final today = _datePart(DateTime.now());
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ALINEACIONES_LOCAL '
      'WHERE sincronizado = 1 AND fecha = ?',
      [today],
    );
    return _toInt(rows.first['c']);
  }

  Future<void> replaceRemoteAlignmentHistory(
    List<AlignmentMeasurement> measurements,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('ALINEACIONES_REMOTAS');
      for (final measurement in measurements) {
        final map = measurement.toDbMap()
          ..remove('uuid')
          ..remove('sincronizado')
          ..remove('error_sync')
          ..['remote_key'] = measurement.uuid
          ..['fecha_hora_iso'] = '${measurement.fecha}T${measurement.hora}';
        await txn.insert(
          'ALINEACIONES_REMOTAS',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<AlignmentMeasurement>> getRemoteAlignmentHistory() async {
    final db = await database;
    final rows = await db.query(
      'ALINEACIONES_REMOTAS',
      orderBy: 'fecha_hora_iso DESC',
    );
    return rows
        .map(
          (row) => AlignmentMeasurement.fromRemoteMap({
            ...Map<String, dynamic>.from(row),
            'uuid': row['remote_key'],
          }),
        )
        .toList();
  }

  Future<String> insertReplacement(ReplacementRequest request) async {
    if (request.components.isEmpty) {
      throw ArgumentError('Seleccione al menos un componente');
    }

    final db = await database;
    final operationUuid = const Uuid().v4();
    final now = DateTime.now();
    final fecha = _datePart(now);
    final hora = _timePart(now);

    await db.transaction((txn) async {
      for (final entry in request.components.entries) {
        final componentCode = replacementComponentCode(entry.key);
        final data = entry.value;
        await txn.insert(
          'REEMPLAZOS_LOCAL',
          {
            'uuid': '$operationUuid-$componentCode',
            'operation_uuid': operationUuid,
            'localizacion': request.equipo.localizacion,
            'code_conjunto': request.equipo.codeSys,
            'equipo': componentCode,
            ...data.toLocalMap(),
            'fecha': fecha,
            'hora': hora,
            'sincronizado': 0,
            'error_sync': null,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
    return operationUuid;
  }

  Future<List<ReplacementLocalOperation>> getPendingReplacements() async {
    final db = await database;
    final rows = await db.query(
      'REEMPLAZOS_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC, operation_uuid ASC, equipo ASC',
    );
    return ReplacementLocalOperation.fromRows(
      rows.map((row) => Map<String, dynamic>.from(row)).toList(),
    );
  }

  Future<int> countSyncedReplacementsToday() async {
    final db = await database;
    final today = _datePart(DateTime.now());
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT operation_uuid) AS c
      FROM REEMPLAZOS_LOCAL
      WHERE sincronizado = 1 AND fecha = ?
      ''',
      [today],
    );
    return _toInt(rows.first['c']);
  }

  Future<int> countReplacementErrors() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT operation_uuid) AS c
      FROM REEMPLAZOS_LOCAL
      WHERE error_sync IS NOT NULL
    ''');
    return _toInt(rows.first['c']);
  }

  Future<void> deleteReplacementOperation(String operationUuid) async {
    final db = await database;
    await db.delete(
      'REEMPLAZOS_LOCAL',
      where: 'operation_uuid = ? AND sincronizado = 0',
      whereArgs: [operationUuid],
    );
  }

  Future<void> updateReplacementOperation(
    ReplacementLocalOperation operation,
    Map<String, ReplacementData> valuesByUuid,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in operation.components) {
        final values = valuesByUuid[item.uuid];
        if (values == null) continue;
        await txn.update(
          'REEMPLAZOS_LOCAL',
          {
            ...values.toLocalMap(),
            'error_sync': null,
          },
          where: 'uuid = ? AND operation_uuid = ? AND sincronizado = 0',
          whereArgs: [item.uuid, operation.operationUuid],
        );
      }
    });
  }

  Future<void> clearReplacementErrors() async {
    final db = await database;
    await db.update(
      'REEMPLAZOS_LOCAL',
      {'error_sync': null},
      where: 'error_sync IS NOT NULL',
    );
  }

  Future<Map<int, int>> getPendingWorkCountsByLocation() async {
    final db = await database;
    final counts = <int, int>{};
    final measurementRows = await db.rawQuery('''
      SELECT localizacion, COUNT(*) AS c
      FROM MEDICIONES_LOCAL
      WHERE sincronizado = 0
      GROUP BY localizacion
    ''');
    final replacementRows = await db.rawQuery('''
      SELECT localizacion, COUNT(DISTINCT operation_uuid) AS c
      FROM REEMPLAZOS_LOCAL
      WHERE sincronizado = 0
      GROUP BY localizacion
    ''');
    for (final row in [...measurementRows, ...replacementRows]) {
      final location = _toInt(row['localizacion']);
      counts[location] = (counts[location] ?? 0) + _toInt(row['c']);
    }
    return counts;
  }

  static String _datePart(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _timePart(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  // ── HISTÓRICO REMOTO DE MARIADB ─────────────────────────────────

  /// Guarda el histórico descargado. Con [reemplazarTodo] se crea un espejo
  /// exacto del servidor; sin él solo se agregan/actualizan filas.
  Future<int> upsertMedicionesRemotas(
    List<MedicionRemota> mediciones, {
    bool reemplazarTodo = false,
  }) async {
    final db = await database;
    if (mediciones.isEmpty) {
      if (reemplazarTodo) {
        await db.transaction((txn) async {
          await txn.delete('MEDICIONES_REMOTAS');
          await txn.delete('ULTIMA_LECTURA');
        });
      }
      return 0;
    }

    await db.transaction((txn) async {
      if (reemplazarTodo) {
        await txn.delete('MEDICIONES_REMOTAS');
        await txn.delete('ULTIMA_LECTURA');
      }

      final batch = txn.batch();
      for (final medicion in mediciones) {
        batch.insert(
          'MEDICIONES_REMOTAS',
          medicion.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });

    await actualizarUltimasDesdeRemotas(mediciones);
    return mediciones.length;
  }

  Future<void> actualizarUltimasDesdeRemotas(
    List<MedicionRemota> mediciones,
  ) async {
    final ultimas = <int, MedicionRemota>{};

    for (final medicion in mediciones) {
      if (medicion.localizacion <= 0) continue;
      final actual = ultimas[medicion.localizacion];
      final esMasNueva = actual == null ||
          medicion.fechaHora.isAfter(actual.fechaHora) ||
          (medicion.fechaHora.isAtSameMomentAs(actual.fechaHora) &&
              medicion.id > actual.id);
      if (esMasNueva) ultimas[medicion.localizacion] = medicion;
    }

    for (final medicion in ultimas.values) {
      await upsertUltimaLectura(medicion.toUltimaLectura());
    }
  }

  Future<List<MedicionRemota>> getMedicionesRemotas({
    int? localizacion,
    int? limit,
  }) async {
    final db = await database;
    final rows = await db.query(
      'MEDICIONES_REMOTAS',
      where: localizacion == null ? null : 'localizacion = ?',
      whereArgs: localizacion == null ? null : [localizacion],
      orderBy: 'fecha_hora_iso DESC, id_remoto DESC',
      limit: limit,
    );

    return rows
        .map((row) => MedicionRemota.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  Future<int> countMedicionesRemotas() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM MEDICIONES_REMOTAS',
    );
    return _toInt(rows.first['total']);
  }

  Future<void> clearMedicionesRemotas() async {
    final db = await database;
    await db.delete('MEDICIONES_REMOTAS');
  }

  // ── ULTIMA LECTURA ────────────────────────────────────────────────

  Future<void> upsertUltimaLectura(UltimaLectura ul) async {
    final db = await database;

    final actual = await getUltimaLectura(ul.localizacion);
    if (actual != null && actual.fechaHora.isAfter(ul.fechaHora)) {
      // Nunca permitir que una descarga vieja reemplace una lectura más nueva.
      return;
    }

    final map = <String, dynamic>{
      'localizacion': ul.localizacion,
      'fecha': ul.fecha,
      'hora': ul.hora,
      'fecha_hora_iso': ul.fechaHora.toIso8601String(),
      'RMS': ul.rms,
    };

    for (final e in ul.valores.entries) {
      map[e.key] = e.value;
    }

    await db.insert(
      'ULTIMA_LECTURA',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UltimaLectura?> getUltimaLectura(int localizacion) async {
    final db = await database;
    final rows = await db.query(
      'ULTIMA_LECTURA',
      where: 'localizacion = ?',
      whereArgs: [localizacion],
    );
    if (rows.isEmpty) return null;

    return UltimaLectura.fromJson({
      ...Map<String, dynamic>.from(rows.first),
      'LOCALIZACION': rows.first['localizacion'],
    });
  }

  Future<Map<int, UltimaLectura>> getUltimasLecturasMap() async {
    final db = await database;
    final rows = await db.query(
      'ULTIMA_LECTURA',
      orderBy: 'fecha_hora_iso DESC',
    );

    final result = <int, UltimaLectura>{};
    for (final row in rows) {
      final lectura = UltimaLectura.fromJson({
        ...Map<String, dynamic>.from(row),
        'LOCALIZACION': row['localizacion'],
      });
      result[lectura.localizacion] = lectura;
    }
    return result;
  }

  Future<Map<String, String>?> getUsuarioLocal(String usuario) async {
    final normalized =
        usuario.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (normalized.isEmpty) return null;

    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT usuario, cargo
      FROM USUARIOS
      WHERE UPPER(TRIM(usuario)) = ?
      LIMIT 1
      ''',
      [normalized],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return {
      'usuario': (row['usuario'] ?? '').toString(),
      'cargo': (row['cargo'] ?? 'MECANICO').toString(),
    };
  }

  Future<List<Map<String, String>>> getUsuariosLocales() async {
    final db = await database;
    final rows = await db.query(
      'USUARIOS',
      orderBy: 'usuario ASC',
    );
    return rows
        .map((row) => {
              'usuario': (row['usuario'] ?? '').toString(),
              'cargo': (row['cargo'] ?? 'MECANICO').toString(),
            })
        .where((row) => row['usuario']!.trim().isNotEmpty)
        .toList();
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

Set<String> _qrKeysDb(String? raw) {
  return qr_matcher.qrKeys(raw);
}
