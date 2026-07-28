import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/replacement_visual_layout.dart';

void main() {
  const expectedComponents = <int, Set<ReplacementComponent>>{
    1: {ReplacementComponent.motor, ReplacementComponent.pump},
    2: {ReplacementComponent.motor, ReplacementComponent.pump},
    3: {ReplacementComponent.motor, ReplacementComponent.pump},
    4: {ReplacementComponent.motor, ReplacementComponent.fan},
    5: {ReplacementComponent.motor, ReplacementComponent.fan},
    6: {
      ReplacementComponent.motor,
      ReplacementComponent.gearbox,
      ReplacementComponent.pump,
    },
    7: {ReplacementComponent.motor, ReplacementComponent.pump},
    8: {ReplacementComponent.motor, ReplacementComponent.pump},
    9: {ReplacementComponent.motor, ReplacementComponent.pump},
  };

  test('todos los tipos conocidos tienen layout y regiones validas', () {
    for (final entry in expectedComponents.entries) {
      final layout = ReplacementVisualResolver.fromPuntos(entry.key);

      expect(layout, isNotNull, reason: 'Falta PUNTOS ${entry.key}');
      expect(layout!.asset, startsWith('assets/images/visual_'));
      expect(layout.aspectRatio, greaterThan(0));
      expect(layout.components, entry.value);

      for (final regions in layout.regions.values) {
        expect(regions, isNotEmpty);
        for (final rect in regions) {
          expect(rect.left, inInclusiveRange(0, 1));
          expect(rect.top, inInclusiveRange(0, 1));
          expect(rect.right, inInclusiveRange(0, 1));
          expect(rect.bottom, inInclusiveRange(0, 1));
          expect(rect.width, greaterThan(0));
          expect(rect.height, greaterThan(0));
        }
      }
    }
  });

  test('PUNTOS 6 separa motor caja y bomba de izquierda a derecha', () {
    final layout = ReplacementVisualResolver.fromPuntos(6)!;
    final motor = layout.regions[ReplacementComponent.motor]!.first;
    final gearbox = layout.regions[ReplacementComponent.gearbox]!.first;
    final pump = layout.regions[ReplacementComponent.pump]!.first;

    expect(motor.center.dx, lessThan(gearbox.center.dx));
    expect(gearbox.center.dx, lessThan(pump.center.dx));
  });

  test('une las regiones de todos los componentes seleccionados', () {
    final layout = ReplacementVisualResolver.fromPuntos(5)!;
    final motorCount = layout.regions[ReplacementComponent.motor]!.length;
    final fanCount = layout.regions[ReplacementComponent.fan]!.length;

    final union = layout.regionsFor({
      ReplacementComponent.motor,
      ReplacementComponent.fan,
    });

    expect(union.length, motorCount + fanCount);
  });

  test('un tipo desconocido no inventa un layout', () {
    expect(ReplacementVisualResolver.fromPuntos(0), isNull);
    expect(ReplacementVisualResolver.fromPuntos(10), isNull);
  });
}
