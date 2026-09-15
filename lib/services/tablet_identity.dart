import 'package:flutter/services.dart';

/// Identifies the capturing tablet, independently of the database or USB host.
class TabletIdentity {
  static const channel = MethodChannel('ster/tablet_identity');

  static Future<String> origin() async {
    final value =
        (await channel.invokeMethod<String>('getTabletOrigin'))?.trim();
    if (value == null || value.isEmpty || value.length > 100) {
      throw StateError(
          'No se pudo identificar esta tablet. Intente nuevamente.');
    }
    return value;
  }
}
