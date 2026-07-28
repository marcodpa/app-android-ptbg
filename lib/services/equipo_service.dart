import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/qr_code_matcher.dart' as qr_matcher;
import '../db/db_helper.dart';
import '../data/mock_data.dart';
import '../services/api_service.dart';

class EquipoService {
  static final EquipoService instance = EquipoService._();
  EquipoService._();

  List<Equipo> _cache = [];
  bool _loaded = false;
  String? _lastError;

  List<Equipo> get equipos => _cache;
  String? get lastError => _lastError;

  Future<List<Equipo>> cargar({bool forceRefresh = false}) async {
    _lastError = null;

    // Asegura que el catalogo OFFLINE incrustado (con los TAC reales) este en la
    // tablet. Si habia un catalogo viejo guardado, lo reemplaza cuando sube la
    // version. Esto es lo que permite escanear los QR sin conexion.
    await _sembrarCatalogoBaseSiHaceFalta();

    if (_loaded && !forceRefresh && _cache.isNotEmpty) return _cache;

    if (!forceRefresh) {
      final guardados = await _cargarGuardados();
      if (guardados.isNotEmpty) {
        _cache = guardados;
        _loaded = true;
      }
    }

    try {
      final online = await ApiService.instance.checkConexion();
      if (!online) return _cache;

      final remote = await _descargarDesdeServidor();
      if (remote.isNotEmpty) {
        await _guardarLocalmente(remote, clearBeforeSave: forceRefresh);
        _cache = remote;
        _loaded = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ultima_descarga', DateTime.now().toIso8601String());
        await prefs.setInt('equipos_descargados', remote.length);
        await prefs.setInt(
          'equipos_sin_pt_eq',
          remote.where((e) => e.ptEq < 1 || e.ptEq > 9).length,
        );
      }
    } catch (e) {
      _lastError = e.toString();
    }

    return _cache;
  }

  Future<OfflineDownloadResult> descargarParaOffline({
    bool descargarLecturas = true,
  }) async {
    _lastError = null;

    try {
      final online = await ApiService.instance.checkConexion();
      if (!online) {
        final guardados = await _cargarGuardados();
        if (guardados.isNotEmpty) {
          _cache = guardados;
          _loaded = true;
        }
        return OfflineDownloadResult.failure(
          'Sin conexión al servidor. Se mantiene el catálogo local.',
          equipos: _cache,
          lecturas: 0,
        );
      }

      final remote = await _descargarDesdeServidor();
      if (remote.isEmpty) {
        return OfflineDownloadResult.failure(
          'El servidor no devolvió equipos.',
          equipos: _cache,
          lecturas: 0,
        );
      }

      await _guardarLocalmente(remote, clearBeforeSave: true);
      _cache = remote;
      _loaded = true;

      int lecturas = 0;
      if (descargarLecturas && !kIsWeb) {
        for (final eq in remote) {
          try {
            final ul = await ApiService.instance.fetchUltimaLectura(eq.localizacion);
            if (ul != null) {
              await DbHelper.instance.upsertUltimaLectura(ul);
              lecturas++;
            }
          } catch (_) {}
        }
      }

      final sinPtEq = remote.where((e) => e.ptEq < 1 || e.ptEq > 9).length;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ultima_descarga', DateTime.now().toIso8601String());
      await prefs.setInt('equipos_descargados', remote.length);
      await prefs.setInt('lecturas_descargadas', lecturas);
      await prefs.setInt('equipos_sin_pt_eq', sinPtEq);

      if (sinPtEq > 0) {
        return OfflineDownloadResult.failure(
          'Catálogo descargado, pero $sinPtEq equipos vienen sin PUNTOS válido desde MOT_EQUIP.',
          equipos: remote,
          lecturas: lecturas,
        );
      }

      return OfflineDownloadResult.success(equipos: remote, lecturas: lecturas);
    } catch (e) {
      _lastError = e.toString();
      final guardados = await _cargarGuardados();
      if (guardados.isNotEmpty) {
        _cache = guardados;
        _loaded = true;
      }
      return OfflineDownloadResult.failure(
        'Error al descargar catálogo: $e',
        equipos: _cache,
        lecturas: 0,
      );
    }
  }

  Future<List<Equipo>> _descargarDesdeServidor() async {
    final equipos = await ApiService.instance.fetchEquipos();
    final result = <Equipo>[];

    for (final e in equipos) {
      EquipoInfo? info = e.info;
      if (info == null || info.isEmpty) {
        try {
          info = await ApiService.instance.fetchEquipoInfo(e.localizacion);
        } catch (_) {}
      }

      result.add(e.copyWith(info: info));
    }

    return result;
  }

  Future<void> _guardarLocalmente(
    List<Equipo> equipos, {
    bool clearBeforeSave = false,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final json = equipos.map((e) => e.toMap()).toList();
      await prefs.setString('equipos_cache', jsonEncode(json));
      return;
    }

    if (clearBeforeSave) {
      await DbHelper.instance.clearEquiposCache();
    }
    await DbHelper.instance.upsertEquipos(equipos);
  }

  Future<List<Equipo>> _cargarGuardados() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('equipos_cache');
        if (raw == null) return [];
        final list = jsonDecode(raw) as List;
        return list
            .whereType<Map>()
            .map((j) => Equipo.fromJson(Map<String, dynamic>.from(j)))
            .toList();
      } catch (_) {
        return [];
      }
    }

    try {
      return await DbHelper.instance.getAllEquipos();
    } catch (_) {
      return [];
    }
  }

  /// Siembra el catalogo incrustado en el almacenamiento local de la tablet.
  /// Solo actua una vez por cada version del catalogo (catalogoBaseVersion):
  /// limpia el cache anterior y guarda el catalogo actual con los TAC reales.
  Future<void> _sembrarCatalogoBaseSiHaceFalta() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('catalogo_base_version') ?? 0;
      if (v >= catalogoBaseVersion) return;

      await DbHelper.instance.clearEquiposCache();
      await DbHelper.instance.upsertEquipos(mockEquipos);
      _cache = List.of(mockEquipos);
      _loaded = true;

      await prefs.setInt('catalogo_base_version', catalogoBaseVersion);
    } catch (_) {}
  }

  Equipo? buscarPorQr(String code) {
    final inputKeys = _qrKeys(code);
    if (inputKeys.isEmpty) return null;

    try {
      return _cache.firstWhere((e) => _equipoMatchesQr(e, inputKeys));
    } catch (_) {
      return null;
    }
  }

  List<String> get sistemas {
    final set = <String>{};
    for (final e in _cache) {
      set.add(e.sistema);
    }
    return set.toList()..sort();
  }

  List<Equipo> filtrar({String? sistema, String? busqueda}) {
    return _cache.where((e) {
      if (sistema != null && sistema != 'Todos' && e.sistema != sistema) return false;
      if (busqueda != null && busqueda.isNotEmpty) {
        final q = busqueda.toLowerCase();
        return e.equipo.toLowerCase().contains(q) ||
            e.qrDisplay.toLowerCase().contains(q) ||
            e.sistema.toLowerCase().contains(q) ||
            (e.scada ?? '').toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  Future<void> limpiarCacheLocal() async {
    _cache = [];
    _loaded = false;
    if (!kIsWeb) {
      await DbHelper.instance.clearEquiposCache();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('equipos_cache');
    }
  }

  void limpiarCache() {
    _cache = [];
    _loaded = false;
  }
}

class OfflineDownloadResult {
  final bool ok;
  final String? error;
  final List<Equipo> equipos;
  final int lecturas;

  const OfflineDownloadResult._({
    required this.ok,
    this.error,
    required this.equipos,
    required this.lecturas,
  });

  factory OfflineDownloadResult.success({
    required List<Equipo> equipos,
    required int lecturas,
  }) {
    return OfflineDownloadResult._(
      ok: true,
      equipos: equipos,
      lecturas: lecturas,
    );
  }

  factory OfflineDownloadResult.failure(
    String error, {
    required List<Equipo> equipos,
    required int lecturas,
  }) {
    return OfflineDownloadResult._(
      ok: false,
      error: error,
      equipos: equipos,
      lecturas: lecturas,
    );
  }
}

Set<String> _qrKeys(String? raw) {
  return qr_matcher.qrKeys(raw);
}

bool _equipoMatchesQr(Equipo e, Set<String> inputKeys) {
  return qr_matcher.equipoMatchesQr(e, inputKeys);
}
