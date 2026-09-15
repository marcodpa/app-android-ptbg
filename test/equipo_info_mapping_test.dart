import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';

void main() {
  test('mapea detalles tecnicos desde MOT_DATA', () {
    final info = EquipoInfo.fromJson({
      'UBICACION': 20,
      'MARCA': 'WEG',
      'MODELO': 'M-123',
      'SERIAL': 'S-456',
      'HP': '50',
      'VOLTAJE': '480',
      'CORRIENTE': '62',
      'SF': '1.15',
      'CICLO': '60',
      'RPM': '1780',
      'ARRANQUE': 'DIRECTO',
      'BRGS_DRIVE': '6312',
      'BRGS_OPP': '6310',
      'LUBRICACION': 'GRASA EP2',
      'MOTORES_LUB': 'MOTOR PRINCIPAL',
      'CANT_MOT_LUB': '12,5 gramos',
      'ELEC_MOT_LUB': 6,
      'MAN_MOT_LUB': 5,
      'ELEMENTO_LUB': 'BOMBA',
      'CANT_ELEM_LUB': 20,
      'ELEC_ELEM_LUB': 10,
      'MAN_ELEM_LUB': 8.33,
    });

    expect(info.localizacion, 20);
    expect(info.marca, 'WEG');
    expect(info.modelo, 'M-123');
    expect(info.serial, 'S-456');
    expect(info.hp, '50');
    expect(info.volts, '480');
    expect(info.fla, '62');
    expect(info.sf, '1.15');
    expect(info.hz, '60');
    expect(info.rpm, '1780');
    expect(info.start, 'DIRECTO');
    expect(info.brgsDrive, '6312');
    expect(info.brgsOpp, '6310');
    expect(info.lubricacion, 'GRASA EP2');
    expect(info.motoresLub, 'MOTOR PRINCIPAL');
    expect(info.cantMotLub, 12.5);
    expect(info.elecMotLub, 6);
    expect(info.manMotLub, 5);
    expect(info.elementoLub, 'BOMBA');
    expect(info.cantElemLub, 20);
    expect(info.elecElemLub, 10);
    expect(info.manElemLub, 8.33);
  });

  test('mapea aliases enviados por /equipos', () {
    final info = EquipoInfo.fromJson({
      'LOCALIZACION': 21,
      'MARCA_INFO': 'SIEMENS',
      'MODELO_INFO': '1LE',
      'SERIAL_INFO': 'SER-1',
      'HP_INFO': '75',
      'VOLTAJE_INFO': '4160',
      'CORRIENTE_INFO': '11',
      'SF_INFO': '1.0',
      'CICLO_INFO': '60',
      'RPM_INFO': '3600',
      'ARRANQUE_INFO': 'VFD',
    });

    expect(info.localizacion, 21);
    expect(info.marca, 'SIEMENS');
    expect(info.modelo, '1LE');
    expect(info.serial, 'SER-1');
    expect(info.volts, '4160');
    expect(info.fla, '11');
    expect(info.hz, '60');
    expect(info.start, 'VFD');
  });
}
