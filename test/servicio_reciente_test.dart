import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/servicio_reciente.dart';

void main() {
  group('tipo de servicio', () {
    test('cada codigo es unico', () {
      // Dos tipos con el mismo codigo harian que la consulta de recientes
      // devolviera uno y se mostrara el otro.
      final codigos = TipoServicio.values.map((t) => t.codigo).toSet();
      expect(codigos.length, TipoServicio.values.length);
    });

    test('resuelve por codigo y aguanta lo desconocido', () {
      expect(TipoServicio.porCodigo('vibracion'), TipoServicio.vibracion);
      expect(TipoServicio.porCodigo('black_start'), TipoServicio.blackStart);
      expect(TipoServicio.porCodigo('inventado'), isNull);
      expect(TipoServicio.porCodigo(null), isNull);
    });
  });

  group('fila de la base', () {
    test('arma el servicio con lo que devuelve la consulta', () {
      final servicio = ServicioReciente.deFila({
        'servicio': 'temperatura',
        'localizacion': 48,
        'fecha': '2026-08-25',
        'hora': '09:04:17',
      });
      expect(servicio, isNotNull);
      expect(servicio!.tipo, TipoServicio.temperatura);
      expect(servicio.localizacion, 48);
    });

    test('el black start viene sin localizacion', () {
      final servicio = ServicioReciente.deFila({
        'servicio': 'black_start',
        'localizacion': null,
        'fecha': '2026-08-25',
        'hora': '09:04:17',
      });
      expect(servicio?.localizacion, isNull);
    });

    test('una fila de un servicio que no conoce se descarta', () {
      // Si mañana se agrega una tabla a la consulta y se olvida el tipo, la
      // fila se ignora en vez de tumbar el inicio.
      expect(
        ServicioReciente.deFila({'servicio': 'algo_nuevo', 'fecha': 'x'}),
        isNull,
      );
    });
  });

  group('como se lee la fecha', () {
    ServicioReciente con(String fecha, String hora) => ServicioReciente(
          tipo: TipoServicio.vibracion,
          localizacion: 1,
          fecha: fecha,
          hora: hora,
        );

    test('pasa de ISO a dia/mes/año y corta los segundos', () {
      // En la base va ISO para que ordene bien como texto; en pantalla se lee
      // como se lee aqui, y los segundos no le importan a nadie.
      expect(con('2026-08-25', '09:04:17').cuando, '25/08/2026 · 09:04');
    });

    test('sin hora muestra solo la fecha', () {
      expect(con('2026-08-25', '').cuando, '25/08/2026');
    });

    test('una fecha con otro formato se muestra tal cual', () {
      // Mas vale enseñarla cruda que inventar un dia y un mes al voltearla.
      expect(con('25/08/2026', '09:04').cuando, '25/08/2026 · 09:04');
    });
  });
}
