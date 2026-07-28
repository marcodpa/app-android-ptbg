import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/db/db_helper.dart').readAsStringSync();
  });

  test('declara tablas local y remota con las 12 columnas exactas', () {
    expect(source, contains('CREATE TABLE IF NOT EXISTS ALINEACIONES_LOCAL'));
    expect(source, contains('CREATE TABLE IF NOT EXISTS ALINEACIONES_REMOTAS'));
    for (final column in const [
      'AMB_ANGULO_V',
      'AMB_ANGULO_H',
      'AMB_COMPENSACION_V',
      'AMB_COMPENSACION_H',
      'ACM_ANGULO_V',
      'ACM_ANGULO_H',
      'ACM_COMPENSACION_V',
      'ACM_COMPENSACION_H',
      'ACB_ANGULO_V',
      'ACB_ANGULO_H',
      'ACB_COMPENSACION_V',
      'ACB_COMPENSACION_H',
    ]) {
      expect(source, contains('$column REAL'));
    }
    expect(source, contains('sincronizado  INTEGER NOT NULL DEFAULT 0'));
    expect(source, contains('error_sync'));
    expect(source, contains('created_at'));
    expect(source, contains('IDX_ALINEACIONES_PENDING'));
  });

  test('expone CRUD, conteos y caché remota', () {
    for (final method in const [
      'insertAlignment',
      'getPendingAlignments',
      'getLocalAlignments',
      'updateAlignment',
      'deleteAlignment',
      'markAlignmentSynced',
      'markAlignmentError',
      'clearAlignmentErrors',
      'countAlignmentErrors',
      'countSyncedAlignmentsToday',
      'replaceRemoteAlignmentHistory',
      'getRemoteAlignmentHistory',
    ]) {
      expect(source, contains('$method('), reason: 'Falta $method');
    }
    expect(source, contains("where: 'sincronizado = 0'"));
    expect(source, contains("where: 'uuid = ? AND sincronizado = 0'"));
  });
}
