import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/measurement_editing.dart';

void main() {
  group('observacion general', () {
    test('guarda solo el texto general limpio', () {
      expect(cleanGeneralObservation('  ruido general en bomba  '),
          'ruido general en bomba');
      expect(cleanGeneralObservation('   '), isNull);
    });
  });

  group('edicion de mediciones pendientes', () {
    test('recalcula RMS usando valores editados', () {
      final values = editedMeasurementValues(
        current: const {'H1': 3, 'V1': 4},
        edits: const {'H1': '6,00', 'V1': '8.00'},
      );

      expect(values['H1'], 6);
      expect(values['V1'], 8);
      expect(calculateRms(values), 7.07);
    });

    test('rechaza valores editados invalidos', () {
      expect(
        () => editedMeasurementValues(
          current: const {'H1': 3},
          edits: const {'H1': 'abc'},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
