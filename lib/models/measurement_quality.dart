enum VibrationQualityLevel { empty, normal, warning, danger, extreme }

class VibrationQuality {
  final VibrationQualityLevel level;
  final String label;
  final String detail;

  const VibrationQuality._({
    required this.level,
    required this.label,
    required this.detail,
  });

  factory VibrationQuality.fromValue(double? value) {
    if (value == null) {
      return const VibrationQuality._(
        level: VibrationQualityLevel.empty,
        label: 'Sin lectura',
        detail: 'Ingrese el valor en mm/s',
      );
    }
    if (value >= 50) {
      return const VibrationQuality._(
        level: VibrationQualityLevel.extreme,
        label: 'Muy alto',
        detail: 'Valor demasiado elevado, posible error de captura',
      );
    }
    if (value >= 11.2) {
      return const VibrationQuality._(
        level: VibrationQualityLevel.danger,
        label: 'Alto',
        detail: 'Confirme que la lectura sea correcta',
      );
    }
    if (value >= 4.5) {
      return const VibrationQuality._(
        level: VibrationQualityLevel.warning,
        label: 'Medio',
        detail: 'Vibracion por encima de lo normal',
      );
    }
    return const VibrationQuality._(
      level: VibrationQualityLevel.normal,
      label: 'Bajo',
      detail: 'Lectura dentro de rango esperado',
    );
  }
}
