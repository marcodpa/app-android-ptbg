enum OperationType {
  vibration,
  temperature,
  lubrication,
  replacement,
  alignment,
  couplingChange,
  beltAdjustment,
  plateCleaning,
}

class CouplingChangeResolver {
  static bool isEligible(int puntos) =>
      const {1, 2, 3, 6, 9, 10}.contains(puntos);
}

/// Solo los ventiladores (5) y los fin-fan (4) llevan correa; el resto se
/// mueve por acople directo y ofrecerles el ajuste seria ruido.
class BeltAdjustmentResolver {
  static bool isEligible(int puntos) => const {4, 5}.contains(puntos);
}

enum ReplacementComponent { motor, pump, gearbox, fan }

class OperationFlow {
  OperationFlow({required List<OperationType> selected, required this.current})
      : pending = List<OperationType>.of(selected)..remove(current);

  final OperationType current;
  final List<OperationType> pending;

  OperationType? get next => pending.isEmpty ? null : pending.first;
}

class ReplacementComponentResolver {
  static List<ReplacementComponent> fromPuntos(int puntos) {
    if (puntos == 10) return const [ReplacementComponent.motor];
    if (const {1, 2, 3, 7, 8, 9}.contains(puntos)) {
      return const [ReplacementComponent.motor, ReplacementComponent.pump];
    }
    if (const {4, 5}.contains(puntos)) {
      return const [ReplacementComponent.motor, ReplacementComponent.fan];
    }
    if (puntos == 6) {
      return const [
        ReplacementComponent.motor,
        ReplacementComponent.gearbox,
        ReplacementComponent.pump,
      ];
    }
    return const [];
  }
}
