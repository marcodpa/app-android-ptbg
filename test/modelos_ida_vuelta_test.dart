import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/lubrication_measurement.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/temperature_measurement.dart';

/// Ida y vuelta de los cuatro modelos de medicion: lo que sale por toDbMap
/// tiene que volver identico por fromMap.
///
/// Estos cuatro modelos comparten catorce campos copiados a mano, y el
/// serializado es lo que se guarda en SQLite y se sube a MariaDB. Estas
/// pruebas fijan el contrato actual para que cualquier unificacion futura
/// de los modelos no cambie ni un campo en silencio.
void main() {
  group('ida y vuelta toDbMap → fromMap', () {
    test('temperatura', () {
      const original = TemperatureMeasurement(
        uuid: 'uuid-t1',
        localizacion: 48,
        sistema: 'AGUA POTABLE',
        fecha: '2026-08-26',
        hora: '08:26:18',
        valores: {'T1': 61.0, 'T2': 88.0, 'T5': 63.5, 'T6': 64.0},
        observaciones: 'prueba de contrato',
        responsable: 'ALEXI AVILA',
        cargo: 'SUP.MECANICO',
        marca: 'MARATHON',
        modelo: 'QX-11',
        serial: 'C0049856',
        odt: 4521,
        sincronizado: false,
      );
      final vuelta = TemperatureMeasurement.fromMap(original.toDbMap());
      expect(vuelta.uuid, original.uuid);
      expect(vuelta.localizacion, original.localizacion);
      expect(vuelta.sistema, original.sistema);
      expect(vuelta.fecha, original.fecha);
      expect(vuelta.hora, original.hora);
      expect(vuelta.valores, original.valores);
      expect(vuelta.observaciones, original.observaciones);
      expect(vuelta.responsable, original.responsable);
      expect(vuelta.cargo, original.cargo);
      expect(vuelta.marca, original.marca);
      expect(vuelta.modelo, original.modelo);
      expect(vuelta.serial, original.serial);
      expect(vuelta.odt, original.odt);
      expect(vuelta.sincronizado, original.sincronizado);
    });

    test('lubricacion', () {
      const original = LubricationMeasurement(
        uuid: 'uuid-l1',
        localizacion: 2,
        sistema: 'TURBINA BG-1',
        fecha: '2026-08-26',
        hora: '09:00:00',
        valores: {'L1': 12.5, 'L2': 8.0},
        observaciones: null,
        responsable: 'ALEXI AVILA',
        cargo: null,
        odt: null,
        sincronizado: true,
      );
      final vuelta = LubricationMeasurement.fromMap(original.toDbMap());
      expect(vuelta.uuid, original.uuid);
      expect(vuelta.valores, original.valores);
      // Lo vacio vuelve vacio, no convertido en texto 'null'.
      expect(vuelta.odt, isNull);
      expect(vuelta.sincronizado, isTrue);
    });

    test('alineacion', () {
      final valores = <String, double?>{
        for (final columna in alignmentValueColumns) columna: 1.25,
      };
      final original = AlignmentMeasurement(
        uuid: 'uuid-a1',
        localizacion: 5,
        sistema: 'TURBINA BG-1',
        puntos: 4,
        fecha: '2026-08-26',
        hora: '10:00:00',
        valores: valores,
        observaciones: 'alineado en frio',
        responsable: 'ALEXI AVILA',
        cargo: 'SUP.MECANICO',
        odt: 77,
        sincronizado: false,
      );
      final vuelta = AlignmentMeasurement.fromMap(original.toDbMap());
      expect(vuelta.uuid, original.uuid);
      expect(vuelta.valores, original.valores);
      expect(vuelta.puntos, original.puntos);
      expect(vuelta.odt, original.odt);
    });

    test('vibracion (MedicionLocal) lee la fila de SQLite', () {
      // MedicionLocal no tiene toDbMap: su escritura vive inline en
      // DbHelper.insertMedicion. El contrato que se fija aqui es la lectura
      // de una fila con la forma exacta que esa insercion produce.
      final vuelta = MedicionLocal.fromMap(const {
        'uuid': 'uuid-v1',
        'localizacion': 48,
        'sistema': 'AGUA POTABLE',
        'fecha': '2026-08-26',
        'hora': '08:13:04',
        'H1': 7.77, 'V1': 5.02, 'A1': 5.03,
        'H2': 5.04, 'V2': 5.05, 'A2': 5.06,
        'H5': 5.07, 'V5': 5.08, 'A5': 5.09,
        'H6': 5.10, 'V6': 5.11, 'A6': 5.12,
        'rms': 5.21,
        'observaciones': 'prueba de editor',
        'responsable': 'ALEXI AVILA',
        'cargo': 'SUP.MECANICO',
        'odt': 4521,
        'sincronizado': 0,
      });
      expect(vuelta.uuid, 'uuid-v1');
      expect(vuelta.valores['H1'], 7.77);
      expect(vuelta.valores['A6'], 5.12);
      expect(vuelta.valores.length, 12);
      expect(vuelta.rms, 5.21);
      expect(vuelta.responsable, 'ALEXI AVILA');
      expect(vuelta.odt, 4521);
      expect(vuelta.sincronizado, isFalse);
    });
  });

  group('lectura tolerante desde el servidor', () {
    test('acepta claves en mayusculas como manda MariaDB', () {
      final medida = TemperatureMeasurement.fromMap(const {
        'uuid': 'x',
        'LOCALIZACION': 7,
        'SISTEMA': 'FUEL OIL',
        'FECHA': '2026-08-26',
        'HORA': '11:00:00',
        'T1': 40.0,
        'OBSERVACIONES': 'desde la planta',
        'USUARIO': 'PEDRO',
        'CARGO': 'MECANICO',
      });
      expect(medida.localizacion, 7);
      expect(medida.sistema, 'FUEL OIL');
      expect(medida.responsable, 'PEDRO');
      expect(medida.valores['T1'], 40.0);
    });

    test('los decimales aceptan coma', () {
      // El helper de coercion compartido admite la coma del teclado de la
      // tablet; una fila vieja con "4,5" no debe perder la lectura.
      final medida = LubricationMeasurement.fromMap(const {
        'uuid': 'x',
        'localizacion': 1,
        'sistema': 'S',
        'fecha': '2026-08-26',
        'hora': '11:00:00',
        'L1': '4,5',
      });
      expect(medida.valores['L1'], 4.5);
    });
  });
}
