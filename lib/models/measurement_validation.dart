import 'package:flutter/services.dart';

class MeasurementValidation {
  const MeasurementValidation._();

  static const temperatureMin = -100.0;
  static const temperatureMax = 1000.0;
  static const vibrationMin = 0.0;
  static const vibrationMax = 200.0;
  static const lubricationMin = 0.0;
  static const lubricationMax = 10000.0;

  static double? parseDecimal(String? raw) {
    final text = (raw ?? '').trim().replaceAll(',', '.');
    if (text.isEmpty ||
        !RegExp(r'^[-+]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(text)) {
      return null;
    }
    final value = double.tryParse(text);
    return value != null && value.isFinite ? value : null;
  }

  static String? requiredRange(
    String? raw, {
    required double min,
    required double max,
    required String unit,
    int? maxDecimalPlaces,
  }) {
    if ((raw ?? '').trim().isEmpty) return 'Valor obligatorio';
    final value = parseDecimal(raw);
    if (value == null) return 'Ingrese un número válido';
    if (maxDecimalPlaces != null) {
      final normalized = (raw ?? '').trim().replaceAll(',', '.');
      final separator = normalized.indexOf('.');
      if (separator >= 0 &&
          normalized.length - separator - 1 > maxDecimalPlaces) {
        return 'Use máximo $maxDecimalPlaces decimales';
      }
    }
    if (value < min || value > max) {
      final suffix = unit.isEmpty ? '' : ' $unit';
      return 'Rango permitido: ${_number(min)} a ${_number(max)}$suffix';
    }
    return null;
  }

  static String? requiredNumber(String? raw) {
    if ((raw ?? '').trim().isEmpty) return 'Valor obligatorio';
    return parseDecimal(raw) == null ? 'Ingrese un número válido' : null;
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  static TextInputFormatter decimalFormatter({
    required bool signed,
    int decimalPlaces = 3,
  }) {
    final expression = signed
        ? RegExp('^[-+]?(?:\\d{0,7}(?:[\\.,]\\d{0,$decimalPlaces})?)?\$')
        : RegExp('^(?:\\d{0,7}(?:[\\.,]\\d{0,$decimalPlaces})?)?\$');
    return TextInputFormatter.withFunction((oldValue, newValue) =>
        expression.hasMatch(newValue.text) ? newValue : oldValue);
  }
}

enum MeasurementAdvisoryLevel { empty, normal, attention, high, critical }

class MeasurementAdvisory {
  const MeasurementAdvisory(this.level, this.label, this.detail);

  final MeasurementAdvisoryLevel level;
  final String label;
  final String detail;

  static const empty = MeasurementAdvisory(
    MeasurementAdvisoryLevel.empty,
    'Sin lectura',
    'Ingrese un valor para evaluarlo',
  );

  factory MeasurementAdvisory.temperature(double? value) {
    if (value == null) return empty;
    if (value >= 150 || value < -40) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.critical,
          'Muy alto', 'Valor muy fuera de lo habitual; confirme la lectura');
    }
    if (value >= 100) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.high, 'Alto',
          'Temperatura elevada; revise la condición del equipo');
    }
    if (value >= 80) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.attention,
          'Medio', 'Temperatura por encima de lo habitual');
    }
    return const MeasurementAdvisory(MeasurementAdvisoryLevel.normal, 'Bajo',
        'Lectura dentro del nivel esperado');
  }

  factory MeasurementAdvisory.alignment(double? value) {
    if (value == null) return empty;
    final magnitude = value.abs();
    if (magnitude >= 1) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.critical,
          'Muy alto', 'Desviación muy elevada; confirme la captura');
    }
    if (magnitude >= .20) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.high, 'Alto',
          'Desviación alta de alineación');
    }
    if (magnitude >= .10) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.attention,
          'Medio', 'Desviación por encima de lo habitual');
    }
    return const MeasurementAdvisory(MeasurementAdvisoryLevel.normal, 'Bajo',
        'Valor de alineación dentro del nivel esperado');
  }

  factory MeasurementAdvisory.lubrication(double? value, double? reference) {
    if (value == null) return empty;
    if (reference == null || reference <= 0) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.normal,
          'Registrado', 'Sin cantidad de referencia para comparar');
    }
    final ratio = value / reference;
    if (ratio > 1.5) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.critical,
          'Muy alto', 'Cantidad muy superior a la recomendada');
    }
    if (ratio > 1.2) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.high, 'Alto',
          'Cantidad superior a la recomendación');
    }
    if (ratio >= .8) {
      return const MeasurementAdvisory(MeasurementAdvisoryLevel.attention,
          'Medio', 'Cantidad cercana a la recomendada');
    }
    return const MeasurementAdvisory(MeasurementAdvisoryLevel.normal, 'Bajo',
        'Cantidad inferior a la recomendada');
  }
}
