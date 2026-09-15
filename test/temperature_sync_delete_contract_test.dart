import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sincronizacion permite eliminar temperaturas pendientes', () {
    final db = File('lib/db/db_helper.dart').readAsStringSync();
    final sync = File('lib/screens/sync_screen.dart').readAsStringSync();

    expect(db, contains('Future<void> deleteTemperature(String uuid)'));
    expect(db, contains("where: 'uuid = ? AND sincronizado = 0'"));
    expect(sync, contains('_confirmDeleteTemperature'));
    expect(sync, contains('Eliminar temperatura'));
    expect(sync, contains('deleteTemperature(measurement.uuid)'));
  });
}
