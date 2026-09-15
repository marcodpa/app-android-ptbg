import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/checklist_black_start.dart';
import '../models/checklist_compresor.dart';
import '../models/compatibilidad_equipos.dart';
import '../models/equipo_nuevo.dart';
import '../models/historial_servicio.dart';
import '../models/orden_reparacion.dart';
import '../models/pendientes_sync.dart';
import '../models/servicio_reciente.dart';
import '../models/models.dart';
import '../models/medicion_remota.dart';
import '../models/qr_code_matcher.dart' as qr_matcher;
import '../models/replacement_request.dart';
import '../models/temperature_measurement.dart';
import '../models/lubrication_measurement.dart';
import '../models/ajuste_correa.dart';
import '../models/limpieza_plato.dart';
import '../models/coupling_change.dart';
import '../models/work_order.dart';
import '../models/operation_flow.dart';
import '../services/tablet_identity.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._();
  static Database? _db;
  DbHelper._();

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<void> reopenAfterUsbSync() async {
    final current = _db;
    _db = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
    await database;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'scv_ptbg.db');
    return openDatabase(
      path,
      version: 12,
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
        cargo    TEXT,
        rol      TEXT
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
        odt           INTEGER,
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
    await _createLubricationTables(db);
    await _createCouplingChangeTable(db);
    await _createBeltAdjustmentTable(db);
    await _createWorkOrderTable(db);
  }

  Future<void> _createWorkOrderTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ORDENES_TRABAJO_LOCAL (
        odt           INTEGER PRIMARY KEY,
        fecha         TEXT NOT NULL,
        hora          TEXT NOT NULL,
        equipo        TEXT,
        ubicacion     INTEGER NOT NULL,
        code_conjunto INTEGER,
        vibracion     INTEGER NOT NULL DEFAULT 0,
        temperatura   INTEGER NOT NULL DEFAULT 0,
        alineacion    INTEGER NOT NULL DEFAULT 0,
        lubricacion   INTEGER NOT NULL DEFAULT 0,
        coupling_rpl  INTEGER NOT NULL DEFAULT 0,
        correa_ajt    INTEGER NOT NULL DEFAULT 0,
        reemplazo     INTEGER NOT NULL DEFAULT 0,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_ORDENES_TRABAJO_PENDING
      ON ORDENES_TRABAJO_LOCAL(sincronizado, created_at)
    ''');
    await _addColumnIfMissing(db, 'ORDENES_TRABAJO_LOCAL', 'limpieza_plato',
        'INTEGER NOT NULL DEFAULT 0');
    // No backfill: the current device is not evidence of a historic origin.
    await _addColumnIfMissing(
        db, 'ORDENES_TRABAJO_LOCAL', 'tablet_origen', 'TEXT');
    await db.execute('''CREATE TABLE IF NOT EXISTS LIMPIEZAS_PLATO_LOCAL (
      uuid TEXT PRIMARY KEY, localizacion INTEGER NOT NULL,
      fecha TEXT NOT NULL, hora TEXT NOT NULL,
      horas_funcionamiento INTEGER NOT NULL CHECK(horas_funcionamiento BETWEEN 0 AND 2147483647),
      observaciones TEXT, responsable TEXT, cargo TEXT,
      marca TEXT, modelo TEXT, serial TEXT, odt INTEGER NOT NULL,
      sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS IDX_PLATO_PENDING ON LIMPIEZAS_PLATO_LOCAL(sincronizado, created_at)');
  }

  /// Ajustes de correa: solo los ventiladores y fin-fan llevan.
  Future<void> _createBeltAdjustmentTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AJUSTES_CORREA_LOCAL (
        uuid          TEXT PRIMARY KEY,
        localizacion  INTEGER NOT NULL,
        sistema       TEXT,
        fecha         TEXT NOT NULL,
        hora          TEXT NOT NULL,
        ajustada      INTEGER NOT NULL DEFAULT 0,
        tension       REAL,
        observaciones TEXT,
        responsable   TEXT,
        cargo         TEXT,
        marca         TEXT,
        modelo        TEXT,
        serial        TEXT,
        odt           INTEGER,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_CORREA_PENDING
      ON AJUSTES_CORREA_LOCAL(sincronizado, created_at)
    ''');
  }

  Future<void> _createCouplingChangeTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CAMBIOS_COUPLING_LOCAL (
        uuid          TEXT PRIMARY KEY,
        localizacion  INTEGER NOT NULL,
        sistema       TEXT,
        fecha         TEXT NOT NULL,
        hora          TEXT NOT NULL,
        observaciones TEXT,
        responsable   TEXT,
        cargo         TEXT,
        marca         TEXT,
        modelo        TEXT,
        serial        TEXT,
        odt           INTEGER,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_COUPLING_PENDING
      ON CAMBIOS_COUPLING_LOCAL(sincronizado, created_at)
    ''');
  }

  Future<void> _createLubricationTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS LUBRICACIONES_LOCAL (
        uuid          TEXT PRIMARY KEY,
        localizacion  INTEGER NOT NULL,
        sistema       TEXT,
        fecha         TEXT,
        hora          TEXT,
        L1 REAL, L2 REAL, L3 REAL, L4 REAL, L5 REAL,
        L6 REAL, L7 REAL, L8 REAL, L9 REAL,
        observaciones TEXT,
        responsable   TEXT,
        cargo         TEXT,
        marca         TEXT,
        modelo        TEXT,
        serial        TEXT,
        odt           INTEGER,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_LUB_LOCAL_PENDING
      ON LUBRICACIONES_LOCAL(sincronizado, created_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS LUBRICACIONES_REMOTAS (
        remote_key     TEXT PRIMARY KEY,
        localizacion   INTEGER NOT NULL,
        sistema        TEXT,
        fecha          TEXT,
        hora           TEXT,
        fecha_hora_iso TEXT,
        L1 REAL, L2 REAL, L3 REAL, L4 REAL, L5 REAL,
        L6 REAL, L7 REAL, L8 REAL, L9 REAL,
        observaciones  TEXT,
        responsable    TEXT,
        cargo          TEXT,
        marca          TEXT,
        modelo         TEXT,
        serial         TEXT,
        odt            INTEGER,
        updated_at     TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
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
        odt             INTEGER,
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

  /// Copia local del catalogo de piezas que devuelve `GET /componentes/{tipo}`.
  ///
  /// Se cachea porque el reemplazo se captura en campo, muchas veces sin
  /// señal: sin esta tabla el selector estaria vacio justo cuando se necesita.
  Future<void> _createComponentCatalogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CATALOGO_COMPONENTES (
        tipo          INTEGER NOT NULL,
        serial        TEXT NOT NULL,
        marca         TEXT,
        modelo        TEXT,
        instalado     INTEGER NOT NULL DEFAULT 0,
        localizacion  INTEGER,
        equipo        TEXT,
        ultima_fecha  TEXT,
        actualizado   TEXT,
        PRIMARY KEY (tipo, serial)
      )
    ''');
    // Inventario: la tabla maestra de MariaDB manda. `estado` es la condicion
    // de la pieza y `sitio` donde esta fisicamente cuando no esta instalada.
    // Cambios de estatus hechos en campo, a la espera de subir. El tecnico
    // marca un motor como averiado sin señal y esto viaja en la proxima
    // sincronizacion por USB.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CAMBIOS_ESTADO_LOCAL (
        uuid          TEXT PRIMARY KEY,
        tipo          INTEGER NOT NULL,
        serial        TEXT NOT NULL,
        estado        TEXT NOT NULL,
        localizacion  TEXT,
        observaciones TEXT,
        usuario       TEXT,
        cargo         TEXT,
        fecha         TEXT NOT NULL,
        hora          TEXT NOT NULL,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_CAMBIOS_ESTADO_PENDING
      ON CAMBIOS_ESTADO_LOCAL(sincronizado, created_at)
    ''');

    // Ordenes de reparacion. El estatus de una pieza deja de editarse a mano:
    // ahora es consecuencia de una orden, que siempre deja quien, cuando y por
    // que. Una orden es de UNA pieza; dos motores del mismo dia vuelven en
    // fechas distintas y con trabajos distintos.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ORDENES_REPARACION_LOCAL (
        uuid              TEXT PRIMARY KEY,
        tipo              INTEGER NOT NULL,
        serial            TEXT NOT NULL,
        marca             TEXT,
        modelo            TEXT,
        ubicacion_origen  INTEGER,
        destino           TEXT NOT NULL,
        motivo            TEXT,
        fecha_salida      TEXT NOT NULL,
        hora_salida       TEXT NOT NULL,
        usuario_salida    TEXT,
        cargo_salida      TEXT,
        odt               INTEGER,
        estado_orden      TEXT NOT NULL DEFAULT 'ABIERTA',
        fecha_retorno     TEXT,
        hora_retorno      TEXT,
        usuario_cierre    TEXT,
        cargo_cierre      TEXT,
        trabajo_realizado TEXT,
        resultado         TEXT,
        ubicacion_final   TEXT,
        observaciones     TEXT,
        sincronizado      INTEGER NOT NULL DEFAULT 0,
        error_sync        TEXT,
        created_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS IDX_ORDENES_REP_ABIERTAS
      ON ORDENES_REPARACION_LOCAL(estado_orden, created_at)
    ''');

    // Equipos registrados en campo que aun no existen en la planta. Al subir se
    // reparten en MOT_EQUIPO (identidad), MOT_DATA (placa del motor) y la
    // maestra de cada pieza. Aqui van juntos porque hasta que suben son un
    // solo trabajo pendiente del tecnico.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS EQUIPOS_NUEVOS_LOCAL (
        uuid            TEXT PRIMARY KEY,
        localizacion    INTEGER NOT NULL UNIQUE,
        equipo          TEXT NOT NULL,
        code_sys        INTEGER NOT NULL,
        sistema         TEXT,
        subsistema      TEXT,
        tagname         TEXT,
        code_qr         TEXT,
        pt_eq           INTEGER NOT NULL,
        code_conjunto   INTEGER,
        familia_compat  INTEGER,
        marca           TEXT,
        modelo          TEXT,
        serial          TEXT,
        hp              TEXT,
        arranque        TEXT,
        voltaje         TEXT,
        corriente       TEXT,
        sf              TEXT,
        ciclo           TEXT,
        ph              TEXT,
        rpm             TEXT,
        frame           TEXT,
        brgs_drive      TEXT,
        brgs_opp        TEXT,
        lubricacion     TEXT,
        motores_lub     TEXT,
        cant_mot_lub    REAL,
        elec_mot_lub    REAL,
        man_mot_lub     REAL,
        elemento_lub    TEXT,
        cant_elem_lub   REAL,
        elec_elem_lub   REAL,
        man_elem_lub    REAL,
        sin_lubricacion INTEGER NOT NULL DEFAULT 0,
        piezas_json     TEXT,
        usuario         TEXT,
        cargo           TEXT,
        fecha           TEXT NOT NULL,
        hora            TEXT NOT NULL,
        sincronizado    INTEGER NOT NULL DEFAULT 0,
        error_sync      TEXT,
        created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Check list de compresores de aire (formato SF-OP-FOR-040).
    //
    // Los compresores no llevan ninguno de los protocolos de medicion, asi que
    // no encajan en ninguna tabla existente: su mantenimiento es esta
    // inspeccion guiada y va aparte.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CHECKLIST_COMPRESOR_LOCAL (
        uuid            TEXT PRIMARY KEY,
        localizacion    INTEGER NOT NULL,
        equipo          TEXT,
        subsistema      TEXT,
        tag             TEXT,
        fecha           TEXT NOT NULL,
        hora            TEXT NOT NULL,
        h_inicio        TEXT,
        h_fin           TEXT,
        n_horas         INTEGER,
        n_arranques     INTEGER,
        act1            INTEGER NOT NULL DEFAULT 0,
        act1_obs        TEXT,
        act2            INTEGER NOT NULL DEFAULT 0,
        act2_obs        TEXT,
        act3            INTEGER NOT NULL DEFAULT 0,
        act3_obs        TEXT,
        act4            INTEGER NOT NULL DEFAULT 0,
        act4_obs        TEXT,
        act5            INTEGER NOT NULL DEFAULT 0,
        act5_obs        TEXT,
        act6            INTEGER NOT NULL DEFAULT 0,
        act6_obs        TEXT,
        act7            INTEGER NOT NULL DEFAULT 0,
        act7_obs        TEXT,
        act8            INTEGER NOT NULL DEFAULT 0,
        act8_obs        TEXT,
        act9            INTEGER NOT NULL DEFAULT 0,
        act9_obs        TEXT,
        act10            INTEGER NOT NULL DEFAULT 0,
        act10_obs        TEXT,
        act11            INTEGER NOT NULL DEFAULT 0,
        act11_obs        TEXT,
        mtto_lub_uf      TEXT,
        mtto_lub_uh      TEXT,
        mtto_lub_obs     TEXT,
        mtto_inh_uf      TEXT,
        mtto_inh_uh      TEXT,
        mtto_inh_obs     TEXT,
        mtto_air_uf      TEXT,
        mtto_air_uh      TEXT,
        mtto_air_obs     TEXT,
        mtto_ace_uf      TEXT,
        mtto_ace_uh      TEXT,
        mtto_ace_obs     TEXT,
        usuario         TEXT,
        cargo           TEXT,
        odt             INTEGER,
        sincronizado    INTEGER NOT NULL DEFAULT 0,
        error_sync      TEXT,
        created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Check list del generador de arranque en negro (SF-OP-FOR-036).
    //
    // Sin localizacion ni equipo: el black start es uno solo en la planta, asi
    // que no hace falta decir cual.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CHECKLIST_BLACK_START_LOCAL (
        uuid              TEXT PRIMARY KEY,
        fecha             TEXT NOT NULL,
        hora              TEXT NOT NULL,
        trabajo_hrs       TEXT,
        refrigerante_lvl  TEXT,
        combustible_lvl   TEXT,
        aceite_lvl        TEXT,
        voltaje_bat       TEXT,
        amperaje_bat      TEXT,
        filtro_aceite     INTEGER NOT NULL DEFAULT 0,
        filtro_aire       INTEGER NOT NULL DEFAULT 0,
        panel_control     INTEGER NOT NULL DEFAULT 0,
        correa            INTEGER NOT NULL DEFAULT 0,
        observaciones     TEXT,
        usuario           TEXT,
        cargo             TEXT,
        odt               INTEGER,
        sincronizado      INTEGER NOT NULL DEFAULT 0,
        error_sync        TEXT,
        created_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await _addColumnIfMissing(db, 'CATALOGO_COMPONENTES', 'estado', 'TEXT');
    await _addColumnIfMissing(db, 'CATALOGO_COMPONENTES', 'sitio', 'TEXT');
    await _addColumnIfMissing(db, 'CATALOGO_COMPONENTES', 'activo', 'INTEGER');
    await _addColumnIfMissing(
        db, 'CATALOGO_COMPONENTES', 'code_conjunto', 'INTEGER');
  }

  /// Reemplaza el catalogo de un tipo. Se borra y se reescribe entero porque el
  /// backend manda la foto completa: una pieza que desaparecio de la lista es
  /// una pieza que ya no debe ofrecerse.
  Future<void> saveComponentCatalog(
    int tipo,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn
          .delete('CATALOGO_COMPONENTES', where: 'tipo = ?', whereArgs: [tipo]);
      final batch = txn.batch();
      for (final row in rows) {
        if ((row['serial'] ?? '').toString().trim().isEmpty) continue;
        batch.insert(
          'CATALOGO_COMPONENTES',
          {...row, 'tipo': tipo, 'actualizado': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Registra un cambio de estatus hecho en campo y lo refleja de una vez en
  /// el inventario local, para que el tecnico vea el resultado sin esperar a
  /// sincronizar.
  ///
  /// No toca `instalado`: que una pieza este puesta en un equipo lo decide el
  /// reemplazo, nunca un cambio manual de estatus.
  Future<void> registrarCambioEstado({
    required String uuid,
    required int tipo,
    required String serial,
    required String estado,
    String? localizacion,
    String? observaciones,
    String? usuario,
    String? cargo,
  }) async {
    final db = await database;
    final ahora = DateTime.now();
    final fecha = ahora.toIso8601String().substring(0, 10);
    final hora = ahora.toIso8601String().substring(11, 19);

    await db.transaction((txn) async {
      await txn.insert(
        'CAMBIOS_ESTADO_LOCAL',
        {
          'uuid': uuid,
          'tipo': tipo,
          'serial': serial,
          'estado': estado,
          'localizacion': localizacion,
          'observaciones': observaciones,
          'usuario': usuario,
          'cargo': cargo,
          'fecha': fecha,
          'hora': hora,
          'sincronizado': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'CATALOGO_COMPONENTES',
        {'estado': estado, 'sitio': localizacion},
        where: 'tipo = ? AND UPPER(TRIM(serial)) = ?',
        whereArgs: [tipo, serial.trim().toUpperCase()],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getPendingEstadoChanges() async {
    final db = await database;
    return db.query(
      'CAMBIOS_ESTADO_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Descarta un cambio de estatus que aun no se ha subido.
  ///
  /// Sirve para los que nunca van a poder subir: por ejemplo una pieza que
  /// figuraba en el catalogo viejo pero no existe en la tabla maestra. El
  /// inventario local no se toca porque la proxima descarga USB lo reescribe
  /// entero desde MariaDB.
  Future<void> deleteEstadoChange(String uuid) async {
    final db = await database;
    await db.delete(
      'CAMBIOS_ESTADO_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
  }

  Future<int> countPendingEstadoChanges() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM CAMBIOS_ESTADO_LOCAL WHERE sincronizado = 0',
    );
    return _toInt(rows.first['c']);
  }

  // ── ORDENES DE REPARACION ────────────────────────────────────────────────

  /// Crea la orden y deja la pieza EN REPARACION en el inventario local, para
  /// que el tecnico vea el efecto sin esperar a sincronizar.
  Future<void> crearOrdenReparacion(OrdenReparacion orden) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'ORDENES_REPARACION_LOCAL',
        orden.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'CATALOGO_COMPONENTES',
        {'estado': estadoEnReparacion, 'sitio': orden.destino},
        where: 'tipo = ? AND UPPER(TRIM(serial)) = ?',
        whereArgs: [orden.tipo, orden.serial.trim().toUpperCase()],
      );
    });
    await refrescarAvisos();
  }

  /// Cierra la orden y aplica al inventario el estatus que dicta el resultado.
  Future<void> cerrarOrdenReparacion(OrdenReparacion orden) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'ORDENES_REPARACION_LOCAL',
        orden.toDbMap()..remove('uuid'),
        where: 'uuid = ?',
        whereArgs: [orden.uuid],
      );
      await txn.update(
        'CATALOGO_COMPONENTES',
        {'estado': orden.estadoPieza, 'sitio': orden.ubicacionFinal},
        where: 'tipo = ? AND UPPER(TRIM(serial)) = ?',
        whereArgs: [orden.tipo, orden.serial.trim().toUpperCase()],
      );
    });
    await refrescarAvisos();
  }

  Future<List<OrdenReparacion>> getOrdenesReparacion({bool? abiertas}) async {
    final db = await database;
    final rows = await db.query(
      'ORDENES_REPARACION_LOCAL',
      where: abiertas == null
          ? null
          : abiertas
              ? "UPPER(TRIM(estado_orden)) <> 'CERRADA'"
              : "UPPER(TRIM(estado_orden)) = 'CERRADA'",
      orderBy: 'created_at DESC',
    );
    return rows.map(OrdenReparacion.fromMap).toList();
  }

  /// Refresca los dos avisos de ordenes en una sola consulta.
  ///
  /// - Abiertas: solo las sincronizadas. El pendiente que se muestra en la
  ///   barra es el de la planta, no el de esta tablet. Una orden recien creada
  ///   existe y se ve en la lista marcada "sin enviar", pero no suma hasta que
  ///   sube y el resto de las tablets puede verla.
  /// - Sin enviar: lo creado o cerrado aqui que aun no ha subido.
  ///
  /// Van juntos porque cualquier movimiento cambia los dos: crear una orden
  /// suma una sin enviar, y sincronizarla la pasa a abierta. Y van en un solo
  /// SELECT porque cada consulta cruza el canal de plataforma de sqflite: dos
  /// viajes donde alcanza uno se notan cuando esto se llama seguido.
  Future<void> refrescarContadoresOrdenes() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT "
      "SUM(CASE WHEN UPPER(TRIM(estado_orden)) <> 'CERRADA' "
      "         AND sincronizado = 1 THEN 1 ELSE 0 END) AS abiertas, "
      "SUM(CASE WHEN sincronizado = 0 THEN 1 ELSE 0 END) AS sin_enviar "
      "FROM ORDENES_REPARACION_LOCAL",
    );
    final fila = rows.first;
    ordenesAbiertasNotifier.value = _toInt(fila['abiertas']);
    ordenesSinEnviarNotifier.value = _toInt(fila['sin_enviar']);
  }

  /// Refresca de una vez todos los avisos que pinta la barra lateral.
  Future<void> refrescarAvisos() async {
    await refrescarContadoresOrdenes();
    await countPendientesSync();
  }

  /// Tablas locales cuyo contenido viaja al servidor.
  ///
  /// Es la misma lista que suma la pantalla de sincronizar; si aparece una
  /// tabla nueva con `sincronizado`, va aqui o el punto rojo mentira.
  static const _tablasPendientesSync = <String>[
    'MEDICIONES_LOCAL',
    'TEMPERATURAS_LOCAL',
    'LUBRICACIONES_LOCAL',
    'ALINEACIONES_LOCAL',
    'REEMPLAZOS_LOCAL',
    'CAMBIOS_COUPLING_LOCAL',
    'AJUSTES_CORREA_LOCAL',
    'LIMPIEZAS_PLATO_LOCAL',
    'CAMBIOS_ESTADO_LOCAL',
    'ORDENES_REPARACION_LOCAL',
    'EQUIPOS_NUEVOS_LOCAL',
    'CHECKLIST_COMPRESOR_LOCAL',
    'CHECKLIST_BLACK_START_LOCAL',
  ];

  /// Los ultimos trabajos que SI subieron a la planta.
  ///
  /// Es el reverso de [countPendientesSync]: aquella cuenta lo que falta,
  /// esta confirma lo que llego. Sin esto el tecnico sincroniza y su trabajo
  /// desaparece de la pantalla sin decirle que quedo registrado.
  ///
  /// Va en una sola consulta con UNION ALL en vez de ocho consultas y un
  /// ordenamiento en Dart: para quedarse con cuatro filas no vale la pena
  /// traer a memoria todo el historico de ocho tablas.
  ///
  /// Ordena por texto porque fecha y hora se guardan en ISO
  /// (`2026-08-25`, `08:15:07`), donde el orden alfabetico y el cronologico
  /// son el mismo. Si algun dia se guardaran como `25/08/2026`, esto ordena
  /// mal en silencio.
  Future<List<ServicioReciente>> serviciosRecientes({int limite = 4}) async {
    final db = await database;
    const fuentes = <String, String>{
      'vibracion': 'MEDICIONES_LOCAL',
      'temperatura': 'TEMPERATURAS_LOCAL',
      'lubricacion': 'LUBRICACIONES_LOCAL',
      'alineacion': 'ALINEACIONES_LOCAL',
      'reemplazo': 'REEMPLAZOS_LOCAL',
      'coupling': 'CAMBIOS_COUPLING_LOCAL',
      'ajuste_correa': 'AJUSTES_CORREA_LOCAL',
      'limpieza_plato': 'LIMPIEZAS_PLATO_LOCAL',
      'checklist_compresor': 'CHECKLIST_COMPRESOR_LOCAL',
    };
    final partes = fuentes.entries
        .map((e) => "SELECT '${e.key}' AS servicio, localizacion, fecha, hora "
            'FROM ${e.value} WHERE sincronizado = 1')
        .toList();
    // El black start no tiene localizacion: es uno solo en la planta y su
    // registro no cuelga de ningun equipo del inventario.
    partes.add("SELECT 'black_start' AS servicio, NULL AS localizacion, "
        'fecha, hora FROM CHECKLIST_BLACK_START_LOCAL WHERE sincronizado = 1');

    try {
      final filas = await db.rawQuery(
        '${partes.join(' UNION ALL ')} '
        'ORDER BY fecha DESC, hora DESC LIMIT ?',
        [limite],
      );
      return filas
          .map(ServicioReciente.deFila)
          .whereType<ServicioReciente>()
          .toList();
    } catch (_) {
      // Una instalacion nueva puede no tener alguna de las tablas todavia.
      // Quedarse sin la lista de recientes no justifica tumbar el inicio.
      return const [];
    }
  }

  /// Todo lo que quedo guardado en la tablet y no ha subido.
  ///
  /// Las ocho tablas se suman en una sola consulta con subselects. Antes era un
  /// COUNT por tabla dentro de un for: ocho viajes al canal de sqflite cada vez
  /// que alguien miraba el punto rojo.
  ///
  /// Ademas de devolver el numero refresca el valor compartido, para que el
  /// punto rojo de la barra se entere sin tener que entrar a sincronizar.
  Future<int> countPendientesSync() async {
    final db = await database;
    final sumas = _tablasPendientesSync
        .map((t) => '(SELECT COUNT(*) FROM $t WHERE sincronizado = 0)')
        .join(' + ');
    final rows = await db.rawQuery('SELECT $sumas AS c');
    final total = _toInt(rows.first['c']);
    pendientesSyncNotifier.value = total;
    return total;
  }

  Future<List<Map<String, dynamic>>> getPendingOrdenesReparacion() async {
    final db = await database;
    return db.query(
      'ORDENES_REPARACION_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteOrdenReparacion(String uuid) async {
    final db = await database;
    await db.delete(
      'ORDENES_REPARACION_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
    await refrescarAvisos();
  }

  // ── BLACK START ──────────────────────────────────────────────────────────

  /// Numero de orden para un trabajo que no cuelga de un equipo.
  ///
  /// El black start no tiene LOCALIZACION —es uno solo en la planta— asi que
  /// no puede pasar por createWorkOrder, que parte de un equipo. La ODT se
  /// numera igual que las demas para que el consecutivo no se rompa, y la fila
  /// queda con ubicacion 0, que ninguna consulta de equipos llega a mirar.
  Future<int> crearOrdenSuelta(String nombre) async {
    final tabletOrigen = await TabletIdentity.origin();
    final db = await database;
    return db.transaction((txn) async {
      var odt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (odt > 2147483640) odt = 2147483640;
      while ((await txn.query(
        'ORDENES_TRABAJO_LOCAL',
        columns: const ['odt'],
        where: 'odt = ?',
        whereArgs: [odt],
        limit: 1,
      ))
          .isNotEmpty) {
        odt++;
      }
      final ahora = DateTime.now().toIso8601String();
      await txn.insert('ORDENES_TRABAJO_LOCAL', {
        'odt': odt,
        'fecha': ahora.substring(0, 10),
        'hora': ahora.substring(11, 19),
        'equipo': nombre,
        'tablet_origen': tabletOrigen,
        'ubicacion': 0,
        'code_conjunto': 0,
        'sincronizado': 0,
      });
      return odt;
    });
  }

  Future<void> insertChecklistBlackStart(ChecklistBlackStart checklist) async {
    final db = await database;
    await db.insert(
      'CHECKLIST_BLACK_START_LOCAL',
      checklist.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await countPendientesSync();
  }

  Future<List<ChecklistBlackStart>> getChecklistsBlackStart() async {
    final db = await database;
    final rows = await db.query(
      'CHECKLIST_BLACK_START_LOCAL',
      orderBy: 'fecha DESC, hora DESC',
    );
    return rows.map(ChecklistBlackStart.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingChecklistsBlackStart() async {
    final db = await database;
    return db.query(
      'CHECKLIST_BLACK_START_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteChecklistBlackStart(String uuid) async {
    final db = await database;
    await db.delete(
      'CHECKLIST_BLACK_START_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
    await countPendientesSync();
  }

  // ── COMPRESORES DE AIRE ──────────────────────────────────────────────────

  /// Codigo del sistema AIRE COMPRIMIDO en MOT_SYSTEM.
  ///
  /// Los equipos de este sistema no se miden: se les llena el check list
  /// SF-OP-FOR-040. Por eso se apartan del resto en toda la app.
  static const codeSysAireComprimido = 9;

  /// Los compresores de aire, para su propia pantalla.
  Future<List<Equipo>> getCompresores() async {
    final db = await database;
    final rows = await db.query(
      'EQUIPOS',
      where: 'CODE_SYS = ?',
      whereArgs: [codeSysAireComprimido],
      orderBy: 'LOCALIZACION',
    );
    return rows
        .map((r) => Equipo.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> insertChecklistCompresor(ChecklistCompresor checklist) async {
    final db = await database;
    await db.insert(
      'CHECKLIST_COMPRESOR_LOCAL',
      checklist.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await countPendientesSync();
  }

  /// Check lists de un compresor, del mas reciente al mas viejo.
  ///
  /// El orden se calcula con el criterio compartido y no con un ORDER BY de
  /// texto: los check list bajados de MOT_COMP_CHKL traen la FECHA como la
  /// haya guardado la planta, y comparar '19/08/2026' contra '2026-08-19'
  /// como cadenas elegiria mal cual fue el ultimo. De ese orden depende la
  /// 'ultima vez' que se le muestra al mecanico en cada tarea.
  Future<List<ChecklistCompresor>> getChecklistsCompresor(
    int localizacion,
  ) async {
    final db = await database;
    final rows = await db.query(
      'CHECKLIST_COMPRESOR_LOCAL',
      where: 'localizacion = ?',
      whereArgs: [localizacion],
    );
    return historialCompresorConReferencias(
      rows.map(ChecklistCompresor.fromMap),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChecklistsCompresor() async {
    final db = await database;
    return db.query(
      'CHECKLIST_COMPRESOR_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Cuantos check list tiene cada compresor, para la lista de equipos.
  Future<Map<int, int>> conteoChecklistsPorCompresor() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT localizacion, COUNT(*) AS n FROM CHECKLIST_COMPRESOR_LOCAL '
      'GROUP BY localizacion',
    );
    return {
      for (final f in rows) _toInt(f['localizacion']): _toInt(f['n']),
    };
  }

  Future<void> deleteChecklistCompresor(String uuid) async {
    final db = await database;
    await db.delete(
      'CHECKLIST_COMPRESOR_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
    await countPendientesSync();
  }

  // ── EQUIPOS NUEVOS ───────────────────────────────────────────────────────

  /// Siguiente LOCALIZACION libre.
  ///
  /// Mira los equipos que ya conoce la tablet y los que estan por subir, para
  /// no repetir un numero que ya se uso aqui mismo y aun no ha viajado. Dos
  /// tablets sin sincronizar todavia podrian elegir el mismo: eso lo resuelve
  /// el uploader al subir, que es quien ve la planta completa.
  Future<int> siguienteLocalizacion() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MAX(m) AS m FROM ('
      '  SELECT MAX(LOCALIZACION) AS m FROM EQUIPOS'
      '  UNION ALL'
      '  SELECT MAX(localizacion) AS m FROM EQUIPOS_NUEVOS_LOCAL'
      ')',
    );
    return _toInt(rows.first['m']) + 1;
  }

  /// Subsistemas ya usados, para proponerlos en vez de escribirlos a mano.
  ///
  /// Se filtran por sistema porque un subsistema pertenece a uno: ofrecer los
  /// de toda la planta invitaria a mezclarlos.
  Future<List<String>> subsistemasDe(int codeSys) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT SUBSISTEMA AS s FROM EQUIPOS "
      "WHERE CODE_SYS = ? AND TRIM(COALESCE(SUBSISTEMA,'')) <> '' "
      "ORDER BY SUBSISTEMA",
      [codeSys],
    );
    return rows.map((r) => (r['s'] ?? '').toString()).toList(growable: false);
  }

  /// Sistemas conocidos, como pares codigo/nombre.
  Future<List<Map<String, dynamic>>> sistemasDisponibles() async {
    final db = await database;
    return db.rawQuery(
      "SELECT DISTINCT CODE_SYS AS code, SISTEMA AS nombre FROM EQUIPOS "
      "WHERE CODE_SYS IS NOT NULL AND TRIM(COALESCE(SISTEMA,'')) <> '' "
      "ORDER BY CODE_SYS",
    );
  }

  /// Guarda el equipo y lo deja visible de una vez en la lista de la tablet.
  ///
  /// Se escribe tambien en EQUIPOS para que aparezca junto a los demas sin
  /// esperar a sincronizar; la ficha va a EQUIPO_INFO por lo mismo. Lo que no
  /// puede hacerse todavia es medirlo: eso lo bloquea la pantalla, mirando si
  /// la LOCALIZACION sigue pendiente de subir.
  Future<void> crearEquipoNuevo(EquipoNuevo equipo) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'EQUIPOS_NUEVOS_LOCAL',
        equipo.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'EQUIPOS',
        {
          'CODE_SYS': equipo.codeSys,
          'EQUIPO': equipo.equipo,
          'LOCALIZACION': equipo.localizacion,
          'QR_CODE': equipo.codeQr,
          'PUNTOS': equipo.ptEq,
          'PT_EQ': equipo.ptEq,
          'SISTEMA': equipo.sistema,
          'SUBSISTEMA': equipo.subsistema,
          'SCADA': equipo.tagname,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'EQUIPO_INFO',
        {
          'localizacion': equipo.localizacion,
          'marca': equipo.motor.marca,
          'serial': equipo.motor.serial,
          'modelo': equipo.motor.modelo,
          'hp': equipo.motor.hp,
          'start': equipo.motor.arranque,
          'volts': equipo.motor.voltaje,
          'fla': equipo.motor.corriente,
          'sf': equipo.motor.sf,
          'hz': equipo.motor.ciclo,
          'ph': equipo.motor.ph,
          'rpm': equipo.motor.rpm,
          'brgs_drive': equipo.motor.brgsDrive,
          'brgs_opp': equipo.motor.brgsOpp,
          'lubricacion': equipo.motor.lubricacion,
          'motores_lub': equipo.motor.motoresLub,
          'cant_mot_lub': equipo.motor.cantMotLub,
          'elec_mot_lub': equipo.motor.elecMotLub,
          'man_mot_lub': equipo.motor.manMotLub,
          'elemento_lub': equipo.motor.elementoLub,
          'cant_elem_lub': equipo.motor.cantElemLub,
          'elec_elem_lub': equipo.motor.elecElemLub,
          'man_elem_lub': equipo.motor.manElemLub,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await countPendientesSync();
  }

  Future<List<EquipoNuevo>> getEquiposNuevos() async {
    final db = await database;
    final rows = await db.query(
      'EQUIPOS_NUEVOS_LOCAL',
      orderBy: 'created_at DESC',
    );
    return rows.map(EquipoNuevo.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingEquiposNuevos() async {
    final db = await database;
    return db.query(
      'EQUIPOS_NUEVOS_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Localizaciones registradas aqui que aun no han subido.
  ///
  /// Son las que no se pueden medir todavia: el servidor no las conoce y la
  /// medicion se rechazaria al sincronizar.
  Future<Set<int>> localizacionesSinEnviar() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT localizacion FROM EQUIPOS_NUEVOS_LOCAL WHERE sincronizado = 0',
    );
    return rows.map((r) => _toInt(r['localizacion'])).toSet();
  }

  /// Familias declaradas por ubicacion, para el filtro de compatibilidad.
  ///
  /// La lista fija del codigo solo cubre las 51 ubicaciones originales. Aqui se
  /// juntan las que vienen de la planta (EQUIPOS.FAMILIA_COMPAT, que llega al
  /// sincronizar y es la que ven todas las tablets) con las de los equipos
  /// registrados aqui y aun sin subir, que solo existen en esta tablet.
  ///
  /// Las locales van al final a proposito: si el equipo ya subio y en la planta
  /// le corrigieron la familia, manda lo que dice la planta.
  Future<Map<int, int>> familiasAsignadas() async {
    final db = await database;
    final asignadas = <int, int>{};

    final locales = await db.rawQuery(
      'SELECT localizacion, familia_compat FROM EQUIPOS_NUEVOS_LOCAL '
      'WHERE familia_compat IS NOT NULL AND sincronizado = 0',
    );
    for (final fila in locales) {
      asignadas[_toInt(fila['localizacion'])] = _toInt(fila['familia_compat']);
    }

    final remotas = await db.rawQuery(
      'SELECT LOCALIZACION, FAMILIA_COMPAT FROM EQUIPOS '
      'WHERE FAMILIA_COMPAT IS NOT NULL',
    );
    for (final fila in remotas) {
      asignadas[_toInt(fila['LOCALIZACION'])] = _toInt(fila['FAMILIA_COMPAT']);
    }

    return asignadas;
  }

  /// Familias de compatibilidad que existen, con un nombre para mostrarlas.
  ///
  /// La lista fija del codigo solo nombra las 10 primeras. La planta puede
  /// tener mas —hoy la 11, 12 y 13 son los tres equipos del sistema contra
  /// incendio, cada uno en la suya— asi que se completan leyendo EQUIPOS y se
  /// nombran con un equipo que ya pertenezca a ellas.
  Future<Map<int, String>> familiasExistentes() async {
    final db = await database;
    final familias = <int, String>{...CompatibilidadEquipos.opciones};

    final rows = await db.rawQuery(
      'SELECT FAMILIA_COMPAT AS familia, EQUIPO AS equipo '
      'FROM EQUIPOS WHERE FAMILIA_COMPAT IS NOT NULL '
      'GROUP BY FAMILIA_COMPAT ORDER BY FAMILIA_COMPAT',
    );
    for (final fila in rows) {
      final id = _toInt(fila['familia']);
      if (id <= 0 || familias.containsKey(id)) continue;
      final equipo = (fila['equipo'] ?? '').toString().trim();
      familias[id] = equipo.isEmpty ? 'Familia $id' : equipo;
    }
    return familias;
  }

  /// Numero que le tocaria a una familia nueva.
  ///
  /// Es solo una propuesta para enseñarla en pantalla: el numero definitivo lo
  /// asigna el servidor al subir, que es el unico que ve la planta entera.
  Future<int> siguienteFamilia() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MAX(m) AS m FROM ('
      '  SELECT MAX(FAMILIA_COMPAT) AS m FROM EQUIPOS'
      '  UNION ALL'
      '  SELECT MAX(familia_compat) AS m FROM EQUIPOS_NUEVOS_LOCAL'
      ')',
    );
    final maximo = _toInt(rows.first['m']);
    // Si la tablet aun no ha bajado las familias de la planta, al menos no
    // propone una que ya use la lista fija del codigo.
    final piso = CompatibilidadEquipos.opciones.keys
        .fold<int>(0, (a, b) => a > b ? a : b);
    return (maximo > piso ? maximo : piso) + 1;
  }

  /// Descarta un equipo que nunca salio de la tablet.
  Future<void> deleteEquipoNuevo(String uuid) async {
    final db = await database;
    final filas = await db.query(
      'EQUIPOS_NUEVOS_LOCAL',
      columns: ['localizacion'],
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
    if (filas.isEmpty) return;
    final localizacion = _toInt(filas.first['localizacion']);
    await db.transaction((txn) async {
      await txn.delete(
        'EQUIPOS_NUEVOS_LOCAL',
        where: 'uuid = ? AND sincronizado = 0',
        whereArgs: [uuid],
      );
      // Tambien se quita de la lista visible: si se descarta el registro, el
      // equipo no debe seguir apareciendo entre los de la planta.
      await txn.delete('EQUIPOS',
          where: 'LOCALIZACION = ?', whereArgs: [localizacion]);
      await txn.delete('EQUIPO_INFO',
          where: 'localizacion = ?', whereArgs: [localizacion]);
    });
    await countPendientesSync();
  }

  Future<List<Map<String, dynamic>>> getComponentCatalog(int tipo) async {
    final db = await database;
    return db.query(
      'CATALOGO_COMPONENTES',
      where: 'tipo = ?',
      whereArgs: [tipo],
      orderBy: 'instalado ASC, marca ASC, modelo ASC, serial ASC',
    );
  }

  Future<void> _ensureSchema(Database db) async {
    await _createRemoteMeasurementTable(db);
    await _createReplacementTable(db);
    await _createTemperatureTables(db);
    await _createAlignmentTables(db);
    await _createLubricationTables(db);
    await _createCouplingChangeTable(db);
    await _createBeltAdjustmentTable(db);
    await _createWorkOrderTable(db);
    await _createComponentCatalogTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS USUARIOS (
        id       INTEGER PRIMARY KEY,
        usuario  TEXT UNIQUE,
        cargo    TEXT,
        rol      TEXT
      )
    ''');

    // Bitacora del administrador: cada correccion de una medicion y cada
    // retro-fechado queda aqui con la hora REAL del reloj de la tablet
    // (nunca la elegida), quien lo hizo y que cambio. Sube a MOT_LOG_ADM en
    // la planta con el mismo mecanismo de pendientes que el resto de los
    // trabajos, asi la auditoria no depende de que alguien mire la tablet.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS EVENTOS_ADMIN (
        uuid          TEXT PRIMARY KEY,
        fecha         TEXT NOT NULL,
        hora          TEXT NOT NULL,
        usuario       TEXT NOT NULL,
        cargo         TEXT,
        accion        TEXT NOT NULL,
        servicio      TEXT,
        localizacion  INTEGER,
        uuid_medicion TEXT,
        detalle       TEXT,
        sincronizado  INTEGER NOT NULL DEFAULT 0,
        error_sync    TEXT,
        created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    // Una tablet que ya tenga la primera version de la bitacora —sin UUID ni
    // columnas de sincronizacion— no vuelve a pasar por el CREATE de arriba:
    // hay que completarle las columnas o el registro del evento fallaria.
    for (final columna in const [
      ['uuid', 'TEXT'],
      ['cargo', 'TEXT'],
      ['sincronizado', 'INTEGER NOT NULL DEFAULT 0'],
      ['error_sync', 'TEXT'],
      ['created_at', 'TEXT'],
    ]) {
      await _addColumnIfMissing(db, 'EVENTOS_ADMIN', columna[0], columna[1]);
    }

    await _addColumnIfMissing(db, 'USUARIOS', 'rol', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'PT_EQ', 'INTEGER DEFAULT 0');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SCADA', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'PUNTOS', 'INTEGER DEFAULT 0');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SISTEMA', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'SUBSISTEMA', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPOS', 'FAMILIA_COMPAT', 'INTEGER');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'responsable', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'cargo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'marca', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'modelo', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'serial', 'TEXT');
    await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', 'odt', 'INTEGER');
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
    await _addColumnIfMissing(db, 'REEMPLAZOS_LOCAL', 'odt', 'INTEGER');
    // Que se dano en la pieza que sale. Viaja a MOT_LOG_RPL.MOTIVO.
    await _addColumnIfMissing(db, 'REEMPLAZOS_LOCAL', 'motivo', 'TEXT');
    // Con que estatus y en que sitio queda la pieza retirada. La elige el
    // tecnico: solo el sabe si sirve, quedo averiada o se desecha.
    await _addColumnIfMissing(
        db, 'REEMPLAZOS_LOCAL', 'estado_saliente', 'TEXT');
    await _addColumnIfMissing(db, 'REEMPLAZOS_LOCAL', 'sitio_saliente', 'TEXT');
    // Coupling e inserto se cambian por separado: puede tocarse uno, el otro o
    // los dos. Por eso son dos banderas y no una sola respuesta.
    await _addColumnIfMissing(
        db, 'CAMBIOS_COUPLING_LOCAL', 'coupling', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'CAMBIOS_COUPLING_LOCAL', 'inserto', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'CAMBIOS_COUPLING_LOCAL', 'modelo_cplg', 'TEXT');

    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'start', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'volts', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'fla', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'sf', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'hz', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'ph', 'TEXT');
    await _addColumnIfMissing(db, 'EQUIPO_INFO', 'rpm', 'TEXT');
    for (final column in const [
      'brgs_drive',
      'brgs_opp',
      'lubricacion',
      'motores_lub',
      'cant_mot_lub',
      'elec_mot_lub',
      'man_mot_lub',
      'elemento_lub',
      'cant_elem_lub',
      'elec_elem_lub',
      'man_elem_lub',
    ]) {
      await _addColumnIfMissing(
        db,
        'EQUIPO_INFO',
        column,
        column.startsWith('cant_') ||
                column.startsWith('elec_') ||
                column.startsWith('man_')
            ? 'REAL'
            : 'TEXT',
      );
    }

    await _addColumnIfMissing(db, 'ULTIMA_LECTURA', 'fecha_hora_iso', 'TEXT');
    for (final eje in const ['H', 'V', 'A']) {
      for (int punto = 1; punto <= 9; punto++) {
        await _addColumnIfMissing(db, 'ULTIMA_LECTURA', '$eje$punto', 'REAL');
        await _addColumnIfMissing(db, 'MEDICIONES_LOCAL', '$eje$punto', 'REAL');
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
    final exists = cols.any(
      (c) => (c['name'] ?? '').toString().toUpperCase() == column.toUpperCase(),
    );
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
            'FAMILIA_COMPAT': e.familiaCompat,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

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

  /// Cuantos equipos tiene la tablet. Se usa para NO pisar un catalogo
  /// bajado de la planta con el catalogo base incrustado en la app.
  Future<int> contarEquipos() async {
    final db = await database;
    final filas = await db.rawQuery('SELECT COUNT(*) AS n FROM EQUIPOS');
    return filas.isEmpty ? 0 : _toInt(filas.first['n']);
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
        i.rpm,
        i.brgs_drive, i.brgs_opp, i.lubricacion, i.motores_lub,
        i.cant_mot_lub, i.elec_mot_lub, i.man_mot_lub,
        i.elemento_lub, i.cant_elem_lub, i.elec_elem_lub, i.man_elem_lub
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
        i.rpm,
        i.brgs_drive, i.brgs_opp, i.lubricacion, i.motores_lub,
        i.cant_mot_lub, i.elec_mot_lub, i.man_mot_lub,
        i.elemento_lub, i.cant_elem_lub, i.elec_elem_lub, i.man_elem_lub
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
    final rows = await db.rawQuery(
      '''
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
        i.rpm,
        i.brgs_drive, i.brgs_opp, i.lubricacion, i.motores_lub,
        i.cant_mot_lub, i.elec_mot_lub, i.man_mot_lub,
        i.elemento_lub, i.cant_elem_lub, i.elec_elem_lub, i.man_elem_lub
      FROM EQUIPOS e
      LEFT JOIN EQUIPO_INFO i ON i.localizacion = e.LOCALIZACION
      WHERE e.LOCALIZACION = ?
      LIMIT 1
    ''',
      [localizacion],
    );

    if (rows.isEmpty) return null;
    return _equipoFromDbRow(rows.first);
  }

  Equipo _equipoFromDbRow(Map<String, Object?> r) {
    final localizacion = _toInt(r['LOCALIZACION']);
    final info = EquipoInfo.fromJson({
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
      'BRGS_DRIVE': r['brgs_drive'],
      'BRGS_OPP': r['brgs_opp'],
      'LUBRICACION': r['lubricacion'],
      'MOTORES_LUB': r['motores_lub'],
      'CANT_MOT_LUB': r['cant_mot_lub'],
      'ELEC_MOT_LUB': r['elec_mot_lub'],
      'MAN_MOT_LUB': r['man_mot_lub'],
      'ELEMENTO_LUB': r['elemento_lub'],
      'CANT_ELEM_LUB': r['cant_elem_lub'],
      'ELEC_ELEM_LUB': r['elec_elem_lub'],
      'MAN_ELEM_LUB': r['man_elem_lub'],
    }, fallbackLocalizacion: localizacion);

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
      'odt': m.odt,
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

  Future<void> deleteMedicionLocal(String uuid) =>
      _eliminarPendiente('MEDICIONES_LOCAL', uuid);

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

  Future<int> countErrores() => _contarErroresSync('MEDICIONES_LOCAL');

  // ── Operaciones comunes de las tablas sincronizables ──────────────────
  //
  // Las seis tablas de servicios locales comparten el mismo contrato de
  // sincronizacion (uuid, sincronizado, error_sync, fecha), asi que estas
  // operaciones de una sentencia viven una sola vez aqui y los metodos
  // publicos —cuyos nombres citan los llamadores y los tests de contrato—
  // son delegaciones de una linea. Antes cada tabla tenia su copia y ya
  // habian empezado a divergir en detalles ("as c" vs "AS c", dos maneras
  // de calcular la fecha de hoy).
  //
  // Quedan fuera a proposito: los conteos de REEMPLAZOS_LOCAL, que cuentan
  // operaciones con COUNT(DISTINCT operation_uuid) y no filas, y
  // deleteReplacementOperation, que borra por operation_uuid.

  Future<void> _marcarSincronizado(String tabla, String uuid) async {
    final db = await database;
    await db.update(
      tabla,
      {'sincronizado': 1, 'error_sync': null},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> _marcarErrorSync(String tabla, String uuid, String error) async {
    final db = await database;
    await db.update(
      tabla,
      {'error_sync': error},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> _limpiarErroresSync(String tabla) async {
    final db = await database;
    await db.update(
      tabla,
      {'error_sync': null},
      where: 'error_sync IS NOT NULL',
    );
  }

  Future<int> _contarErroresSync(String tabla) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tabla WHERE error_sync IS NOT NULL',
    );
    return _toInt(rows.first['c']);
  }

  Future<int> _contarSincronizadosHoy(String tabla) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tabla WHERE sincronizado = 1 AND fecha = ?',
      [_datePart(DateTime.now())],
    );
    return _toInt(rows.first['c']);
  }

  /// Borra un registro local que aun no subio. Los ya sincronizados no se
  /// tocan: en la planta ya existen y borrarlos aqui solo desincronizaria.
  Future<void> _eliminarPendiente(String tabla, String uuid) async {
    final db = await database;
    await db.delete(
      tabla,
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
  }

  Future<void> markSincronizado(String uuid) =>
      _marcarSincronizado('MEDICIONES_LOCAL', uuid);

  Future<void> markError(String uuid, String error) =>
      _marcarErrorSync('MEDICIONES_LOCAL', uuid, error);

  Future<void> clearErrors() => _limpiarErroresSync('MEDICIONES_LOCAL');

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
        .map(
          (row) =>
              TemperatureMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<TemperatureMeasurement>> getLocalTemperatures() async {
    final db = await database;
    final rows = await db.query(
      'TEMPERATURAS_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
    );
    return rows
        .map(
          (row) =>
              TemperatureMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<void> deleteTemperature(String uuid) =>
      _eliminarPendiente('TEMPERATURAS_LOCAL', uuid);

  Future<int> countSyncedTemperaturesToday() =>
      _contarSincronizadosHoy('TEMPERATURAS_LOCAL');

  Future<int> countTemperatureErrors() =>
      _contarErroresSync('TEMPERATURAS_LOCAL');

  Future<void> clearTemperatureErrors() =>
      _limpiarErroresSync('TEMPERATURAS_LOCAL');

  Future<void> markTemperatureSynced(String uuid) =>
      _marcarSincronizado('TEMPERATURAS_LOCAL', uuid);

  Future<void> markTemperatureError(String uuid, String error) =>
      _marcarErrorSync('TEMPERATURAS_LOCAL', uuid, error);

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
        .map(
          (row) => TemperatureReading.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  // ── ALINEACIONES LOCAL Y CACHÉ REMOTA ─────────────────────────────

  Future<void> insertLubrication(LubricationMeasurement measurement) async {
    final db = await database;
    await db.insert(
      'LUBRICACIONES_LOCAL',
      measurement.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertCouplingChange(CouplingChange change) async {
    final db = await database;
    await db.insert(
      'CAMBIOS_COUPLING_LOCAL',
      change.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAjusteCorrea(AjusteCorrea ajuste) async {
    final db = await database;
    await db.insert(
      'AJUSTES_CORREA_LOCAL',
      ajuste.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await countPendientesSync();
  }

  Future<void> insertLimpiezaPlato(LimpiezaPlato limpieza) async {
    final db = await database;
    await db.transaction((txn) async {
      final equipos = await txn.query('EQUIPOS',
          where: 'LOCALIZACION = ? AND PUNTOS = 10',
          whereArgs: [limpieza.localizacion]);
      final ordenes = await txn.query('ORDENES_TRABAJO_LOCAL',
          where: 'odt = ? AND ubicacion = ?',
          whereArgs: [limpieza.odt, limpieza.localizacion]);
      if (equipos.isEmpty || ordenes.isEmpty) {
        throw StateError('La limpieza requiere un equipo tipo 10 y su ODT.');
      }
      await txn.insert('LIMPIEZAS_PLATO_LOCAL', limpieza.toDbMap());
      await txn.update('ORDENES_TRABAJO_LOCAL',
          {'limpieza_plato': 1, 'sincronizado': 0, 'error_sync': null},
          where: 'odt = ?', whereArgs: [limpieza.odt]);
    });
    await countPendientesSync();
  }

  Future<List<LimpiezaPlato>> getLimpiezasPlato(
      {int? localizacion, bool pendientes = false}) async {
    final db = await database;
    final filtros = [
      if (localizacion != null) 'localizacion = ?',
      if (pendientes) 'sincronizado = 0',
    ];
    final rows = await db.query('LIMPIEZAS_PLATO_LOCAL',
        where: filtros.isEmpty ? null : filtros.join(' AND '),
        whereArgs: [if (localizacion != null) localizacion],
        orderBy: 'fecha DESC, hora DESC');
    return rows.map(LimpiezaPlato.fromMap).toList();
  }

  Future<Map<String, int>> resumenLimpiezasPlato() async {
    final db = await database;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.rawQuery('''SELECT
      SUM(CASE WHEN sincronizado=1 AND fecha=? THEN 1 ELSE 0 END) AS hoy,
      SUM(CASE WHEN sincronizado=0 AND error_sync IS NOT NULL AND error_sync<>'' THEN 1 ELSE 0 END) AS errores
      FROM LIMPIEZAS_PLATO_LOCAL''', [hoy]);
    return {
      'hoy': _toInt(rows.first['hoy']),
      'errores': _toInt(rows.first['errores'])
    };
  }

  Future<void> deleteLimpiezaPlato(String uuid) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('LIMPIEZAS_PLATO_LOCAL',
          where: 'uuid = ? AND sincronizado = 0', whereArgs: [uuid]);
      if (rows.isEmpty) return;
      final odt = rows.first['odt'];
      await txn.delete('LIMPIEZAS_PLATO_LOCAL',
          where: 'uuid = ? AND sincronizado = 0', whereArgs: [uuid]);
      final restantes = await txn
          .query('LIMPIEZAS_PLATO_LOCAL', where: 'odt = ?', whereArgs: [odt]);
      if (restantes.isEmpty) {
        await txn.update(
            'ORDENES_TRABAJO_LOCAL', {'limpieza_plato': 0, 'sincronizado': 0},
            where: 'odt = ?', whereArgs: [odt]);
      }
    });
    await countPendientesSync();
  }

  /// Reclasificacion confirmada por el usuario; una sola vez, sin tocar historiales.
  Future<bool> migrarSeparadoresTipo10() async {
    final db = await database;
    await db.execute(
        'CREATE TABLE IF NOT EXISTS APP_MIGRACIONES (clave TEXT PRIMARY KEY)');
    return db.transaction((txn) async {
      const clave = 'separadores_tipo10_20260908';
      if ((await txn
              .query('APP_MIGRACIONES', where: 'clave = ?', whereArgs: [clave]))
          .isNotEmpty) {
        return false;
      }
      const equipos = {
        43: '17-06-DO_EM101_S',
        44: '17-06-DO_EM101_D',
        45: '17-06-DO_EM201'
      };
      if ((await txn.query('EQUIPOS', limit: 1)).isEmpty) {
        return false;
      }
      for (final entry in equipos.entries) {
        await txn.update('EQUIPOS', {'PUNTOS': 10, 'PT_EQ': 10},
            where:
                'LOCALIZACION = ? AND CODE_SYS = 6 AND PUNTOS = 1 AND (QR_CODE = ? OR EQUIPO = ?)',
            whereArgs: [entry.key, entry.value, entry.value]);
      }
      await txn.insert('APP_MIGRACIONES', {'clave': clave});
      return true;
    });
  }

  Future<List<AjusteCorrea>> getAjustesCorreaPendientes() async {
    final db = await database;
    final rows = await db.query(
      'AJUSTES_CORREA_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(AjusteCorrea.fromMap).toList();
  }

  Future<void> deleteAjusteCorrea(String uuid) async {
    final db = await database;
    await db.delete(
      'AJUSTES_CORREA_LOCAL',
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [uuid],
    );
    await countPendientesSync();
  }

  Future<int> createWorkOrder({
    required Equipo equipo,
    required Set<OperationType> services,
  }) async {
    final tabletOrigen = await TabletIdentity.origin();
    final db = await database;
    return db.transaction((txn) async {
      var odt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (odt > 2147483640) odt = 2147483640;
      while ((await txn.query(
        'ORDENES_TRABAJO_LOCAL',
        columns: const ['odt'],
        where: 'odt = ?',
        whereArgs: [odt],
        limit: 1,
      ))
          .isNotEmpty) {
        odt++;
      }
      final order = WorkOrder.forSelection(
        tabletOrigen: tabletOrigen,
        odt: odt,
        createdAt: DateTime.now(),
        equipo: equipo.equipo,
        ubicacion: equipo.localizacion,
        codeConjunto: equipo.codeSys,
        services: services,
      );
      await txn.insert('ORDENES_TRABAJO_LOCAL', order.toDbMap());
      return odt;
    });
  }

  Future<List<Map<String, dynamic>>> getPendingWorkOrders() async {
    final db = await database;
    return db.query(
      'ORDENES_TRABAJO_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Columnas de servicio de una orden de trabajo.
  ///
  /// Una ODT nace cuando se abre un equipo y cada servicio se marca al
  /// completarlo. Si el tecnico entra y sale sin medir, la ODT queda con todas
  /// en cero: existe, pero no registra ningun trabajo.
  static const _columnasServicioOdt = <String>[
    'vibracion',
    'temperatura',
    'alineacion',
    'lubricacion',
    'coupling_rpl',
    'correa_ajt',
    'reemplazo',
    'limpieza_plato',
  ];

  /// Ordenes de trabajo recientes del equipo.
  ///
  /// Con [soloConServicios] se dejan fuera las que no registraron ningun
  /// trabajo. La planilla oficial imprime lo que la ODT hizo, asi que una en
  /// cero no puede producir nada: mostrarla dejaba al tecnico eligiendola y
  /// encontrandose la lista de servicios vacia y el boton de imprimir muerto,
  /// sin ninguna explicacion.
  Future<List<Map<String, dynamic>>> getRecentWorkOrdersForEquipment(
    int localizacion, {
    int limit = 3,
    bool soloConServicios = false,
  }) async {
    final db = await database;
    final filtroServicios =
        _columnasServicioOdt.map((c) => '$c = 1').join(' OR ');
    return db.query(
      'ORDENES_TRABAJO_LOCAL',
      where: soloConServicios
          ? 'ubicacion = ? AND ($filtroServicios)'
          : 'ubicacion = ?',
      whereArgs: [localizacion],
      orderBy: 'created_at DESC, odt DESC',
      limit: limit,
    );
  }

  Future<void> markWorkOrderServicesNotPerformed(
    int odt,
    Iterable<OperationType> services,
  ) async {
    const columns = {
      OperationType.vibration: 'vibracion',
      OperationType.temperature: 'temperatura',
      OperationType.alignment: 'alineacion',
      OperationType.lubrication: 'lubricacion',
      OperationType.couplingChange: 'coupling_rpl',
      OperationType.replacement: 'reemplazo',
      OperationType.plateCleaning: 'limpieza_plato',
    };
    final values = <String, Object?>{};
    for (final service in services) {
      final column = columns[service];
      if (column != null) values[column] = 0;
    }
    if (values.isEmpty) return;
    final db = await database;
    await db.update(
      'ORDENES_TRABAJO_LOCAL',
      values,
      where: 'odt = ? AND sincronizado = 0',
      whereArgs: [odt],
    );
  }

  Future<List<CouplingChange>> getPendingCouplingChanges() async {
    final db = await database;
    final rows = await db.query(
      'CAMBIOS_COUPLING_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => CouplingChange.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<CouplingChange>> getLocalCouplingChanges() async {
    final db = await database;
    final rows = await db.query(
      'CAMBIOS_COUPLING_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
    );
    return rows
        .map((row) => CouplingChange.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> deleteCouplingChange(String uuid) =>
      _eliminarPendiente('CAMBIOS_COUPLING_LOCAL', uuid);

  Future<int> countSyncedCouplingChangesToday() =>
      _contarSincronizadosHoy('CAMBIOS_COUPLING_LOCAL');

  Future<int> countCouplingChangeErrors() =>
      _contarErroresSync('CAMBIOS_COUPLING_LOCAL');

  Future<List<LubricationMeasurement>> getPendingLubrications() async {
    final db = await database;
    final rows = await db.query(
      'LUBRICACIONES_LOCAL',
      where: 'sincronizado = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) =>
              LubricationMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<LubricationMeasurement>> getLocalLubrications() async {
    final db = await database;
    final rows = await db.query(
      'LUBRICACIONES_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
    );
    return rows
        .map(
          (row) =>
              LubricationMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  /// Corrige una lubricacion que aun no se ha enviado.
  ///
  /// Igual que en temperatura: solo se toca mientras `sincronizado = 0`. Una
  /// vez enviada, la version buena es la del servidor.
  Future<void> updateLubrication(LubricationMeasurement measurement) async {
    final db = await database;
    final map = measurement.toDbMap()
      ..remove('uuid')
      ..remove('sincronizado')
      ..['error_sync'] = null;
    await db.update(
      'LUBRICACIONES_LOCAL',
      map,
      where: 'uuid = ? AND sincronizado = 0',
      whereArgs: [measurement.uuid],
    );
  }

  Future<void> deleteLubrication(String uuid) =>
      _eliminarPendiente('LUBRICACIONES_LOCAL', uuid);

  Future<void> markLubricationSynced(String uuid) =>
      _marcarSincronizado('LUBRICACIONES_LOCAL', uuid);

  Future<void> markLubricationError(String uuid, String error) =>
      _marcarErrorSync('LUBRICACIONES_LOCAL', uuid, error);

  Future<int> countSyncedLubricationsToday() =>
      _contarSincronizadosHoy('LUBRICACIONES_LOCAL');

  Future<int> countLubricationErrors() =>
      _contarErroresSync('LUBRICACIONES_LOCAL');

  Future<void> clearLubricationErrors() =>
      _limpiarErroresSync('LUBRICACIONES_LOCAL');

  Future<void> replaceRemoteLubricationHistory(
    List<LubricationReading> readings,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('LUBRICACIONES_REMOTAS');
      for (final reading in readings) {
        final map = reading.toDbMap()
          ..remove('uuid')
          ..remove('sincronizado')
          ..remove('error_sync')
          ..['remote_key'] =
              '${reading.localizacion}|${reading.fecha}|${reading.hora}'
          ..['fecha_hora_iso'] = reading.fechaHora.toIso8601String();
        await txn.insert(
          'LUBRICACIONES_REMOTAS',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<LubricationReading>> getRemoteLubricationHistory() async {
    final db = await database;
    final rows = await db.query(
      'LUBRICACIONES_REMOTAS',
      orderBy: 'fecha_hora_iso DESC',
    );
    return rows
        .map(
          (row) =>
              LubricationMeasurement.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

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

  Future<void> deleteAlignment(String uuid) =>
      _eliminarPendiente('ALINEACIONES_LOCAL', uuid);

  Future<void> markAlignmentSynced(String uuid) =>
      _marcarSincronizado('ALINEACIONES_LOCAL', uuid);

  Future<void> markAlignmentError(String uuid, String error) =>
      _marcarErrorSync('ALINEACIONES_LOCAL', uuid, error);

  Future<void> clearAlignmentErrors() =>
      _limpiarErroresSync('ALINEACIONES_LOCAL');

  Future<int> countAlignmentErrors() =>
      _contarErroresSync('ALINEACIONES_LOCAL');

  Future<int> countSyncedAlignmentsToday() =>
      _contarSincronizadosHoy('ALINEACIONES_LOCAL');

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
    final existingInfo = await getEquipoInfo(request.equipo.localizacion);

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
              'odt': request.odt,
              'sincronizado': 0,
              'error_sync': null,
            },
            conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final primary = request.components[ReplacementComponent.motor] ??
          request.components.values.first;
      final updatedInfo = <String, dynamic>{
        if (existingInfo != null) ...existingInfo.toMap(),
        'localizacion': request.equipo.localizacion,
        'marca': primary.brand.trim(),
        'modelo': primary.model.trim(),
        'serial': primary.serial.trim(),
      };
      if (primary.updateTechnicalSpecs) {
        updatedInfo.addAll({
          'hp': primary.horsepower.trim(),
          'start': primary.start.trim(),
          'volts': primary.voltage.trim(),
          'fla': primary.current.trim(),
          'sf': primary.serviceFactor.trim(),
          'hz': primary.cycle.trim(),
          'ph': primary.phases.trim(),
          'rpm': primary.rpm.trim(),
          'brgs_drive': primary.driveBearing.trim(),
          'brgs_opp': primary.oppositeBearing.trim(),
          'lubricacion': primary.lubrication.trim(),
        });
      }
      await txn.insert(
        'EQUIPO_INFO',
        updatedInfo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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

  Future<List<ReplacementLocalOperation>> getLocalReplacements() async {
    final db = await database;
    final rows = await db.query(
      'REEMPLAZOS_LOCAL',
      orderBy: 'fecha DESC, hora DESC, created_at DESC, operation_uuid, equipo',
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
          {...values.toLocalMap(), 'error_sync': null},
          where: 'uuid = ? AND operation_uuid = ? AND sincronizado = 0',
          whereArgs: [item.uuid, operation.operationUuid],
        );
      }
    });
  }

  Future<void> clearReplacementErrors() =>
      _limpiarErroresSync('REEMPLAZOS_LOCAL');

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
        .map((row) => MedicionRemota.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getEquipmentServiceHistory(
    int localizacion,
    String service,
  ) async {
    final db = await database;
    const tables = <String, List<String>>{
      'vibration': ['MEDICIONES_LOCAL', 'MEDICIONES_REMOTAS'],
      'temperature': ['TEMPERATURAS_LOCAL', 'TEMPERATURAS_REMOTAS'],
      'lubrication': ['LUBRICACIONES_LOCAL', 'LUBRICACIONES_REMOTAS'],
      'alignment': ['ALINEACIONES_LOCAL', 'ALINEACIONES_REMOTAS'],
      'replacements': ['REEMPLAZOS_LOCAL'],
      'coupling_changes': ['CAMBIOS_COUPLING_LOCAL'],
    };
    final result = <Map<String, dynamic>>[];
    for (final table in tables[service] ?? const <String>[]) {
      try {
        final isLocalMirror = table.endsWith('_LOCAL') &&
            table != 'REEMPLAZOS_LOCAL' &&
            table != 'CAMBIOS_COUPLING_LOCAL';
        final rows = await db.query(
          table,
          // MariaDB manda sobre el histórico sincronizado. Las tablas *_LOCAL
          // solo aportan capturas pendientes; las filas ya subidas se leen de
          // su tabla *_REMOTAS para que un borrado en planta desaparezca de la
          // tablet en la siguiente descarga.
          where: isLocalMirror
              ? 'localizacion = ? AND sincronizado = 0'
              : 'localizacion = ?',
          whereArgs: [localizacion],
          orderBy: table == 'REEMPLAZOS_LOCAL'
              ? 'created_at DESC'
              : 'fecha DESC, hora DESC',
        );
        result.addAll(rows.map((row) => <String, dynamic>{
              ...row,
              '_source': table,
            }));
      } catch (_) {
        // Una tabla opcional puede no existir en instalaciones antiguas.
      }
    }
    // El criterio compartido con el PDF de reportes: antes cada uno depuraba
    // y ordenaba a su manera y "los ultimos 5" no coincidian entre la
    // pantalla, el reporte y MariaDB.
    return depurarYOrdenarHistorial(result);
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

  /// Anota una accion del administrador en la bitacora.
  ///
  /// La fecha y la hora las pone este metodo con el reloj real: aunque el
  /// evento sea "retro-fecho una medicion al dia anterior", el registro dice
  /// cuando lo hizo de verdad.
  Future<void> registrarEventoAdmin({
    required String usuario,
    required String accion,
    String? cargo,
    String? servicio,
    int? localizacion,
    String? uuidMedicion,
    String? detalle,
  }) async {
    final db = await database;
    final ahora = DateTime.now().toIso8601String();
    await db.insert('EVENTOS_ADMIN', {
      'uuid': const Uuid().v4(),
      'fecha': ahora.substring(0, 10),
      'hora': ahora.substring(11, 19),
      'usuario': usuario,
      'cargo': cargo,
      'accion': accion,
      'servicio': servicio,
      'localizacion': localizacion,
      'uuid_medicion': uuidMedicion,
      'detalle': detalle,
      'sincronizado': 0,
      'created_at': ahora,
    });
  }

  Future<List<Map<String, Object?>>> getEventosAdmin({int limite = 80}) async {
    final db = await database;
    return db.query(
      'EVENTOS_ADMIN',
      orderBy: 'fecha DESC, hora DESC, created_at DESC',
      limit: limite,
    );
  }

  Future<List<Map<String, String>>> getUsuariosLocales() async {
    final db = await database;
    final rows = await db.query('USUARIOS', orderBy: 'usuario ASC');
    return rows
        .map(
          (row) => {
            'usuario': (row['usuario'] ?? '').toString(),
            'cargo': (row['cargo'] ?? 'MECANICO').toString(),
            // MDB_USERS.ROL: dice quien es ADMIN sin depender del cargo.
            'rol': (row['rol'] ?? '').toString(),
          },
        )
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
