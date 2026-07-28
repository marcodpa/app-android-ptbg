import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/usb_sync_status.dart';

void main() {
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
