import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/servicio_reciente.dart';
import '../models/usb_sync_status.dart';
import '../services/equipo_service.dart';
import '../db/db_helper.dart';
import 'black_start_screen.dart';
import 'equipment_history_screen.dart';
import 'limpieza_plato_screen.dart';
import '../widgets/industrial_navigation.dart';
import '../theme.dart';
import '../widgets/avisos.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color verde = Color(0xFF00B89C);
  static const Color fondo = Color(0xFF071226);
  // Los colores de texto del inicio se eligen segun el tema. Antes eran dos
  // constantes de modo noche —un blanco casi puro y un gris azulado— y en
  // modo dia quedaban lavadas sobre el fondo claro: el nombre del tecnico,
  // los contadores y los titulos de las tarjetas apenas se leian.
  static const Color _textoNoche = Color(0xFFF4F8FF);
  static const Color _texto2Noche = Color(0xFF9EB0CA);
  static const Color _textoDia = Color(0xFF123A68);
  static const Color _texto2Dia = Color(0xFF5A7391);

  static Color get texto =>
      esterThemeController.isDark ? _textoNoche : _textoDia;
  static Color get texto2 =>
      esterThemeController.isDark ? _texto2Noche : _texto2Dia;
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  String usuario = 'Mecánico';
  String apiUrl = '';
  String mensaje = 'Cargando información local...';
  bool online = false;
  bool cargando = true;
  bool refrescando = false;
  List<Equipo> equipos = <Equipo>[];

  /// Los ultimos trabajos ya sincronizados, para la seccion
  /// de recientes.
  List<ServicioReciente> recientes = const [];
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
        final file = File(
          '/data/data/com.example.scv_ptbg/files/usb_status.json',
        );
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString());
          if (data is Map) {
            fileStatus = UsbSyncStatus.fromValues(
              status: data['status']?.toString(),
              serial: data['serial']?.toString(),
              detail: data['detail']?.toString(),
              lastSeen: data['last_seen']?.toString(),
              requestId: data['request_id']?.toString(),
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
          requestId: prefs.getString('usb_sync_request_id'),
          now: DateTime.now(),
        );
    if (!mounted) return;
    // Solo se redibuja si el estado USB de verdad cambio. Este metodo corre
    // cada 3 segundos en un Timer, y sin la comparacion reconstruia la
    // pantalla completa 20 veces por minuto aunque no pasara nada.
    if (status == usbStatus) return;
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
    String urlLocal = 'Sincronización exclusiva por USB';
    bool onlineLocal = false;
    List<Equipo> equiposLocal = <Equipo>[];
    int pendientesLocal = 0;
    int hoyLocal = 0;
    int erroresLocal = 0;
    String mensajeLocal = 'Home listo';
    List<ServicioReciente> recientesLocal = const [];

    try {
      final prefs = await SharedPreferences.getInstance();
      usuarioLocal = prefs.getString('username') ?? 'Mecánico';
    } catch (_) {}

    try {
      urlLocal = 'Sincronización exclusiva por USB';
    } catch (_) {
      urlLocal = '';
    }

    try {
      onlineLocal = false;
    } catch (_) {
      onlineLocal = false;
    }

    try {
      equiposLocal = await EquipoService.instance.cargar(
        forceRefresh: false,
      );
      // El resumen debe reflejar siempre el catálogo SQLite que usan Equipos
      // y QR, incluso si la caché del servicio todavía no se ha actualizado.
      if (equiposLocal.isEmpty) {
        equiposLocal = await DbHelper.instance.getAllEquipos();
      }
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
      final l = await DbHelper.instance.getPendingLubrications();
      pendientesLocal = p.length + t.length + r.length + a.length + l.length;
    } catch (_) {
      pendientesLocal = 0;
    }

    try {
      final h = await DbHelper.instance.getSincronizadasHoy();
      final t = await DbHelper.instance.countSyncedTemperaturesToday();
      final r = await DbHelper.instance.countSyncedReplacementsToday();
      final a = await DbHelper.instance.countSyncedAlignmentsToday();
      final l = await DbHelper.instance.countSyncedLubricationsToday();
      hoyLocal = h.length + t + r + a + l;
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

    try {
      recientesLocal = await DbHelper.instance.serviciosRecientes();
    } catch (_) {
      // Sin recientes el inicio funciona igual; es informativo.
      recientesLocal = const [];
    }

    if (!mounted) return;

    setState(() {
      usuario = usuarioLocal;
      apiUrl = urlLocal;
      online = onlineLocal;
      equipos = equiposLocal;
      recientes = recientesLocal;
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
    await _loadUsbStatus();
    if (!usbStatus.online) {
      _snack('Conecta la laptop por USB para recargar los equipos.', warning);
      return;
    }

    setState(() {
      refrescando = true;
      mensaje = 'Descargando catálogo desde la laptop por USB...';
    });
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final file = File(
        '/data/data/com.example.scv_ptbg/files/usb_sync_request.json',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'id': requestId,
          'action': 'download_data',
          'created_at': DateTime.now().toIso8601String(),
        }),
      );

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 2));
        await _loadUsbStatus();
        if (usbStatus.requestId == requestId &&
            (usbStatus.rawStatus == 'DONE' || usbStatus.rawStatus == 'ERROR')) {
          break;
        }
      }

      if (!mounted) return;
      if (usbStatus.requestId != requestId || usbStatus.rawStatus != 'DONE') {
        throw Exception(usbStatus.detail);
      }

      await DbHelper.instance.reopenAfterUsbSync();
      EquipoService.instance.limpiarCache();
      await _cargarHome(refrescarServidor: false, mostrarMensaje: false);
      _snack('Equipos y datos técnicos actualizados por USB.', verde);
    } catch (e) {
      if (mounted) {
        setState(() {
          refrescando = false;
          mensaje = 'Error de descarga USB: $e';
        });
        _snack('No se pudo recargar por USB: $e', error);
      }
    }
  }

  void _snack(String text, Color color) {
    if (!mounted) return;
    avisar(context, text, color);
  }

  void _abrir(String ruta) {
    try {
      Navigator.pushReplacementNamed(context, ruta);
    } catch (e) {
      _snack('No se pudo abrir $ruta: $e', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          esterThemeController.isDark ? fondo : const Color(0xFFF7FAFE),
      body: Row(children: <Widget>[
        const IndustrialSideRail(activeRoute: '/home'),
        Expanded(
          child: Column(children: <Widget>[
            // Fuera de la lista y a todo lo ancho, como en las demas
            // pantallas. Sin flecha: es la raiz de la app.
            IndustrialContentHeader(
              title: 'Panel industrial',
              subtitle: 'Equipos, servicios y seguimiento de planta',
              icon: Icons.dashboard_rounded,
              showBack: false,
              actions: [_chipUsb()],
            ),
            Expanded(
              child: RefreshIndicator(
                color: verde,
                onRefresh: _refrescar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  children: <Widget>[
                    _profileAndStats(),
                    const SizedBox(height: 12),
                    _referenceModules(),
                    const SizedBox(height: 14),
                    _notaCard(),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Estado del USB, dentro de la barra de titulo.
  ///
  /// Los colores son propios y no los del tema porque va sobre el degradado
  /// oscuro del encabezado: el verde y el ambar se leen igual en ambos modos.
  Widget _chipUsb() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: (usbStatus.online ? verde : warning).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: (usbStatus.online ? verde : warning)
                    .withValues(alpha: .45))),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(usbStatus.online ? Icons.check_rounded : Icons.usb_off_rounded,
              color: usbStatus.online ? verde : warning, size: 13),
          const SizedBox(width: 4),
          Text(usbStatus.online ? 'SINCRONIZADO' : 'SIN USB',
              style: AppText.micro
                  .copyWith(color: usbStatus.online ? verde : warning)),
        ]),
      );

  Widget _profileAndStats() => SizedBox(
        height: 116,
        child: Row(children: <Widget>[
          Expanded(
              flex: 5,
              child: _glassCard(
                  child: Row(children: <Widget>[
                Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: <Color>[
                          Color(0xFF28466E),
                          Color(0xFF172743)
                        ]),
                        border: Border.all(color: const Color(0xFF49678E))),
                    child: const Icon(Icons.engineering_rounded,
                        color: Color(0xFFE8C39E), size: 40)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(usuario,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.seccion.copyWith(color: texto)),
                    const SizedBox(height: 3),
                    Text('Técnico de mantenimiento',
                        style: AppText.subtitulo.copyWith(color: texto2)),
                    const SizedBox(height: 8),
                    _miniBadge(
                        usbStatus.online ? 'USB CONECTADO' : 'USB DESCONECTADO',
                        usbStatus.online ? verde : warning),
                  ],
                )),
              ]))),
          const SizedBox(width: 9),
          Expanded(
              flex: 3,
              child: Column(children: <Widget>[
                Expanded(
                    child: _glassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text('Tareas completadas hoy',
                                  style:
                                      AppText.etiqueta.copyWith(color: texto2)),
                              Text(
                                  '$sincronizadasHoy/${sincronizadasHoy + pendientes}',
                                  style: AppText.datoGrande
                                      .copyWith(color: texto)),
                            ]))),
                const SizedBox(height: 7),
                Expanded(
                    child: _glassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text('Equipos disponibles',
                                  style:
                                      AppText.etiqueta.copyWith(color: texto2)),
                              Text('${equipos.length}',
                                  style: AppText.datoGrande
                                      .copyWith(color: texto)),
                            ]))),
              ])),
        ]),
      );

  Widget _referenceModules() => SizedBox(
        height: 300,
        child: Row(children: <Widget>[
          Expanded(
              flex: 4,
              child: _moduleCard(
                title: 'Escanear QR',
                subtitle: 'INICIAR INSPECCIÓN',
                icon: Icons.qr_code_2_rounded,
                accent: const Color(0xFF62D8FF),
                large: true,
                onTap: () => _abrir('/qr'),
              )),
          const SizedBox(width: 9),
          Expanded(
              flex: 6,
              child: Column(children: <Widget>[
                Expanded(
                    child: Row(children: <Widget>[
                  Expanded(
                      child: _moduleCard(
                          title: 'Todos los equipos',
                          subtitle: 'Generales y por pieza',
                          icon: Icons.precision_manufacturing_outlined,
                          accent: verde,
                          onTap: () => _abrir('/equipos'))),
                  const SizedBox(width: 9),
                  Expanded(
                      child: _moduleCard(
                          title: 'Sincronización USB',
                          subtitle: usbStatus.online
                              ? 'Laptop conectada'
                              : 'Sin conexión',
                          icon: Icons.usb_rounded,
                          accent: const Color(0xFF60A5FA),
                          onTap: () => _abrir('/sync'))),
                ])),
                const SizedBox(height: 9),
                Expanded(
                    child: Row(children: <Widget>[
                  Expanded(
                      child: _moduleCard(
                          title: 'Subir pendientes',
                          subtitle: '$pendientes pendientes',
                          icon: Icons.sync_rounded,
                          accent: warning,
                          onTap: () => _abrir('/sync'))),
                  const SizedBox(width: 9),
                  Expanded(
                      child: _moduleCard(
                          title: 'Mapa de la planta',
                          subtitle: 'Ubicar equipos',
                          icon: Icons.map_outlined,
                          accent: const Color(0xFF8AB4F8),
                          onTap: () => _abrir('/mapa'))),
                ])),
              ])),
        ]),
      );

  Widget _moduleCard(
          {required String title,
          required String subtitle,
          required IconData icon,
          required Color accent,
          required VoidCallback onTap,
          bool large = false}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              decoration: BoxDecoration(
                  color: esterThemeController.isDark
                      ? const Color(0xFF111D35)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: accent.withValues(alpha: .48)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: accent.withValues(alpha: .12), blurRadius: 14)
                  ]),
              child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(children: <Widget>[
                    Align(
                        alignment: Alignment.topLeft,
                        // cuerpoFuerte y no seccion: estas fichas son estrechas
                        // y a 15 los titulos de dos palabras partian en dos
                        // lineas, empujando el icono y el pie de la tarjeta.
                        child: Text(title,
                            maxLines: 2,
                            style: AppText.cuerpoFuerte.copyWith(
                                color: esterThemeController.isDark
                                    ? texto
                                    : const Color(0xFF111827)))),
                    Expanded(
                        child: Center(
                            child: Icon(icon,
                                size: large ? 92 : 48, color: accent))),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: AppText.subtitulo
                            .copyWith(color: accent.withValues(alpha: .82))),
                  ])),
            )),
      );

  Widget _glassCard({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: esterThemeController.isDark
                ? const Color(0xFF111D35)
                : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: esterThemeController.isDark
                    ? const Color(0xFF314565)
                    : const Color(0xFFE2E8F0)),
            boxShadow: <BoxShadow>[
              BoxShadow(color: verde.withValues(alpha: .08), blurRadius: 14)
            ]),
        child: child,
      );

  Widget _miniBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .38))),
        child: Text(label, style: AppText.micro.copyWith(color: color)),
      );

  /// Los ultimos trabajos que ya subieron a la planta.
  ///
  /// Ocupa el sitio donde antes iba la ruta de trabajo. La ruta repetia lo
  /// que ya ofrecen las tarjetas de arriba —llevaba a la misma pantalla—,
  /// mientras que esto no estaba en ningun lado: hasta ahora la app decia lo
  /// que faltaba subir, pero nunca confirmaba lo que llego. El tecnico
  /// sincronizaba y su trabajo desaparecia de la pantalla.
  Widget _notaCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Text('Recientes', style: AppText.seccion.copyWith(color: texto)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('ya subidos a la planta',
                style: AppText.apoyo.copyWith(color: texto2)),
          ),
          InkWell(
            onTap: () => _abrir('/mediciones'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Ver historial',
                  style: AppText.apoyo.copyWith(color: verde)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (recientes.isEmpty)
          _card(
              child: Row(children: <Widget>[
            Icon(Icons.cloud_off_rounded, color: texto2),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    'Todavía no hay trabajos subidos. Lo que captures aparece '
                    'aquí después de sincronizar.',
                    style: AppText.apoyo.copyWith(color: texto2))),
          ]))
        else
          ...recientes.map(_filaReciente),
      ],
    );
  }

  /// Abre la vista previa del trabajo tocado.
  ///
  /// Lleva a la misma pantalla que el boton "Reportes e historial" del
  /// equipo, y no a una vista nueva: es donde el tecnico ya sabe leer sus
  /// mediciones, con las tablas por servicio y la ficha del equipo. Una
  /// segunda forma de mostrar lo mismo solo habria que mantenerla dos veces.
  Future<void> _abrirReciente(ServicioReciente servicio, Equipo? equipo) async {
    if (servicio.tipo == TipoServicio.blackStart) {
      // El black start no cuelga de ningun equipo del inventario, asi que su
      // historial vive en su propia pantalla.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BlackStartScreen()),
      );
      return;
    }
    if (equipo == null) {
      // El equipo no esta en el catalogo de la tablet: puede haberse
      // registrado en planta y aun no haber bajado. El historial general si
      // muestra el registro.
      _abrir('/mediciones');
      return;
    }
    if (servicio.tipo == TipoServicio.limpiezaPlato) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HistorialLimpiezaPlatoScreen(equipo: equipo)));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EquipmentHistoryScreen(equipo: equipo),
      ),
    );
  }

  Widget _filaReciente(ServicioReciente servicio) {
    // El nombre sale de los equipos que el inicio ya tiene cargados, en vez
    // de consultarlo: son cuatro filas y la lista esta ahi al lado.
    final equipo = servicio.localizacion == null
        ? null
        : equipos
            .where((e) => e.localizacion == servicio.localizacion)
            .firstOrNull;
    final donde = equipo != null
        ? '${equipo.equipo} · LOC-${servicio.localizacion}'
        : servicio.localizacion != null
            ? 'LOC-${servicio.localizacion}'
            : 'Generador de arranque en negro';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _abrirReciente(servicio, equipo),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: esterThemeController.isDark
                ? const Color(0xFF111D35)
                : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border:
                Border.all(color: servicio.tipo.color.withValues(alpha: .22)),
          ),
          child: Row(children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: servicio.tipo.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(servicio.tipo.icono,
                  size: 19, color: servicio.tipo.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(servicio.tipo.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cuerpoFuerte.copyWith(color: texto)),
                  const SizedBox(height: 2),
                  Text(donde,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.apoyo.copyWith(color: texto2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                const Icon(Icons.cloud_done_rounded,
                    size: 15, color: Color(0xFF00B89C)),
                const SizedBox(height: 3),
                Text(servicio.cuando,
                    style: AppText.micro.copyWith(color: texto2)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esterThemeController.isDark
            ? const Color(0xFF111D35)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: verde.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
