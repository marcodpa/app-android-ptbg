import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/orden_reparacion.dart';

OrdenReparacion _orden({
  String estadoOrden = 'ABIERTA',
  bool sincronizado = false,
  String? resultado,
}) =>
    OrdenReparacion(
      uuid: 'uuid-1',
      tipo: 1,
      serial: 'M-123',
      destino: 'TALLER ELECTRICO',
      fechaSalida: '2026-08-01',
      horaSalida: '08:00:00',
      estadoOrden: estadoOrden,
      resultado: resultado,
      sincronizado: sincronizado,
    );

void main() {
  group('una orden sin sincronizar no se puede finalizar', () {
    test('recien creada, todavia en la tablet', () {
      final orden = _orden(sincronizado: false);
      expect(orden.abierta, isTrue);
      // Si se pudiera cerrar aqui, apertura y cierre subirian juntos y el
      // servidor recibiria una orden que nacio cerrada.
      expect(orden.puedeFinalizarse, isFalse);
    });

    test('una vez enviada si se puede finalizar', () {
      expect(_orden(sincronizado: true).puedeFinalizarse, isTrue);
    });

    test('una orden ya cerrada no se vuelve a finalizar', () {
      final cerrada = _orden(
        estadoOrden: 'CERRADA',
        sincronizado: true,
        resultado: 'REPARADO',
      );
      expect(cerrada.puedeFinalizarse, isFalse);
    });
  });

  group('descartar solo lo que nunca salio de la tablet', () {
    test('abierta y sin enviar se puede descartar', () {
      expect(_orden(sincronizado: false).puedeDescartarse, isTrue);
    });

    test('ya enviada no se descarta: el registro vive en el servidor', () {
      expect(_orden(sincronizado: true).puedeDescartarse, isFalse);
    });

    test('un cierre pendiente de subir tampoco se descarta', () {
      // sincronizado = 0 porque falta subir el cierre, pero la apertura ya
      // esta en MariaDB: borrarla dejaria la pieza congelada EN REPARACION.
      final cierrePendiente = _orden(
        estadoOrden: 'CERRADA',
        sincronizado: false,
        resultado: 'REPARADO',
      );
      expect(cierrePendiente.puedeDescartarse, isFalse);
    });
  });

  test('cerrar deja la orden pendiente de subir otra vez', () {
    final abierta = _orden(sincronizado: true);
    final cerrada = abierta.cerrar(
      fecha: '2026-08-10',
      hora: '15:30:00',
      resultado: 'REPARADO',
      trabajoRealizado: 'Cambio de rodamientos',
    );
    expect(cerrada.abierta, isFalse);
    expect(cerrada.sincronizado, isFalse);
    expect(cerrada.estadoPieza, 'DISPONIBLE');
    expect(cerrada.puedeFinalizarse, isFalse);
    expect(cerrada.puedeDescartarse, isFalse);
  });
}
