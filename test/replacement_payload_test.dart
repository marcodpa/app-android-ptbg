import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/replacement_request.dart';

void main() {
  test('construye el contrato de reemplazo con ubicacion y sistema', () {
    const equipo = Equipo(
      id: 2,
      codeSys: 7,
      equipo: 'NOX-LIQUIDO',
      localizacion: 11,
      puntos: 6,
      ptEq: 6,
      sistema: 'TURBINA BG-1',
    );

    const request = ReplacementRequest(
      equipo: equipo,
      components: {
        ReplacementComponent.motor: ReplacementData(
          brand: 'WEG',
          model: 'W22',
          serial: 'M-001',
          updateTechnicalSpecs: true,
          voltage: '440',
          current: '18.5',
          rpm: '1780',
          serviceFactor: '1.15',
          horsepower: '15',
          frame: '254T',
          driveBearing: '6309',
          oppositeBearing: '6208',
          cycle: '60',
          start: 'DIRECTO',
          phases: '3',
          tension: '12',
          lubrication: 'GRASA',
        ),
        ReplacementComponent.gearbox: ReplacementData(
          brand: 'SEW',
          model: 'R97',
          serial: 'C-002',
        ),
      },
    );

    final payload = request.toJson();
    final components = payload['componentes'] as List<Map<String, dynamic>>;

    expect(payload['localizacion'], 11);
    expect(payload['code_conjunto'], 7);
    expect(components[0]['equipo'], 1);
    expect(components[0]['actualizar_especificaciones'], 1);
    expect(components[0]['voltaje'], '440');
    expect(components[0]['corriente'], '18.5');
    expect(components[0]['brgs_drive'], '6309');
    expect(components[0]['lubricacion'], 'GRASA');
    expect(components[1]['equipo'], 3);
    expect(components[1]['serial'], 'C-002');
  });
}
