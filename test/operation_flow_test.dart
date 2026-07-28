import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/operation_flow.dart';

void main() {
  group('OperationFlow', () {
    test('respeta la operacion elegida para comenzar', () {
      final flow = OperationFlow(
        selected: const [
          OperationType.vibration,
          OperationType.replacement,
        ],
        current: OperationType.replacement,
      );

      expect(flow.current, OperationType.replacement);
      expect(flow.pending, const [OperationType.vibration]);
      expect(flow.next, OperationType.vibration);
    });

    test('no deja operaciones pendientes cuando solo se selecciona una', () {
      final flow = OperationFlow(
        selected: const [OperationType.vibration],
        current: OperationType.vibration,
      );

      expect(flow.pending, isEmpty);
      expect(flow.next, isNull);
    });

    test('conserva el orden de cuatro operaciones desde la elegida', () {
      final flow = OperationFlow(
        selected: const [
          OperationType.vibration,
          OperationType.temperature,
          OperationType.replacement,
          OperationType.alignment,
        ],
        current: OperationType.temperature,
      );

      expect(
        flow.pending,
        const [
          OperationType.vibration,
          OperationType.replacement,
          OperationType.alignment,
        ],
      );
    });
  });

  group('ReplacementComponentResolver', () {
    test('resuelve motor y bomba para los tipos correspondientes', () {
      for (final puntos in const [1, 2, 3, 7, 8, 9]) {
        expect(
          ReplacementComponentResolver.fromPuntos(puntos),
          const [ReplacementComponent.motor, ReplacementComponent.pump],
        );
      }
    });

    test('resuelve motor y ventilador para tipos 4 y 5', () {
      for (final puntos in const [4, 5]) {
        expect(
          ReplacementComponentResolver.fromPuntos(puntos),
          const [ReplacementComponent.motor, ReplacementComponent.fan],
        );
      }
    });

    test('resuelve motor caja y bomba para tipo 6', () {
      expect(
        ReplacementComponentResolver.fromPuntos(6),
        const [
          ReplacementComponent.motor,
          ReplacementComponent.gearbox,
          ReplacementComponent.pump,
        ],
      );
    });

    test('no inventa componentes para un tipo desconocido', () {
      expect(ReplacementComponentResolver.fromPuntos(0), isEmpty);
      expect(ReplacementComponentResolver.fromPuntos(10), isEmpty);
    });
  });
}
