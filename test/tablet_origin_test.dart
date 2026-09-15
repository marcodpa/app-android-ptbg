import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/work_order.dart';
import 'package:scv_ptbg/services/tablet_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(TabletIdentity.channel, null);
  });

  test('identifica el dispositivo actual, no una copia de su base', () async {
    var current = 'TAB_R7 / 1234567890abcdef';
    messenger.setMockMethodCallHandler(TabletIdentity.channel, (call) async {
      expect(call.method, 'getTabletOrigin');
      return current;
    });
    expect(await TabletIdentity.origin(), current);
    expect(await TabletIdentity.origin(), current);
    current = 'TAB_R7 / fedcba0987654321';
    expect(await TabletIdentity.origin(), current);
  });

  test('no inventa identificador si Android no puede proporcionarlo', () async {
    for (final invalid in <String?>[null, '', '   ', 'x' * 101]) {
      messenger.setMockMethodCallHandler(
          TabletIdentity.channel, (_) async => invalid);
      await expectLater(TabletIdentity.origin(), throwsStateError);
    }
    messenger.setMockMethodCallHandler(TabletIdentity.channel, (_) async {
      throw PlatformException(code: 'TABLET_ID_UNAVAILABLE');
    });
    await expectLater(
        TabletIdentity.origin(), throwsA(isA<PlatformException>()));
  });

  test('una ODT agrupa vibracion y lubricacion con el mismo origen', () {
    final order = WorkOrder.forSelection(
      odt: 100,
      createdAt: DateTime(2026, 9, 10, 11, 0),
      equipo: 'SEPARADOR',
      ubicacion: 43,
      codeConjunto: 6,
      services: {OperationType.vibration, OperationType.lubrication},
      tabletOrigen: 'TAB_R7 / 1234567890abcdef',
    ).toDbMap();
    expect(order['tablet_origen'], 'TAB_R7 / 1234567890abcdef');
    expect(order['vibracion'], 1);
    expect(order['lubricacion'], 1);
    expect(order['sincronizado'], 0);
  });
}
