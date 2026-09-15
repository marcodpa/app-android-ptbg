class AlignmentField {
  const AlignmentField({
    required this.column,
    required this.label,
    required this.unit,
  });

  final String column;
  final String label;
  final String unit;
}

class AlignmentSection {
  const AlignmentSection({required this.title, required this.fields});

  final String title;
  final List<AlignmentField> fields;
}

class AlignmentPlanResolver {
  static const _motorPump = AlignmentSection(
    title: 'ALINEACIÓN MOTOR–BOMBA',
    fields: [
      AlignmentField(
        column: 'AMB_ANGULO_V',
        label: 'Ángulo vertical',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'AMB_ANGULO_H',
        label: 'Ángulo horizontal',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'AMB_COMPENSACION_V',
        label: 'Compensación vertical',
        unit: 'mm',
      ),
      AlignmentField(
        column: 'AMB_COMPENSACION_H',
        label: 'Compensación horizontal',
        unit: 'mm',
      ),
    ],
  );

  static const _motorGearbox = AlignmentSection(
    title: 'ALINEACIÓN MOTOR–CAJA',
    fields: [
      AlignmentField(
        column: 'ACM_ANGULO_V',
        label: 'Ángulo vertical',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'ACM_ANGULO_H',
        label: 'Ángulo horizontal',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'ACM_COMPENSACION_V',
        label: 'Compensación vertical',
        unit: 'mm',
      ),
      AlignmentField(
        column: 'ACM_COMPENSACION_H',
        label: 'Compensación horizontal',
        unit: 'mm',
      ),
    ],
  );

  static const _gearboxPump = AlignmentSection(
    title: 'ALINEACIÓN CAJA–BOMBA',
    fields: [
      AlignmentField(
        column: 'ACB_ANGULO_V',
        label: 'Ángulo vertical',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'ACB_ANGULO_H',
        label: 'Ángulo horizontal',
        unit: 'mm/100 mm',
      ),
      AlignmentField(
        column: 'ACB_COMPENSACION_V',
        label: 'Compensación vertical',
        unit: 'mm',
      ),
      AlignmentField(
        column: 'ACB_COMPENSACION_H',
        label: 'Compensación horizontal',
        unit: 'mm',
      ),
    ],
  );

  static List<AlignmentSection> fromPuntos(int puntos) {
    if (puntos == 10) {
      return [
        AlignmentSection(
            title: 'ALINEACIÓN DEL MOTOR', fields: _motorPump.fields)
      ];
    }
    if (const {1, 2, 9}.contains(puntos)) return const [_motorPump];
    if (puntos == 6) return const [_motorGearbox, _gearboxPump];
    return const [];
  }

  static bool isEligible(int puntos) => fromPuntos(puntos).isNotEmpty;
}
