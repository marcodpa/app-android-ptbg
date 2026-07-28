import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/medicion_remota.dart';
import 'api_service.dart';

/// Descarga el histórico de mediciones y las últimas lecturas por equipo.
class MedicionesService {
  MedicionesService._();
  static final MedicionesService instance = MedicionesService._();

  Future<List<MedicionRemota>> descargarTodas() async {
    return _getLista('/mediciones');
  }

  /// Primero usa el endpoint optimizado. Si no existe, descarga el histórico
  /// y calcula en la tablet la fila más reciente de cada LOCALIZACION.
  Future<List<MedicionRemota>> descargarUltimasPorEquipo() async {
    try {
      final result = await _getLista('/ultimas-mediciones');
      if (result.isNotEmpty) return _soloUltimas(result);
    } catch (_) {
      // Se usa el respaldo de histórico completo.
    }

    final todas = await descargarTodas();
    return _soloUltimas(todas);
  }

  Future<List<MedicionRemota>> _getLista(String path) async {
    final baseUrl = (await ApiService.instance.baseUrl).replaceAll(RegExp(r'/$'), '');
    final response = await http
        .get(
          Uri.parse('$baseUrl$path'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rawList = _extraerLista(decoded);

    final result = rawList
        .whereType<Map>()
        .map((item) => MedicionRemota.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((m) => m.localizacion > 0)
        .toList();

    result.sort(_compararDesc);
    return result;
  }

  List<dynamic> _extraerLista(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in const ['data', 'mediciones', 'items', 'resultados']) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }
    throw Exception('La API no devolvió una lista de mediciones válida');
  }

  List<MedicionRemota> _soloUltimas(List<MedicionRemota> mediciones) {
    final latest = <int, MedicionRemota>{};

    for (final medicion in mediciones) {
      if (medicion.localizacion <= 0) continue;
      final actual = latest[medicion.localizacion];
      if (actual == null || _esMasNueva(medicion, actual)) {
        latest[medicion.localizacion] = medicion;
      }
    }

    final result = latest.values.toList()..sort(_compararDesc);
    return result;
  }

  bool _esMasNueva(MedicionRemota a, MedicionRemota b) {
    final cmp = a.fechaHora.compareTo(b.fechaHora);
    if (cmp != 0) return cmp > 0;
    return a.id > b.id;
  }

  int _compararDesc(MedicionRemota a, MedicionRemota b) {
    final cmp = b.fechaHora.compareTo(a.fechaHora);
    if (cmp != 0) return cmp;
    return b.id.compareTo(a.id);
  }
}
