import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../models/filter_catalog.dart';

/// Only bootstraps a never-initialized catalog. Server snapshots always win,
/// including empty catalogs and deletions. Called inside the opening transaction.
class FilterSeed {
  static const assetPath = 'assets/data/filter_catalog.json';
  static const tables = {
    'systems': 'FILTROS_SYSTEM',
    'subsystems': 'FILTROS_SUBSYSTEM',
    'elements': 'FILTROS_ELEMENTS',
  };

  static FilterCatalog decode(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    List<FilterRow> rows(String key) => (data[key] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final catalog = FilterCatalog(
      systems: rows('systems'),
      subsystems: rows('subsystems'),
      elements: rows('elements'),
    );
    final systems = <int>{};
    final pairs = <String>{};
    final locations = <int>{};
    for (final group in [
      catalog.systems,
      catalog.subsystems,
      catalog.elements
    ]) {
      final ids = <int>{};
      for (final row in group) {
        final id = filterInt(row['ID']);
        if (id <= 0 || !ids.add(id)) {
          throw const FormatException('ID de catálogo inválido o duplicado.');
        }
      }
    }
    for (final row in catalog.systems) {
      final code = filterInt(row['CODE_SYS']);
      if (code <= 0 ||
          !systems.add(code) ||
          filterText(row['SISTEMA']).isEmpty ||
          ![0, 1].contains(row['PTBG_FLT'])) {
        throw const FormatException('Sistema de catálogo inválido.');
      }
    }
    for (final row in catalog.subsystems) {
      if (!systems.contains(row['CODE_SYS']) ||
          filterInt(row['CODE_SUB_SYS']) <= 0 ||
          !pairs.add('${row['CODE_SYS']}:${row['CODE_SUB_SYS']}') ||
          filterText(row['NAME_SUB_SYS']).isEmpty ||
          ![0, 1].contains(row['PTBG_FLT'])) {
        throw const FormatException('Subsistema de catálogo inválido.');
      }
    }
    for (final row in catalog.elements) {
      if (!pairs.contains('${row['CODE_SYS']}:${row['CODE_SUB_SYS']}') ||
          !locations.add(filterInt(row['LOCALIZACION'])) ||
          FilterCatalog.validateElement(row) != null) {
        throw const FormatException('Elemento de catálogo inválido.');
      }
    }
    return catalog;
  }

  static Future<void> ensureInitialCatalog(DatabaseExecutor db,
      {AssetBundle? bundle}) async {
    if ((await db.query('FILTROS_META',
            where: 'clave = ?', whereArgs: ['catalog_source'], limit: 1))
        .isNotEmpty) {
      return;
    }
    // Legacy installs without metadata may already hold downloaded catalogs or
    // pending work. Never fill holes in them from an older bundled snapshot.
    for (final table in [
      ...tables.values,
      'FILTROS_CAMBIOS_LOCAL',
      'FILTROS_CATALOGO_PENDING',
    ]) {
      if ((await db.query(table, limit: 1)).isNotEmpty) {
        await db.insert(
            'FILTROS_META', {'clave': 'catalog_source', 'valor': 'existing'});
        return;
      }
    }
    final catalog = decode(await (bundle ?? rootBundle).loadString(assetPath));
    for (final entry in {
      'FILTROS_SYSTEM': catalog.systems,
      'FILTROS_SUBSYSTEM': catalog.subsystems,
      'FILTROS_ELEMENTS': catalog.elements,
    }.entries) {
      for (final row in entry.value) {
        await db.insert(entry.key, row);
      }
    }
    await db.insert('FILTROS_META',
        {'clave': 'catalog_source', 'valor': 'bundled:csv-2026-09-21'});
  }
}
