import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/temperature_measurement.dart';

Map<String, dynamic> buildMedicionSyncPayload(MedicionLocal m) {
  return {
    'uuid': m.uuid,
    'localizacion': m.localizacion,
    'sistema': m.sistema,
    'fecha': m.fecha,
    'hora': m.hora,
    ...m.valores,
    'RMS': m.rms,
    'OBSERVACIONES': m.observaciones,
    'USUARIO': m.responsable,
    'CARGO': m.cargo,
    'MARCA': m.marca,
    'MODELO': m.modelo,
    'SERIAL': m.serial,
  };
}

Map<String, dynamic> buildTemperatureSyncPayload(TemperatureMeasurement m) {
  return {
    'uuid': m.uuid,
    'localizacion': m.localizacion,
    'sistema': m.sistema,
    'fecha': m.fecha,
    'hora': m.hora,
    for (var i = 1; i <= 10; i++) 'T$i': m.valores['T$i'] ?? 0.0,
    'OBSERVACIONES': m.observaciones,
    'USUARIO': m.responsable,
    'CARGO': m.cargo,
    'MARCA': m.marca,
    'MODELO': m.modelo,
    'SERIAL': m.serial,
    'ODT': m.odt,
  };
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const _prefKey = 'api_base_url';
  static const _tokenKey = 'auth_token';
  static const _defaultUrl = 'http://192.168.100.241:8001';

  Future<String> get baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == null || saved.trim().isEmpty) return _defaultUrl;
    return saved.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  Future<String?> get _token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> get _headers async {
    final token = await _token;
    return {
      'Content-Type': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  // ── LOGIN ─────────────────────────────────────────────────────────────
  Future<LoginResult> login(String username, [String password = '']) async {
    try {
      final url = await baseUrl;
      final res = await http
          .post(
            Uri.parse('$url/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, data['access_token'].toString());
        await prefs.setString('username', username);
        final responsable = (data['responsable'] ??
                data['nombre'] ??
                data['name'] ??
                data['usuario'] ??
                username)
            .toString();
        final cargo =
            (data['cargo'] ?? data['rol'] ?? data['role'] ?? 'MECANICO')
                .toString();
        await prefs.setString('responsable', responsable);
        await prefs.setString('cargo', cargo);
        return LoginResult.success(
          data['access_token'].toString(),
          responsable: responsable,
          cargo: cargo,
        );
      }
      return LoginResult.failure('Usuario incorrecto');
    } catch (_) {
      return LoginResult.failure('Sin conexión al servidor');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<List<Map<String, String>>> fetchUsuarios() async {
    final url = await baseUrl;
    final res = await http.get(
      Uri.parse('$url/usuarios'),
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('Error al obtener usuarios: HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          return {
            'usuario': (map['usuario'] ??
                    map['username'] ??
                    map['responsable'] ??
                    map['nombre'] ??
                    '')
                .toString(),
            'cargo': (map['cargo'] ?? 'MECANICO').toString(),
          };
        })
        .where((item) => item['usuario']!.trim().isNotEmpty)
        .toList();
  }

  // ── EQUIPOS ───────────────────────────────────────────────────────────
  Future<List<Equipo>> fetchEquipos() async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(
          Uri.parse('$url/equipos'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception(
          'Error al obtener equipos: HTTP ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw Exception(
          'La respuesta de /equipos no es una lista JSON. Respuesta: ${res.body}');
    }

    return decoded
        .whereType<Map>()
        .map((j) => Equipo.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<Equipo?> fetchEquipoByQr(String qrCode) async {
    final url = await baseUrl;
    final headers = await _headers;
    final encoded = Uri.encodeComponent(qrCode);
    final res = await http
        .get(
          Uri.parse('$url/equipos/$encoded'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      return Equipo.fromJson(Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    return null;
  }

  Future<EquipoInfo?> fetchEquipoInfo(int localizacion) async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(
          Uri.parse('$url/equipo-info/$localizacion'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      final info =
          EquipoInfo.fromJson(data, fallbackLocalizacion: localizacion);
      return info.isEmpty ? null : info;
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> fetchDebugPtEq() async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(
          Uri.parse('$url/debug-pt-eq'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return [];
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── ÚLTIMA LECTURA ────────────────────────────────────────────────────
  Future<UltimaLectura?> fetchUltimaLectura(int localizacion) async {
    try {
      final url = await baseUrl;
      final headers = await _headers;
      final res = await http
          .get(
            Uri.parse('$url/ultima-medicion/$localizacion'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return UltimaLectura.fromJson(
            Map<String, dynamic>.from(jsonDecode(res.body)));
      }
    } catch (_) {}
    return null;
  }

  Future<List<UltimaLectura>> fetchUltimasLecturas() async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(
          Uri.parse('$url/ultimas-mediciones'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception(
          'Error al obtener últimas mediciones: HTTP ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw Exception(
          'La respuesta de /ultimas-mediciones no es una lista JSON. Respuesta: ${res.body}');
    }

    return decoded
        .whereType<Map>()
        .map((j) => UltimaLectura.fromJson(Map<String, dynamic>.from(j)))
        .where((ul) => ul.localizacion > 0)
        .toList();
  }

  // ── SINCRONIZAR ───────────────────────────────────────────────────────
  Future<SyncResult> sincronizarMedicion(MedicionLocal m) async {
    try {
      final url = await baseUrl;
      final headers = await _headers;
      final body = buildMedicionSyncPayload(m);
      final res = await http
          .post(
            Uri.parse('$url/mediciones'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return SyncResult.ok(m.uuid);
      }
      if (res.statusCode == 401) {
        await logout();
        return SyncResult.error(
          m.uuid,
          'Sesion vencida. Inicie sesion de nuevo y vuelva a sincronizar.',
        );
      }
      return SyncResult.error(m.uuid, 'HTTP ${res.statusCode} ${res.body}');
    } catch (e) {
      return SyncResult.error(m.uuid, e.toString());
    }
  }

  Future<SyncResult> syncTemperature(TemperatureMeasurement measurement) async {
    try {
      final url = await baseUrl;
      final headers = await _headers;
      final res = await http
          .post(
            Uri.parse('$url/temperaturas'),
            headers: headers,
            body: jsonEncode(buildTemperatureSyncPayload(measurement)),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return SyncResult.ok(measurement.uuid);
      }
      if (res.statusCode == 401) {
        await logout();
        return SyncResult.error(
          measurement.uuid,
          'Sesion vencida. Inicie sesion de nuevo y vuelva a sincronizar.',
        );
      }
      return SyncResult.error(
        measurement.uuid,
        'HTTP ${res.statusCode} ${res.body}',
      );
    } catch (e) {
      return SyncResult.error(measurement.uuid, e.toString());
    }
  }

  Future<TemperatureReading?> fetchLatestTemperature(
    int localizacion,
  ) async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(
          Uri.parse('$url/temperaturas/ultima/$localizacion'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception(
        'Error al obtener ultima temperatura: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return TemperatureReading.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body)),
    );
  }

  Future<List<TemperatureReading>> fetchLatestTemperatures({
    int limit = 50,
  }) async {
    return _fetchTemperatureList('/temperaturas/ultimas?limit=$limit');
  }

  Future<List<TemperatureReading>> fetchTemperatureHistory({
    int? localizacion,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (localizacion != null) 'localizacion': '$localizacion',
    };
    final path = Uri(path: '/temperaturas', queryParameters: query).toString();
    return _fetchTemperatureList(path);
  }

  Future<List<TemperatureReading>> _fetchTemperatureList(String path) async {
    final url = await baseUrl;
    final headers = await _headers;
    final res = await http
        .get(Uri.parse('$url$path'), headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception(
        'Error al obtener temperaturas: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw Exception('La respuesta de temperaturas no es una lista JSON.');
    }
    return decoded
        .whereType<Map>()
        .map((row) => TemperatureReading.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  // ── ESTADO ────────────────────────────────────────────────────────────
  Future<bool> checkConexion() async {
    try {
      final url = await baseUrl;
      final res = await http
          .get(Uri.parse('$url/estado'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUltimasMediciones(String token) async {
    try {
      final url = await baseUrl;
      final res = await http.get(
        Uri.parse('$url/ultimas-mediciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }
}

class LoginResult {
  final bool ok;
  final String? token;
  final String? error;
  final String? responsable;
  final String? cargo;
  LoginResult.success(this.token, {this.responsable, this.cargo})
      : ok = true,
        error = null;
  LoginResult.failure(this.error)
      : ok = false,
        token = null,
        responsable = null,
        cargo = null;
}

class SyncResult {
  final bool ok;
  final String uuid;
  final String? error;
  SyncResult.ok(this.uuid)
      : ok = true,
        error = null;
  SyncResult.error(this.uuid, this.error) : ok = false;
}
