import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/replacement_request.dart';

void main() {
  test('agrupa componentes de un mismo reemplazo como un trabajo local', () {
    final operations = ReplacementLocalOperation.fromRows([
      {
        'uuid': 'r-1',
        'operation_uuid': 'op-1',
        'localizacion': 13,
        'code_conjunto': 2,
        'equipo': 1,
        'marca': 'WEG',
        'modelo': 'W22',
        'serial': 'M-1',
        'fecha': '2026-07-21',
        'hora': '13:00:00',
        'sincronizado': 0,
      },
      {
        'uuid': 'r-2',
        'operation_uuid': 'op-1',
        'localizacion': 13,
        'code_conjunto': 2,
        'equipo': 3,
        'marca': 'SEW',
        'modelo': 'R97',
        'serial': 'C-1',
        'fecha': '2026-07-21',
        'hora': '13:00:00',
        'sincronizado': 0,
        'error_sync': 'sin red',
      },
    ]);

    expect(operations, hasLength(1));
    expect(operations.single.components, hasLength(2));
    expect(operations.single.localizacion, 13);
    expect(operations.single.hasError, isTrue);
    expect(operations.single.componentLabels, ['Motor', 'Caja']);
  });
}
