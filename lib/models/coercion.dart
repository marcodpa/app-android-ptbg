/// Coercion de los valores crudos que llegan de SQLite y de la API.
///
/// Estas cuatro funciones existian copiadas en once modelos con once nombres
/// distintos (`_texto`, `_text`, `_t`, `_entero`, `_int`, `_toInt`,
/// `_temperatureInt`, `parseTemperature`, `parseLubricationValue`,
/// `_alignmentDouble`...). Todas hacian lo mismo, y alguna ya habia empezado
/// a divergir. Aqui viven una sola vez; los modelos delegan.
library;

/// El valor como texto recortado; vacio si es null.
String textoDe(Object? valor) => (valor ?? '').toString().trim();

/// El valor como texto recortado, o null si no hay nada util.
String? textoONuloDe(Object? valor) {
  final texto = valor?.toString().trim();
  if (texto == null || texto.isEmpty) return null;
  return texto;
}

/// El valor como entero; 0 si no se puede leer.
int enteroDe(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(textoDe(valor)) ?? 0;
}

/// El valor como decimal, o null si no hay lectura.
///
/// Acepta coma decimal ademas de punto: el teclado de la tablet ofrece la
/// coma y los datos viejos pueden traerla.
double? decimalDe(Object? valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  final texto = valor.toString().trim().replaceAll(',', '.');
  if (texto.isEmpty) return null;
  return double.tryParse(texto);
}
