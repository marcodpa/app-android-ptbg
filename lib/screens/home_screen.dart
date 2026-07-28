import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/usb_sync_status.dart';
import '../services/api_service.dart';
import '../services/equipo_service.dart';
import '../db/db_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color azul = Color(0xFF0A1C3E);
  static const Color azul2 = Color(0xFF0D3B6E);
  static const Color verde = Color(0xFF00B89C);
  static const Color fondo = Color(0xFFF2F5FA);
  static const Color texto = Color(0xFF1A2B4A);
  static const Color texto2 = Color(0xFF6B7C9A);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  String usuario = 'Mecánico';
  String apiUrl = '';
  String mensaje = 'Cargando información local...';
  bool online = false;
  bool cargando = true;
  bool refrescando = false;
  List<Equipo> equipos = <Equipo>[];
  int pendientes = 0;
  int sincronizadasHoy = 0;
  int errores = 0;
  UsbSyncStatus usbStatus = UsbSyncStatus.fromValues(
    status: null,
    serial: null,
    detail: null,
    lastSeen: null,
    now: DateTime.now(),
  );
  Timer? usbStatusTimer;

  @override
  void initState() {
    super.initState();
    _cargarHome(refrescarServidor: false, mostrarMensaje: false);
    _loadUsbStatus();
    usbStatusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadUsbStatus(),
    );
  }

  @override
  void dispose() {
    usbStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsbStatus() async {
    UsbSyncStatus? fileStatus;
    if (!kIsWeb) {
      try {
        final file =
            File('/data/data/com.example.scv_ptbg/files/usb_status.json');
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString());
          if (data is Map) {
            fileStatus = UsbSyncStatus.fromValues(
              status: data['status']?.toString(),
              serial: data['serial']?.toString(),
              detail: data['detail']?.toString(),
              lastSeen: data['last_seen']?.toString(),
              now: DateTime.now(),
            );
          }
        }
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final status = fileStatus ??
        UsbSyncStatus.fromValues(
          status: prefs.getString('usb_sync_status'),
          serial: prefs.getString('usb_sync_serial'),
          detail: prefs.getString('usb_sync_detail'),
          lastSeen: prefs.getString('usb_sync_last_seen'),
          now: DateTime.now(),
        );
    if (!mounted) return;
    setState(() => usbStatus = status);
  }

  Future<void> _cargarHome({
    required bool refrescarServidor,
    required bool mostrarMensaje,
  }) async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      refrescando = refrescarServidor;
      mensaje = refrescarServidor
          ? 'Actualizando catálogo desde el servidor...'
          : 'Cargando información local...';
    });

    String usuarioLocal = 'Mecánico';
    String urlLocal = '';
    bool onlineLocal = false;
    List<Equipo> equiposLocal = <Equipo>[];
    int pendientesLocal = 0;
    int hoyLocal = 0;
    int erroresLocal = 0;
    String mensajeLocal = 'Home listo';

    try {
      final prefs = await SharedPreferences.getInstance();
      usuarioLocal = prefs.getString('username') ?? 'Mecánico';
    } catch (_) {}

    try {
      urlLocal = await ApiService.instance.baseUrl;
    } catch (_) {
      urlLocal = '';
    }

    try {
      onlineLocal = await ApiService.instance.checkConexion();
    } catch (_) {
      onlineLocal = false;
    }

    try {
      equiposLocal = await EquipoService.instance.cargar(
        forceRefresh: refrescarServidor && onlineLocal,
      );
      mensajeLocal = onlineLocal
          ? 'Conectado al servidor'
          : 'Modo offline: usando catálogo local';
    } catch (e) {
      equiposLocal = <Equipo>[];
      mensajeLocal = 'No se pudo cargar el catálogo: $e';
    }

    try {
      final p = await DbHelper.instance.getPendientes();
      final t = await DbHelper.instance.getPendingTemperatures();
      final r = await DbHelper.instance.getPendingReplacements();
      final a = await DbHelper.instance.getPendingAlignments();
      pendientesLocal = p.length + t.length + r.length + a.length;
    } catch (_) {
      pendientesLocal = 0;
    }

    try {
      final h = await DbHelper.instance.getSincronizadasHoy();
      final t = await DbHelper.instance.countSyncedTemperaturesToday();
      final r = await DbHelper.instance.countSyncedReplacementsToday();
      final a = await DbHelper.instance.countSyncedAlignmentsToday();
      hoyLocal = h.length + t + r + a;
    } catch (_) {
      hoyLocal = 0;
    }

    try {
      final v = await DbHelper.instance.countErrores();
      final t = await DbHelper.instance.countTemperatureErrors();
      final r = await DbHelper.instance.countReplacementErrors();
      final a = await DbHelper.instance.countAlignmentErrors();
      erroresLocal = v + t + r + a;
    } catch (_) {
      erroresLocal = 0;
    }

    if (!mounted) return;

    setState(() {
      usuario = usuarioLocal;
      apiUrl = urlLocal;
      online = onlineLocal;
      equipos = equiposLocal;
      pendientes = pendientesLocal;
      sincronizadasHoy = hoyLocal;
      errores = erroresLocal;
      mensaje = mensajeLocal;
      cargando = false;
      refrescando = false;
    });

    if (mostrarMensaje) {
      _snack(mensajeLocal, onlineLocal ? verde : warning);
    }
  }

  Future<void> _refrescar() async {
    await _cargarHome(refrescarServidor: true, mostrarMensaje: true);
  }

  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _abrir(String ruta) {
    try {
      Navigator.pushNamed(context, ruta);
    } catch (e) {
      _snack('No se pudo abrir $ruta: $e', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: Column(
        children: <Widget>[
          _header(),
          Expanded(
            child: RefreshIndicator(
              color: verde,
              onRefresh: _refrescar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: <Widget>[
                  _estadoCard(),
                  const SizedBox(height: 14),
                  _usbStatusCard(),
                  const SizedBox(height: 14),
                  _offlineCard(),
                  const SizedBox(height: 14),
                  _resumenCard(),
                  const SizedBox(height: 14),
                  _acciones(),
                  const SizedBox(height: 14),
                  _notaCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[azul, azul2],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: verde.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: verde.withOpacity(0.45)),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'SCV-PTBG',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Sistema de Captura de Vibraciones',
                      style: TextStyle(
                        color: Color(0xFF7EE2D8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: refrescando ? null : _refrescar,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: refrescando
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: verde,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoCard() {
    return _card(
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE8EDF5),
            child: Icon(
              online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: online ? verde : error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  online ? 'Servidor online' : 'Servidor offline',
                  style: TextStyle(
                    color: online ? verde : error,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mensaje,
                  style: const TextStyle(color: texto2, fontSize: 12),
                ),
                if (apiUrl.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    apiUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (cargando)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: verde),
            ),
        ],
      ),
    );
  }

  Widget _usbStatusCard() {
    final bool connected = usbStatus.online;
    final Color color = connected ? verde : warning;
    return _card(
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  connected ? const Color(0xFFE6F7F4) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              connected ? Icons.usb_rounded : Icons.usb_off_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  connected ? 'USB laptop online' : 'USB laptop offline',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  usbStatus.detail,
                  style: const TextStyle(color: texto2, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineCard() {
    final String textoEquipos = equipos.isEmpty
        ? 'No hay equipos guardados todavía'
        : '${equipos.length} equipos disponibles para modo offline';

    return _card(
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: equipos.isEmpty
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              equipos.isEmpty
                  ? Icons.cloud_off_rounded
                  : Icons.inventory_2_outlined,
              color: equipos.isEmpty ? warning : verde,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Catálogo offline',
                  style: TextStyle(
                    color: texto,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  textoEquipos,
                  style: const TextStyle(color: texto2, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: refrescando ? null : _refrescar,
            icon: refrescando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(refrescando ? '...' : 'Refrescar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: verde,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Resumen de actividad',
            style: TextStyle(
              color: texto,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _stat(
                  icon: Icons.cloud_upload_outlined,
                  value: pendientes.toString(),
                  label: 'Pendientes',
                  color: pendientes > 0 ? warning : texto2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  icon: Icons.task_alt_rounded,
                  value: sincronizadasHoy.toString(),
                  label: 'Hoy',
                  color: verde,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  icon: Icons.inventory_2_outlined,
                  value: equipos.length.toString(),
                  label: 'Equipos',
                  color: azul2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  icon: Icons.warning_amber_rounded,
                  value: errores.toString(),
                  label: 'Errores',
                  color: errores > 0 ? error : texto2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acciones() {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _action(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Escanear QR',
                subtitle: 'Nueva medición',
                color: azul,
                onTap: () => _abrir('/qr'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _action(
                icon: Icons.route_rounded,
                title: 'Ruta',
                subtitle: 'Ruta de medición',
                color: verde,
                onTap: () => _abrir('/ruta'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _action(
                icon: Icons.sync_rounded,
                title: 'Sincronizar',
                subtitle: 'Enviar datos',
                color: const Color(0xFF006D5B),
                onTap: () => _abrir('/sync'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _action(
                icon: Icons.folder_open_rounded,
                title: 'Mediciones',
                subtitle: 'Ver guardadas',
                color: const Color(0xFF1E4A8A),
                onTap: () => _abrir('/mediciones'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _notaCard() {
    return _card(
      child: const Row(
        children: <Widget>[
          Icon(Icons.verified_user_outlined, color: verde),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trabaja seguro. Si no hay red, la app debe seguir capturando y luego sincronizar.',
              style: TextStyle(color: texto2, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _stat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: texto2, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 118,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 30),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 62,
        color: azul,
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: () {},
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.home_rounded, color: verde, size: 23),
                    SizedBox(height: 2),
                    Text(
                      'Inicio',
                      style: TextStyle(
                        color: verde,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _abrir('/ajustes'),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.settings_outlined,
                        color: Colors.white70, size: 23),
                    SizedBox(height: 2),
                    Text(
                      'Ajustes',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
