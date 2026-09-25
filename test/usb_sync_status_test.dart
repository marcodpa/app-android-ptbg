import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/usb_sync_status.dart';

void main() {
  final tabletNow = DateTime(2026, 9, 22, 10);

  UsbSyncStatus receivedStatus({
    required DateTime laptopTime,
    required DateTime receivedAt,
    String status = 'ONLINE',
  }) =>
      UsbSyncStatus.fromValues(
        status: status,
        serial: 'TABR9Pro0000017971',
        detail: 'Laptop conectada',
        lastSeen: laptopTime.toIso8601String(),
        receivedAt: receivedAt,
        now: tabletNow,
        requestId: 'usb-test',
      );

  for (final offset in [-86400, -3600, -33, 33, 3600, 86400]) {
    test('recepcion USB reciente admite desfase de $offset segundos', () {
      final status = receivedStatus(
        laptopTime: tabletNow.add(Duration(seconds: offset)),
        receivedAt: tabletNow.subtract(const Duration(seconds: 3)),
      );
      expect(status.online, isTrue);
      expect(status.lastSeen, tabletNow.add(Duration(seconds: offset)));
      expect(status.requestId, 'usb-test');
    });
  }

  test('archivo vencido no revive aunque la hora de laptop parezca reciente',
      () {
    final status = receivedStatus(
      laptopTime: tabletNow,
      receivedAt: tabletNow.subtract(const Duration(seconds: 26)),
    );
    expect(status.online, isFalse);
  });

  test('cable desconectado vence y otra señal local recupera la conexion', () {
    final laptopTime = tabletNow.subtract(const Duration(hours: 4));
    for (final age in [3, 25, 26, 120, 1]) {
      expect(
          receivedStatus(
            laptopTime: laptopTime,
            receivedAt: tabletNow.subtract(Duration(seconds: age)),
          ).online,
          age <= 25);
    }
  });

  test('OFFLINE o estado desconocido no se aceptan por tener archivo reciente',
      () {
    for (final raw in ['OFFLINE', '', 'INVALID']) {
      expect(
          receivedStatus(
            laptopTime: tabletNow,
            receivedAt: tabletNow,
            status: raw,
          ).online,
          isFalse);
    }
  });

  test('SYNCING DONE y ERROR preservan conexion y respuesta con desfase', () {
    for (final raw in ['SYNCING', 'DONE', 'ERROR']) {
      final status = receivedStatus(
        laptopTime: tabletNow.add(const Duration(hours: 8)),
        receivedAt: tabletNow,
        status: raw,
      );
      expect(status.online, isTrue);
      expect(status.label, raw);
      expect(status.requestId, 'usb-test');
    }
  });

  test('timestamp malformado no se acepta aunque el archivo sea reciente', () {
    final status = UsbSyncStatus.fromValues(
      status: 'ONLINE',
      serial: null,
      detail: null,
      lastSeen: 'invalid',
      receivedAt: tabletNow,
      now: tabletNow,
    );
    expect(status.online, isFalse);
  });

  test('muestra online cuando el subidor USB marco la tablet recientemente',
      () {
    final now = DateTime(2026, 7, 6, 9, 30);
    final status = UsbSyncStatus.fromValues(
      status: 'ONLINE',
      serial: 'TABR70000000012091',
      detail: null,
      lastSeen: now.subtract(const Duration(seconds: 5)).toIso8601String(),
      now: now,
    );

    expect(status.online, isTrue);
    expect(status.label, 'ONLINE');
    expect(status.detail, contains('TABR70000000012091'));
  });

  test('muestra offline cuando el estado online esta vencido', () {
    final now = DateTime(2026, 7, 6, 9, 30);
    final status = UsbSyncStatus.fromValues(
      status: 'ONLINE',
      serial: 'TABR70000000012091',
      detail: 'Ultima deteccion vieja',
      lastSeen: now.subtract(const Duration(seconds: 40)).toIso8601String(),
      now: now,
    );

    expect(status.online, isFalse);
    expect(status.label, 'OFFLINE');
  });

  test('muestra offline cuando no hay datos del subidor USB', () {
    final status = UsbSyncStatus.fromValues(
      status: null,
      serial: null,
      detail: null,
      lastSeen: null,
      now: DateTime(2026, 7, 6, 9, 30),
    );

    expect(status.online, isFalse);
    expect(status.detail, 'Conecta la tablet a la laptop y presiona Detectar');
  });

  test('conserva el id de la solicitud confirmada por la laptop', () {
    final now = DateTime(2026, 7, 21, 14, 30);
    final status = UsbSyncStatus.fromValues(
      status: 'DONE',
      serial: 'TABR70000000012091',
      detail: 'Proceso terminado',
      lastSeen: now.toIso8601String(),
      requestId: '1784045048537',
      now: now,
    );

    expect(status.online, isTrue);
    expect(status.requestId, '1784045048537');
  });
}
