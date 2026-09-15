import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/lubrication_plan.dart';

void main() {
  test('equipos estandar usan motor y bomba', () {
    for (final puntos in const [1, 2, 3, 7, 8, 9]) {
      expect(
        LubricationPlanResolver.fromPuntos(
          puntos,
        ).map((step) => step.dbColumn).toList(),
        const ['L1', 'L2', 'L5', 'L6'],
      );
    }
  });

  test('caja multiplicadora agrega L3 y L4', () {
    expect(
      LubricationPlanResolver.fromPuntos(
        6,
      ).map((step) => step.dbColumn).toList(),
      const ['L1', 'L2', 'L3', 'L4', 'L5', 'L6'],
    );
  });

  test('finfan y ventilador usan sus puntos especificos', () {
    expect(
      LubricationPlanResolver.fromPuntos(
        4,
      ).map((step) => step.dbColumn).toList(),
      const ['L1', 'L2', 'L9'],
    );
    expect(
      LubricationPlanResolver.fromPuntos(
        5,
      ).map((step) => step.dbColumn).toList(),
      const ['L1', 'L2', 'L7', 'L8'],
    );
  });
}
