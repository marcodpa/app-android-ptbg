import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/filter_catalog.dart';
import '../models/sesion.dart';
import '../services/tablet_identity.dart';
import 'db_helper.dart';

/// Aislado del catálogo MOT. No usa LOCALIZACION de filtros como equipo rotativo.
class FilterStore {
  FilterStore({Future<Database> Function()? database})
      : _database = database ?? (() => DbHelper.instance.database);
  final Future<Database> Function() _database;

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_META (
      clave TEXT PRIMARY KEY, valor TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_SYSTEM (
      ID INTEGER PRIMARY KEY, SISTEMA TEXT NOT NULL, CODE_SYS INTEGER NOT NULL UNIQUE,
      PTBG_FLT INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_SUBSYSTEM (
      ID INTEGER PRIMARY KEY, CODE_SYS INTEGER NOT NULL, NAME_SUB_SYS TEXT NOT NULL,
      CODE_SUB_SYS INTEGER NOT NULL, PTBG_FLT INTEGER NOT NULL DEFAULT 0,
      UNIQUE(CODE_SYS, CODE_SUB_SYS))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_ELEMENTS (
      ID INTEGER PRIMARY KEY, TAGNAME TEXT, CODE_SYS INTEGER NOT NULL,
      CODE_SUB_SYS INTEGER NOT NULL, ELEMENTO TEXT NOT NULL, CANTIDAD INTEGER NOT NULL,
      LOCALIZACION INTEGER NOT NULL UNIQUE, MODELO TEXT, MARCA TEXT, ESPECIFICACIONES TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_CAMBIOS_LOCAL (
      uuid TEXT PRIMARY KEY, odt INTEGER NOT NULL, fecha TEXT NOT NULL, hora TEXT NOT NULL,
      sistema TEXT NOT NULL, code_sys INTEGER NOT NULL, code_sub_sys INTEGER NOT NULL,
      localizacion INTEGER NOT NULL, tagname TEXT NOT NULL, elemento TEXT NOT NULL,
      cantidad INTEGER, modelo TEXT NOT NULL, marca TEXT NOT NULL,
      especificaciones TEXT NOT NULL, observaciones TEXT NOT NULL,
      responsable TEXT NOT NULL, cargo TEXT NOT NULL, tablet_origen TEXT NOT NULL,
      sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS IDX_FILTROS_PENDING ON FILTROS_CAMBIOS_LOCAL(sincronizado)');
    await db.execute('''CREATE TABLE IF NOT EXISTS FILTROS_CATALOGO_PENDING (
      uuid TEXT PRIMARY KEY, accion TEXT NOT NULL, payload TEXT NOT NULL,
      responsable TEXT NOT NULL, tablet_origen TEXT NOT NULL,
      sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
  }

  Future<FilterCatalog> catalog() async {
    final db = await _database();
    return FilterCatalog(
        systems: await db.query('FILTROS_SYSTEM', orderBy: 'CODE_SYS'),
        subsystems: await db.query('FILTROS_SUBSYSTEM',
            orderBy: 'CODE_SYS, CODE_SUB_SYS'),
        elements: await db.query('FILTROS_ELEMENTS', orderBy: 'LOCALIZACION'));
  }

  Future<List<FilterRow>> history(
      {int? location, bool pendingOnly = false}) async {
    final db = await _database();
    return db.query('FILTROS_CAMBIOS_LOCAL',
        where: [
          if (location != null) 'localizacion = ?',
          if (pendingOnly) 'sincronizado = 0'
        ].join(' AND ').emptyToNull,
        whereArgs: location == null ? null : [location],
        orderBy: 'fecha DESC, hora DESC, odt DESC');
  }

  Future<List<FilterRow>> catalogRequests() async =>
      (await _database()).query('FILTROS_CATALOGO_PENDING',
          where: 'sincronizado = 0', orderBy: 'created_at');

  /// Orden y cambio se guardan en UNA transacción: sin ODT huérfana al fallar.
  Future<int> saveChange(FilterRow element, FilterRow details) async {
    final user = await Sesion.usuarioActual();
    final cargo = await Sesion.cargoActual();
    final origin = await TabletIdentity.origin();
    if (user.isEmpty ||
        cargo.isEmpty ||
        user.length > 150 ||
        cargo.length > 150) {
      throw StateError('Inicie sesión con responsable y cargo válidos.');
    }
    for (final field in ['modelo', 'marca', 'especificaciones']) {
      final text = filterText(details[field]);
      if (text.isEmpty ||
          text.length > (field == 'especificaciones' ? 50 : 150)) {
        throw ArgumentError('Complete $field dentro de la longitud permitida.');
      }
    }
    final db = await _database();
    final odt = await db.transaction((txn) async {
      final rows = await txn.rawQuery(
          '''SELECT e.*, s.SISTEMA FROM FILTROS_ELEMENTS e
        JOIN FILTROS_SYSTEM s ON s.CODE_SYS=e.CODE_SYS AND s.PTBG_FLT=1
        JOIN FILTROS_SUBSYSTEM sub ON sub.CODE_SYS=e.CODE_SYS AND sub.CODE_SUB_SYS=e.CODE_SUB_SYS AND sub.PTBG_FLT=1
        WHERE e.ID=? AND e.LOCALIZACION=?''',
          [element['ID'], element['LOCALIZACION']]);
      if (rows.length != 1) {
        throw StateError(
            'El filtro ya no está habilitado. Actualice el catálogo.');
      }
      final current = rows.single;
      for (final key in [
        'CANTIDAD',
        'CODE_SYS',
        'CODE_SUB_SYS',
        'ELEMENTO',
        'TAGNAME'
      ]) {
        if (current[key] != element[key]) {
          throw StateError('El catálogo cambió. Abra nuevamente el filtro.');
        }
      }
      if (filterInt(current['CANTIDAD']) <= 0) {
        throw StateError('Cantidad de catálogo inválida.');
      }
      final now = DateTime.now();
      final iso = now.toIso8601String();
      var number = now.millisecondsSinceEpoch ~/ 1000;
      final max = Sqflite.firstIntValue(await txn
              .rawQuery('SELECT MAX(odt) FROM ORDENES_TRABAJO_LOCAL')) ??
          0;
      if (number <= max) number = max + 1;
      if (number > 2147483647) {
        throw StateError('No hay numeración ODT disponible.');
      }
      await txn.insert('ORDENES_TRABAJO_LOCAL', {
        'odt': number,
        'fecha': iso.substring(0, 10),
        'hora': iso.substring(11, 19),
        'equipo': current['ELEMENTO'],
        'ubicacion': current['LOCALIZACION'],
        'code_conjunto': current['CODE_SYS'],
        'tablet_origen': origin,
        'modulo': 'filtros',
        // Only a number reservation here, never a pending MOT_INDICE entry.
        // The actual upload state lives in FILTROS_CAMBIOS_LOCAL.
        'sincronizado': 1,
      });
      await txn.insert('FILTROS_CAMBIOS_LOCAL', {
        'uuid': const Uuid().v4(),
        'odt': number,
        'fecha': iso.substring(0, 10),
        'hora': iso.substring(11, 19),
        'sistema': current['SISTEMA'],
        'code_sys': current['CODE_SYS'],
        'code_sub_sys': current['CODE_SUB_SYS'],
        'localizacion': current['LOCALIZACION'],
        'tagname': filterText(current['TAGNAME']),
        'elemento': current['ELEMENTO'],
        'cantidad': current['CANTIDAD'],
        'modelo': filterText(details['modelo']),
        'marca': filterText(details['marca']),
        'especificaciones': filterText(details['especificaciones']),
        'observaciones': filterText(details['observaciones']),
        'responsable': user,
        'cargo': cargo,
        'tablet_origen': origin
      });
      return number;
    });
    // The capture is already committed. A badge refresh must not invite retry.
    try {
      await DbHelper.instance.countPendientesSync();
    } catch (_) {}
    return odt;
  }

  /// Solicitudes administrativas, no cambios silenciosos de datos maestros.
  Future<void> requestCatalogChange(String action, FilterRow payload) async {
    if (!await Sesion.esAdmin()) throw StateError('Se requiere administrador.');
    if (!['add', 'system', 'subsystem'].contains(action)) {
      throw ArgumentError('Acción inválida.');
    }
    if (action == 'add') {
      final error = FilterCatalog.validateElement(payload);
      if (error != null) throw ArgumentError(error);
    }
    final db = await _database();
    final user = await Sesion.usuarioActual();
    if (user.isEmpty) throw StateError('Sesión sin responsable.');
    await db.insert('FILTROS_CATALOGO_PENDING', {
      'uuid': const Uuid().v4(),
      'accion': action,
      'payload': jsonEncode(payload),
      'responsable': user,
      'tablet_origen': await TabletIdentity.origin()
    });
    try {
      await DbHelper.instance.countPendientesSync();
    } catch (_) {}
  }
}

extension on String {
  String? get emptyToNull => isEmpty ? null : this;
}
