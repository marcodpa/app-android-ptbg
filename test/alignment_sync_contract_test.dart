import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sync;
  late String home;

  setUpAll(() {
    sync = File('lib/screens/sync_screen.dart').readAsStringSync();
    home = File('lib/screens/home_screen.dart').readAsStringSync();
  });

  test('Sync carga, cuenta y presenta alineaciones pendientes', () {
    expect(sync, contains('_alignmentPendientes'));
    expect(sync, contains('getPendingAlignments()'));
    expect(sync, contains('_AlignmentPendRow'));
    expect(sync, contains('Alineación LOC-'));
    expect(sync, contains('_editAlignment'));
    expect(sync, contains('_confirmDeleteAlignment'));
    expect(sync, contains('deleteAlignment('));
    expect(sync, contains('countSyncedAlignmentsToday()'));
    expect(sync, contains('countAlignmentErrors()'));
    expect(sync, contains('clearAlignmentErrors()'));
  });

  test('Sync conserva el transporte exclusivo por USB', () {
    expect(sync, isNot(contains('Subir por red / API')));
    expect(sync, isNot(contains('_uploadPendingByApi')));
    expect(sync, isNot(contains('syncAlignment')));
  });

  test('Home incluye alineaciones en sus estadísticas', () {
    // El AppProvider murió con la migración a sync exclusivo por USB.
    expect(File('lib/providers/app_provider.dart').existsSync(), isFalse);
    expect(home, contains('getPendingAlignments()'));
    expect(home, contains('countSyncedAlignmentsToday()'));
    expect(home, contains('countAlignmentErrors()'));
  });
}
