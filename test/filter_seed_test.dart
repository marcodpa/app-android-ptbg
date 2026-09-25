import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/db/filter_seed.dart';
import 'package:sqflite/sqflite.dart';

class MemoryCatalogDb extends Fake implements DatabaseExecutor {
  final rows = <String, List<Map<String, Object?>>>{};
  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) async =>
      rows[table] ?? [];
  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    (rows[table] ??= []).add(Map.of(values));
    return rows[table]!.length;
  }
}

class CatalogBundle extends CachingAssetBundle {
  CatalogBundle(this.text);
  final String text;
  int loads = 0;
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loads++;
    expect(key, FilterSeed.assetPath);
    return text;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  final text = File(FilterSeed.assetPath).readAsStringSync();
  test('catálogo real: 7 sistemas, 31 subsistemas, 46 filtros', () {
    final catalog = FilterSeed.decode(text);
    expect(catalog.systems, hasLength(7));
    expect(catalog.subsystems, hasLength(31));
    expect(catalog.elements, hasLength(46));
    expect(catalog.enabledSystems.map((s) => s['CODE_SYS']), [1, 2, 3, 4]);
    expect(catalog.systems.singleWhere((s) => s['CODE_SYS'] == 3)['SISTEMA'],
        'COMBUSTIBLE DIESEL');
    expect(catalog.systems.singleWhere((s) => s['CODE_SYS'] == 4)['SISTEMA'],
        'AGUA');
    for (final code in [1, 2, 3, 4]) {
      expect(catalog.elements.where((e) => e['CODE_SYS'] == code).length,
          {1: 18, 2: 18, 3: 4, 4: 6}[code]);
    }
  });
  test('instalación inicial e idempotencia: no repone un filtro borrado',
      () async {
    final db = MemoryCatalogDb();
    final bundle = CatalogBundle(text);
    await FilterSeed.ensureInitialCatalog(db, bundle: bundle);
    expect(db.rows['FILTROS_ELEMENTS'], hasLength(46));
    db.rows['FILTROS_ELEMENTS']!.removeLast();
    await FilterSeed.ensureInitialCatalog(db, bundle: bundle);
    expect(db.rows['FILTROS_ELEMENTS'], hasLength(45));
    expect(bundle.loads, 1);
  });
  test('un catálogo vacío confirmado por servidor no se repuebla', () async {
    final db = MemoryCatalogDb();
    db.rows['FILTROS_META'] = [
      {'clave': 'catalog_source', 'valor': 'server'}
    ];
    final bundle = CatalogBundle(text);
    await FilterSeed.ensureInitialCatalog(db, bundle: bundle);
    expect(db.rows['FILTROS_ELEMENTS'], isNull);
    expect(bundle.loads, 0);
  });
  for (final table in [
    ...FilterSeed.tables.values,
    'FILTROS_CAMBIOS_LOCAL',
    'FILTROS_CATALOGO_PENDING'
  ]) {
    test('preserva datos previos sin metadatos en $table', () async {
      final db = MemoryCatalogDb();
      db.rows[table] = [
        {'ID': 999}
      ];
      final bundle = CatalogBundle(text);
      await FilterSeed.ensureInitialCatalog(db, bundle: bundle);
      expect(bundle.loads, 0);
      expect(db.rows[table], [
        {'ID': 999}
      ]);
      expect(db.rows['FILTROS_META']!.single['valor'], 'existing');
    });
  }
  test('rechaza relaciones inválidas antes de escribir', () async {
    final data = jsonDecode(text) as Map<String, dynamic>;
    data['elements'][0]['CODE_SYS'] = 99;
    final db = MemoryCatalogDb();
    await expectLater(
        FilterSeed.ensureInitialCatalog(db,
            bundle: CatalogBundle(jsonEncode(data))),
        throwsFormatException);
    expect(db.rows, isEmpty);
  });
  test('rechaza localizaciones duplicadas y cantidad cero', () {
    final data = jsonDecode(text) as Map<String, dynamic>;
    data['elements'][1]['LOCALIZACION'] = data['elements'][0]['LOCALIZACION'];
    expect(() => FilterSeed.decode(jsonEncode(data)), throwsFormatException);
    data['elements'][1]['LOCALIZACION'] = 2;
    data['elements'][0]['CANTIDAD'] = 0;
    expect(() => FilterSeed.decode(jsonEncode(data)), throwsFormatException);
  });
}
