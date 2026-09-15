import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/ajuste_correa.dart';
import 'package:scv_ptbg/models/operation_flow.dart';

/// El ajuste de correa (MOT_AJC_REG).
///
/// Solo lo llevan los ventiladores y los fin-fan; el resto de la planta se
/// mueve por acople directo.
void main() {
  group('a que equipos aplica', () {
    test('solo fin-fan (4) y ventilador (5)', () {
      expect(BeltAdjustmentResolver.isEligible(4), isTrue);
      expect(BeltAdjustmentResolver.isEligible(5), isTrue);
      for (final tipo in [1, 2, 3, 6, 7, 8, 9]) {
        expect(BeltAdjustmentResolver.isEligible(tipo), isFalse,
            reason: 'el tipo $tipo no lleva correa');
      }
    });

    test('el modelo y el resolver dicen lo mismo', () {
      // Dos listas separadas se desincronizan sola: esta prueba las ata.
      for (final tipo in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
        expect(AjusteCorrea.aplicaA(tipo),
            BeltAdjustmentResolver.isEligible(tipo));
      }
    });
  });

  group('ida y vuelta con la base', () {
    test('lo que sale por toDbMap vuelve igual por fromMap', () {
      const original = AjusteCorrea(
        uuid: 'correa-1',
        localizacion: 15,
        sistema: 'TURBINA BG-1',
        fecha: '2026-09-02',
        hora: '08:30:00',
        ajustada: true,
        tension: 42.5,
        observaciones: 'CORREA FLOJA, SE TENSIONO',
        responsable: 'ALEXI AVILA',
        cargo: 'SUP.MECANICO',
        marca: 'WEG',
        modelo: 'QX-11',
        serial: 'C0049856',
        odt: 4521,
      );
      final vuelta = AjusteCorrea.fromMap(original.toDbMap());
      expect(vuelta.uuid, original.uuid);
      expect(vuelta.localizacion, original.localizacion);
      expect(vuelta.fecha, original.fecha);
      expect(vuelta.hora, original.hora);
      expect(vuelta.ajustada, isTrue);
      expect(vuelta.tension, 42.5);
      expect(vuelta.observaciones, original.observaciones);
      expect(vuelta.responsable, original.responsable);
      expect(vuelta.odt, 4521);
    });

    test('un NO sin tension es un registro valido', () {
      // Deja constancia de que se reviso la correa y no hizo falta tocarla.
      const original = AjusteCorrea(
        uuid: 'correa-2',
        localizacion: 17,
        sistema: 'TURBINA BG-2',
        fecha: '2026-09-02',
        hora: '09:00:00',
      );
      final vuelta = AjusteCorrea.fromMap(original.toDbMap());
      expect(vuelta.ajustada, isFalse);
      expect(vuelta.tension, isNull);
      expect(vuelta.odt, isNull);
    });

    test('lee las claves en mayusculas, como manda MariaDB', () {
      final ajuste = AjusteCorrea.fromMap(const {
        'uuid': 'x',
        'LOCALIZACION': 15,
        'SISTEMA': 'TURBINA BG-1',
        'FECHA': '2026-09-02',
        'HORA': '08:30:00',
        'TENSION': 42.5,
        'USUARIO': 'PEDRO',
        'CARGO': 'MECANICO',
      });
      expect(ajuste.localizacion, 15);
      expect(ajuste.responsable, 'PEDRO');
      expect(ajuste.tension, 42.5);
    });

    test('la tension con coma del teclado se entiende', () {
      final ajuste = AjusteCorrea.fromMap(const {
        'uuid': 'x',
        'localizacion': 15,
        'sistema': 'S',
        'fecha': '2026-09-02',
        'hora': '08:30:00',
        'tension': '42,5',
      });
      expect(ajuste.tension, 42.5);
    });
  });
}
