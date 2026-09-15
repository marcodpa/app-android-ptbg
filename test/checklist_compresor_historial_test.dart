import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/checklist_compresor.dart';

ChecklistCompresor registro(String uuid, String fecha,
        {int loc = 53, Map<String, Object?> datos = const {}}) =>
    ChecklistCompresor.fromMap({
      'uuid': uuid,
      'fecha': fecha,
      'hora': '08:00',
      'localizacion': loc,
      ...datos,
    });

void main() {
  test('cada tarea conserva su ultimo mantenimiento aunque haya varios NO', () {
    final original = registro('a', '01/06/2026', datos: {
      'mtto_lub_uf': '01/06/2026',
      'mtto_lub_uh': '3000',
      'mtto_lub_obs': 'Grasa aplicada',
      'mtto_air_uf': '01/06/2026',
      'mtto_air_uh': '3000',
    });
    final filtro = registro('b', '2026-08-20', datos: {
      'mtto_air_uf': '20/08/2026',
      'mtto_air_uh': '4000',
      'mtto_air_obs': 'Filtro cambiado',
    });
    final sinMantenimiento = registro('c', '2026-09-07');
    final resultado = historialCompresorConReferencias([
      filtro,
      sinMantenimiento,
      original,
      registro('d', '2026-09-08'),
    ]);
    final ultimo = resultado.first.mantenimientos;
    expect(ultimo[0].ultimaFecha, '01/06/2026');
    expect(ultimo[0].horas, '3000');
    expect(ultimo[0].observacion, 'Grasa aplicada');
    expect(ultimo[2].ultimaFecha, '20/08/2026');
    expect(ultimo[2].observacion, 'Filtro cambiado');
    expect(ultimo[1].tieneRegistro, isFalse);
    expect(sinMantenimiento.mantenimientos[0].tieneRegistro, isFalse);
    expect(sinMantenimiento.toDbMap()['mtto_lub_uf'], isEmpty);
  });

  test('una planilla antigua no usa el futuro ni otro compresor', () {
    final res = historialCompresorConReferencias([
      registro('hoy', '2026-08-01'),
      registro('futuro', '2026-09-01', datos: {'mtto_lub_uf': '01/09/2026'}),
      registro('otro', '2026-07-01',
          loc: 54, datos: {'mtto_lub_uf': '01/07/2026'}),
    ]);
    expect(
        res.firstWhere((r) => r.uuid == 'hoy').mantenimientos[0].tieneRegistro,
        isFalse);
  });

  test('una tarea nueva no se mezcla con horas u observaciones viejas', () {
    final res = historialCompresorConReferencias([
      registro('a', '2026-07-01', datos: {
        'mtto_lub_uf': '01/07/2026',
        'mtto_lub_uh': '3000',
        'mtto_lub_obs': 'Viejo',
      }),
      registro('b', '2026-08-01', datos: {'mtto_lub_uf': '01/08/2026'}),
    ]);
    expect(res.first.mantenimientos[0].horas, isEmpty);
    expect(res.first.mantenimientos[0].observacion, isEmpty);
  });

  test('NO no registra lo anterior ni los campos escritos antes de volver a NO',
      () {
    const tarea = MantenimientoCompresor(
        ultimaFecha: '07/09/2026', horas: '4500', observacion: 'Hecho');
    final guardados = mantenimientosRealizados(
        [false, true, false, false], List.filled(4, tarea));
    expect(guardados[0].tieneRegistro, isFalse);
    expect(guardados[0].observacion, isEmpty);
    expect(guardados[1].ultimaFecha, tarea.ultimaFecha);
    expect(guardados[1].observacion, tarea.observacion);
  });

  test('espacios no reemplazan el ultimo registro y horas cero son validas',
      () {
    final res = historialCompresorConReferencias([
      registro('a', '2026-07-01', datos: {'mtto_lub_uh': '0'}),
      registro('b', '2026-08-01',
          datos: {'mtto_lub_uf': ' ', 'mtto_lub_uh': ' '}),
    ]);
    expect(res.first.mantenimientos[0].horas, '0');
  });
}
