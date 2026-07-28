import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/db_helper.dart';
import '../services/api_service.dart';

class AppProvider extends ChangeNotifier {
  static final AppProvider instance = AppProvider._();
  AppProvider._();

  String _username = '';
  bool _online = false;
  int _pendientes = 0;
  int _inspeccionadosHoy = 0;
  int _errores = 0;
  DateTime? _ultimaSync;

  String get username => _username;
  bool get online => _online;
  int get pendientes => _pendientes;
  int get inspeccionadosHoy => _inspeccionadosHoy;
  int get errores => _errores;
  DateTime? get ultimaSync => _ultimaSync;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? '';
    final syncTs = prefs.getString('ultima_sync');
    if (syncTs != null) _ultimaSync = DateTime.tryParse(syncTs);
    await _checkOnline();
    await refreshStats();
  }

  Future<void> _checkOnline() async {
    _online = await ApiService.instance.checkConexion();
    notifyListeners();
  }

  Future<void> refreshStats() async {
    final pendientes = await DbHelper.instance.getPendientes();
    final temperaturas = await DbHelper.instance.getPendingTemperatures();
    final reemplazos = await DbHelper.instance.getPendingReplacements();
    final alineaciones = await DbHelper.instance.getPendingAlignments();
    final sincHoy = await DbHelper.instance.getSincronizadasHoy();
    final temperaturasHoy =
        await DbHelper.instance.countSyncedTemperaturesToday();
    final reemplazosHoy =
        await DbHelper.instance.countSyncedReplacementsToday();
    final alineacionesHoy =
        await DbHelper.instance.countSyncedAlignmentsToday();
    final errCount = await DbHelper.instance.countErrores();
    final temperatureErrors = await DbHelper.instance.countTemperatureErrors();
    final replacementErrors = await DbHelper.instance.countReplacementErrors();
    final alignmentErrors = await DbHelper.instance.countAlignmentErrors();
    _pendientes = pendientes.length +
        temperaturas.length +
        reemplazos.length +
        alineaciones.length;
    _inspeccionadosHoy =
        sincHoy.length + temperaturasHoy + reemplazosHoy + alineacionesHoy;
    _errores =
        errCount + temperatureErrors + replacementErrors + alignmentErrors;
    notifyListeners();
  }

  Future<void> checkOnline() => _checkOnline();
}
