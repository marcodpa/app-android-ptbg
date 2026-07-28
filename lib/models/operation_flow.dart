enum OperationType { vibration, temperature, replacement, alignment }

enum ReplacementComponent { motor, pump, gearbox, fan }

class OperationFlow {
  OperationFlow({
    required List<OperationType> selected,
    required this.current,
  }) : pending = List<OperationType>.of(selected)..remove(current);

  final OperationType current;
  final List<OperationType> pending;

  OperationType? get next => pending.isEmpty ? null : pending.first;
}

class ReplacementComponentResolver {
  static List<ReplacementComponent> fromPuntos(int puntos) {
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
