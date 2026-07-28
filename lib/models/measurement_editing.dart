import 'dart:math' as math;

String? cleanGeneralObservation(String value) {
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

double? parseMeasurementValue(String value) {
  final clean = value.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final parsed = double.tryParse(clean);
  if (parsed == null) {
    throw FormatException('Valor de medicion invalido: $value');
  }
  return parsed;
}

Map<String, double?> editedMeasurementValues({
  required Map<String, double?> current,
  required Map<String, String> edits,
}) {
  final values = Map<String, double?>.from(current);
  for (final entry in edits.entries) {
    values[entry.key] = parseMeasurementValue(entry.value);
  }
  return values;
}

double? calculateRms(Map<String, double?> values) {
  final doubles = values.values.whereType<double>().toList();
  if (doubles.isEmpty) return null;
  final meanSquares =
      doubles.fold<double>(0.0, (sum, x) => sum + x * x) / doubles.length;
  return double.parse(math.sqrt(meanSquares).toStringAsFixed(2));
}
