import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('las mediciones solo se suben desde sincronizacion USB', () {
    final syncScreen = File('lib/screens/sync_screen.dart').readAsStringSync();

    expect(syncScreen, isNot(contains('Subir por red / API')));
    expect(syncScreen, isNot(contains('_uploadPendingByApi')));
    expect(syncScreen, isNot(contains('AppProvider.instance.sincronizar')));
    // El AppProvider murió con la migración a sync exclusivo por USB.
    expect(File('lib/providers/app_provider.dart').existsSync(), isFalse);
  });

  test('el APK USB se genera en modo debug coherente', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseBlock = RegExp(
      r'release\s*\{([\s\S]*?)\n\s*\}',
    ).firstMatch(gradle)?.group(1);

    expect(releaseBlock, isNotNull);
    // isDebuggable = true es intencional: el flujo USB usa `adb run-as` para
    // extraer la base SQLite de la tablet sin root, y eso exige que la app sea
    // depurable. Si alguien lo quita "por seguridad", la sincronizacion por
    // USB deja de funcionar. Por eso se verifica que ESTE, no que falte.
    expect(releaseBlock, contains('isDebuggable = true'));

    // En el manifiesto sigue sin declararse: lo decide el build de Gradle, y
    // ponerlo en los dos sitios se contradice cuando uno de ellos cambia.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('android:debuggable="true"')));

    final buildScript = File('build_usb_apk.ps1');
    expect(buildScript.existsSync(), isTrue);
    if (!buildScript.existsSync()) return;
    expect(
      buildScript.readAsStringSync(),
      contains(
          r'& $FlutterCommand build apk --debug --target-platform android-arm64'),
    );
  });

  test(
      'ambos scripts actualizan el catalogo antes de compilar y abortan si falla',
      () {
    final usb = File('build_usb_apk.ps1').readAsStringSync();
    final release = File('build_apk.bat').readAsStringSync();
    expect(usb, contains('actualizar_catalogo_apk.py'));
    expect(release, contains('actualizar_catalogo_apk.py'));
    final usbPreparacion = usb.indexOf('actualizar_catalogo_apk.py');
    final usbBuild = usb.indexOf(r'& $FlutterCommand build apk');
    expect(usbPreparacion, lessThan(usbBuild));
    expect(usb.substring(usbPreparacion, usbBuild),
        contains(r'if ($LASTEXITCODE -ne 0)'));
    expect(usb.substring(usbPreparacion, usbBuild), contains('throw'));
    final releasePreparacion = release.indexOf('actualizar_catalogo_apk.py');
    final releaseBuild = release.indexOf('build apk --release');
    expect(releasePreparacion, lessThan(releaseBuild));
    expect(release.substring(releasePreparacion, releaseBuild),
        contains('if errorlevel 1 exit /b 1'));
  });
}
