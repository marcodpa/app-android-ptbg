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
