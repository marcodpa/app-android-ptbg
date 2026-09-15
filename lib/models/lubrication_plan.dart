class LubricationStep {
  const LubricationStep({
    required this.dbPointNumber,
    required this.label,
    required this.motor,
  });

  final int dbPointNumber;
  final String label;
  final bool motor;

  String get dbColumn => 'L$dbPointNumber';
}

class LubricationPlanResolver {
  static List<LubricationStep> fromPuntos(int puntos) {
    if (puntos == 10) {
      return const [
        LubricationStep(
            dbPointNumber: 1, label: 'Motor - lado libre', motor: true),
        LubricationStep(
            dbPointNumber: 2, label: 'Motor - lado acople', motor: true),
      ];
    }
    if ({1, 2, 3, 7, 8, 9}.contains(puntos)) {
      return const [
        LubricationStep(
          dbPointNumber: 1,
          label: 'Motor - lado libre',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 2,
          label: 'Motor - lado acople',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 5,
          label: 'Bomba - lado libre',
          motor: false,
        ),
        LubricationStep(
          dbPointNumber: 6,
          label: 'Bomba - lado acople',
          motor: false,
        ),
      ];
    }
    if (puntos == 6) {
      return const [
        LubricationStep(
          dbPointNumber: 1,
          label: 'Motor - lado libre',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 2,
          label: 'Motor - lado acople',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 3,
          label: 'Caja - lado baja (caja-motor)',
          motor: false,
        ),
        LubricationStep(
          dbPointNumber: 4,
          label: 'Caja - lado alta (caja-bomba)',
          motor: false,
        ),
        LubricationStep(
          dbPointNumber: 5,
          label: 'Bomba - lado libre',
          motor: false,
        ),
        LubricationStep(
          dbPointNumber: 6,
          label: 'Bomba - lado acople',
          motor: false,
        ),
      ];
    }
    if (puntos == 4) {
      return const [
        LubricationStep(
          dbPointNumber: 1,
          label: 'Motor - lado libre',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 2,
          label: 'Motor - lado acople',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 9,
          label: 'Ventilador FIN-FAN - lado libre',
          motor: false,
        ),
      ];
    }
    if (puntos == 5) {
      return const [
        LubricationStep(
          dbPointNumber: 1,
          label: 'Motor - lado libre',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 2,
          label: 'Motor - lado acople',
          motor: true,
        ),
        LubricationStep(
          dbPointNumber: 7,
          label: 'Ventilador - punto 1',
          motor: false,
        ),
        LubricationStep(
          dbPointNumber: 8,
          label: 'Ventilador - punto 2',
          motor: false,
        ),
      ];
    }
    return const [];
  }
}
