import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('las mediciones solo se suben desde sincronizacion USB', () {
    final syncScreen = File('lib/screens/sync_screen.dart').readAsStringSync();
    final appProvider =
        File('lib/providers/app_provider.dart').readAsStringSync();

    expect(syncScreen, isNot(contains('Subir por red / API')));
    expect(syncScreen, isNot(contains('_uploadPendingByApi')));
    expect(syncScreen, isNot(contains('AppProvider.instance.sincronizar')));
    expect(appProvider, isNot(contains('sincronizarMedicion(')));
    expect(appProvider, isNot(contains('syncTemperature(')));
  });

  test('el APK USB se genera en modo debug coherente', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseBlock = RegExp(
      r'release\s*\{([\s\S]*?)\n\s*\}',
    ).firstMatch(gradle)?.group(1);

    expect(releaseBlock, isNotNull);
    expect(releaseBlock, isNot(contains('isDebuggable = true')));

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('android:debuggable="true"')));

    final buildScript = File('build_usb_apk.ps1');
    expect(buildScript.existsSync(), isTrue);
    if (!buildScript.existsSync()) return;
    expect(
      buildScript.readAsStringSync(),
      contains('flutter build apk --debug --target-platform android-arm64'),
    );
  });
}
