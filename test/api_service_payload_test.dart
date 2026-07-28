import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/temperature_measurement.dart';
import 'package:scv_ptbg/services/api_service.dart';

void main() {
  test('payload de sincronizacion usa campos esperados por el API', () {
    const medicion = MedicionLocal(
      uuid: 'abc-123',
      localizacion: 6,
      sistema: 'TURBINA BG-1',
      fecha: '2026-06-29',
      hora: '11:10:00',
      valores: {'H1': 1.2, 'V1': 2.3},
      rms: 1.75,
      observaciones: 'ruido general',
    );

    final payload = buildMedicionSyncPayload(medicion);

    expect(payload['RMS'], 1.75);
    expect(payload['OBSERVACIONES'], 'ruido general');
    expect(payload, isNot(contains('rms')));
    expect(payload, isNot(contains('observaciones')));
  });

  test('payload de temperatura usa columnas mayusculas T1 a T10', () {
    const measurement = TemperatureMeasurement(
      uuid: 'temp-123',
      localizacion: 4,
      sistema: 'FIN-FAN',
      fecha: '2026-07-22',
      hora: '10:30:00',
      valores: {'T1': 41.5, 'T10': 55.25},
      observaciones: 'Correa estable',
      responsable: 'OPERADOR',
      cargo: 'MECANICO',
      marca: 'WEG',
      modelo: 'W22',
      serial: 'ABC-1',
      odt: 701,
    );

    final payload = buildTemperatureSyncPayload(measurement);

    expect(payload['uuid'], 'temp-123');
    expect(payload['localizacion'], 4);
    expect(payload['sistema'], 'FIN-FAN');
    expect(payload['fecha'], '2026-07-22');
    expect(payload['hora'], '10:30:00');
    expect(payload['T1'], 41.5);
    expect(payload['T10'], 55.25);
    expect(payload['T2'], 0.0);
    expect(payload['OBSERVACIONES'], 'Correa estable');
    expect(payload['USUARIO'], 'OPERADOR');
    expect(payload['CARGO'], 'MECANICO');
    expect(payload['MARCA'], 'WEG');
    expect(payload['MODELO'], 'W22');
    expect(payload['SERIAL'], 'ABC-1');
    expect(payload['ODT'], 701);
    expect(payload, isNot(contains('observaciones')));
    expect(payload, isNot(contains('odt')));
  });

  test('payload de temperatura conserva ODT nulo', () {
    const measurement = TemperatureMeasurement(
      uuid: 'temp-null-odt',
      localizacion: 2,
      sistema: 'BOMBAS',
      fecha: '2026-07-22',
      hora: '11:00:00',
      valores: {'T1': 38},
    );

    final payload = buildTemperatureSyncPayload(measurement);

    expect(payload, containsPair('ODT', null));
    for (var i = 2; i <= 10; i++) {
      expect(payload['T$i'], 0.0);
    }
  });
}
