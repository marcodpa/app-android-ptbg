import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/widgets.dart';
import '../widgets/editor_servicio.dart';
import '../widgets/industrial_navigation.dart';
import '../db/db_helper.dart';
import '../models/equipo_visual_config.dart';
import '../models/lubrication_plan.dart';
import '../models/temperature_plan.dart';
import '../models/models.dart';
import '../models/compatibilidad_equipos.dart';
import '../models/checklist_black_start.dart';
import '../models/checklist_compresor.dart';
import '../models/equipo_nuevo.dart';
import '../models/orden_reparacion.dart';
import '../models/replacement_request.dart';
import '../models/temperature_measurement.dart';
import '../models/lubrication_measurement.dart';
import '../models/ajuste_correa.dart';
import '../models/limpieza_plato.dart';
import '../models/coupling_change.dart';
import '../models/sesion.dart';
import '../models/usb_sync_status.dart';
import '../services/equipo_service.dart';
import '../services/equipment_report_service.dart';
import '../services/print_service.dart';
import 'alignment_capture_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<MedicionLocal> _pendientes = [];
  List<TemperatureMeasurement> _temperaturePendientes = [];
  List<ReplacementLocalOperation> _replacementPendientes = [];
  List<AlignmentMeasurement> _alignmentPendientes = [];
  List<LubricationMeasurement> _lubricationPendientes = [];
  List<CouplingChange> _couplingPendientes = [];
  List<AjusteCorrea> _correaPendientes = [];
  List<LimpiezaPlato> _platoPendientes = [];
  // Cambios de estatus/ubicacion de piezas hechos en el inventario. Sin
  // mostrarlos aqui el tecnico no tiene forma de saber que quedaron por subir.
  List<Map<String, dynamic>> _estadoPendientes = [];
  // Ordenes de reparacion creadas o cerradas aqui que aun no han subido. Van
  // en la misma lista que las mediciones porque para el tecnico son el mismo
  // trabajo: algo que hizo en planta y que todavia no llego al servidor.
  List<OrdenReparacion> _ordenPendientes = [];
  // Equipos dados de alta en campo. Van aqui porque hasta que suben, el equipo
  // no se puede medir: es el pendiente que mas bloquea al tecnico.
  List<EquipoNuevo> _equipoPendientes = [];
  // Check list de compresores. Van con el resto de pendientes porque para el
  // tecnico son el mismo trabajo: algo hecho en planta que aun no subio.
  List<ChecklistCompresor> _checklistPendientes = [];
  List<ChecklistBlackStart> _blackStartPendientes = [];
  bool _loading = true;
  bool _downloading = false, _usbRequesting = false;
  bool _printing = false;
  // Corregir un trabajo pendiente es potestad del administrador: para el
  // mecanico el lapiz ni se dibuja. Lo que salio mal se elimina y se vuelve
  // a capturar, con la hora real.
  bool _esAdmin = false;
  int _hoy = 0, _errores = 0;
  String _dlMsg = '';
  String? _ultimaSync, _ultimaDescarga;
  UsbSyncStatus _usbStatus = UsbSyncStatus.fromValues(
    status: null,
    serial: null,
    detail: null,
    lastSeen: null,
    now: DateTime.now(),
  );
  Timer? _usbStatusTimer;

  int get _pendingTotal =>
      _pendientes.length +
      _temperaturePendientes.length +
      _replacementPendientes.length +
      _alignmentPendientes.length +
      _lubricationPendientes.length +
      _couplingPendientes.length +
      _correaPendientes.length +
      _platoPendientes.length +
      _estadoPendientes.length +
      _ordenPendientes.length +
      _equipoPendientes.length +
      _checklistPendientes.length +
      _blackStartPendientes.length;

  int get _visiblePendingTotal =>
      (_pendientes.length > 4 ? 4 : _pendientes.length) +
      (_temperaturePendientes.length > 4 ? 4 : _temperaturePendientes.length) +
      (_replacementPendientes.length > 4 ? 4 : _replacementPendientes.length) +
      (_alignmentPendientes.length > 4 ? 4 : _alignmentPendientes.length) +
      (_lubricationPendientes.length > 4 ? 4 : _lubricationPendientes.length) +
      (_couplingPendientes.length > 4 ? 4 : _couplingPendientes.length) +
      (_correaPendientes.length > 4 ? 4 : _correaPendientes.length) +
      _platoPendientes.length +
      _estadoPendientes.length +
      _ordenPendientes.length +
      _equipoPendientes.length +
      _checklistPendientes.length +
      _blackStartPendientes.length;

  @override
  void initState() {
    super.initState();
    Sesion.esAdmin().then((admin) {
      if (mounted && admin) setState(() => _esAdmin = true);
    });
    _init();
    _usbStatusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadUsbStatus(),
    );
  }

  @override
  void dispose() {
    _usbStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ultimaSync = prefs.getString('ultima_sync');
      _ultimaDescarga = prefs.getString('ultima_descarga');
    });
    await _loadData();
    await _loadUsbStatus();
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
    if (status == _usbStatus) return;
    setState(() => _usbStatus = status);
  }

  /// Catalogo indexado por localizacion, cargado junto con los pendientes.
  Map<int, Equipo> _equiposPorLoc = const {};

  Future<void> _loadData() async {
    try {
      final pend = await DbHelper.instance.getPendientes();
      // El catalogo entero de una vez, para que cada fila pendiente resuelva
      // su nombre en memoria. Antes cada fila llevaba un FutureBuilder que
      // disparaba un SELECT con JOIN, y como el estado USB refresca cada 3
      // segundos, con 20 pendientes eran cientos de consultas por minuto y
      // los nombres parpadeaban en cada tick.
      final catalogo = await DbHelper.instance.getAllEquipos();
      final nombres = {
        for (final e in catalogo) e.localizacion: e,
      };
      final temperatures = await DbHelper.instance.getPendingTemperatures();
      final replacements = await DbHelper.instance.getPendingReplacements();
      final alignments = await DbHelper.instance.getPendingAlignments();
      final lubrications = await DbHelper.instance.getPendingLubrications();
      final coupling = await DbHelper.instance.getPendingCouplingChanges();
      final correas = await DbHelper.instance.getAjustesCorreaPendientes();
      final platos =
          await DbHelper.instance.getLimpiezasPlato(pendientes: true);
      final resumenPlatos = await DbHelper.instance.resumenLimpiezasPlato();
      final sinc = await DbHelper.instance.getSincronizadasHoy();
      final syncedTemperatures =
          await DbHelper.instance.countSyncedTemperaturesToday();
      final syncedReplacements =
          await DbHelper.instance.countSyncedReplacementsToday();
      final syncedAlignments =
          await DbHelper.instance.countSyncedAlignmentsToday();
      final syncedLubrications =
          await DbHelper.instance.countSyncedLubricationsToday();
      final syncedCoupling =
          await DbHelper.instance.countSyncedCouplingChangesToday();
      final errs = await DbHelper.instance.countErrores();
      final temperatureErrors =
          await DbHelper.instance.countTemperatureErrors();
      final replacementErrors =
          await DbHelper.instance.countReplacementErrors();
      final alignmentErrors = await DbHelper.instance.countAlignmentErrors();
      final lubricationErrors =
          await DbHelper.instance.countLubricationErrors();
      final couplingErrors =
          await DbHelper.instance.countCouplingChangeErrors();
      final estados = await DbHelper.instance.getPendingEstadoChanges();
      final ordenes = (await DbHelper.instance.getPendingOrdenesReparacion())
          .map(OrdenReparacion.fromMap)
          .toList(growable: false);
      final equiposNuevos = (await DbHelper.instance.getPendingEquiposNuevos())
          .map(EquipoNuevo.fromMap)
          .toList(growable: false);
      final checklists =
          (await DbHelper.instance.getPendingChecklistsCompresor())
              .map(ChecklistCompresor.fromMap)
              .toList(growable: false);
      final blackStart =
          (await DbHelper.instance.getPendingChecklistsBlackStart())
              .map(ChecklistBlackStart.fromMap)
              .toList(growable: false);
      // Al subir, una orden pasa a contar en el pendiente de la planta. Y el
      // punto rojo de la barra tiene que apagarse en cuanto no quede nada.
      await DbHelper.instance.refrescarAvisos();
      // Un equipo que acaba de bajar puede traer familia nueva: sin recargarla
      // el reemplazo seguiria sin ofrecerle piezas.
      CompatibilidadEquipos.cargarAsignadas(
        await DbHelper.instance.familiasAsignadas(),
      );
      if (mounted) {
        setState(() {
          _equiposPorLoc = nombres;
          _pendientes = pend;
          _temperaturePendientes = temperatures;
          _replacementPendientes = replacements;
          _alignmentPendientes = alignments;
          _lubricationPendientes = lubrications;
          _couplingPendientes = coupling;
          _correaPendientes = correas;
          _platoPendientes = platos;
          _estadoPendientes = estados;
          _ordenPendientes = ordenes;
          _equipoPendientes = equiposNuevos;
          _checklistPendientes = checklists;
          _blackStartPendientes = blackStart;
          _hoy = sinc.length +
              syncedTemperatures +
              syncedReplacements +
              syncedAlignments +
              syncedLubrications +
              syncedCoupling +
              (resumenPlatos['hoy'] ?? 0);
          _errores = errs +
              temperatureErrors +
              replacementErrors +
              alignmentErrors +
              lubricationErrors +
              couplingErrors +
              (resumenPlatos['errores'] ?? 0);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestUsbDownload() async {
    if (kIsWeb || _downloading || !_usbStatus.online) return;
    setState(() {
      _downloading = true;
      _dlMsg = 'Solicitando datos a la laptop por USB...';
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
        if (_usbStatus.requestId == requestId &&
            (_usbStatus.rawStatus == 'DONE' ||
                _usbStatus.rawStatus == 'ERROR')) {
          break;
        }
      }

      if (!mounted) return;
      if (_usbStatus.requestId == requestId && _usbStatus.rawStatus == 'DONE') {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().toIso8601String();
        await prefs.setString('ultima_descarga', now);
        await DbHelper.instance.reopenAfterUsbSync();
        EquipoService.instance.limpiarCache();
        await _loadData();
        setState(() {
          _ultimaDescarga = now;
          _dlMsg = 'Datos descargados correctamente por USB.';
        });
        _snack('Datos descargados desde MariaDB por USB.', AppColors.success);
      } else {
        throw Exception(_usbStatus.detail);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _dlMsg = 'Error: $e');
        _snack('Error al descargar por USB: $e', AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _requestUsbUpload() async {
    if (kIsWeb || _usbRequesting || !_usbStatus.online) return;

    final beforePending = List<MedicionLocal>.from(_pendientes);
    final beforeReplacementIds =
        _replacementPendientes.map((item) => item.operationUuid).toSet();
    final beforeAlignmentIds =
        _alignmentPendientes.map((item) => item.uuid).toSet();
    // El resto de los servicios tambien tiene planilla, y hasta ahora se
    // sincronizaban sin ofrecer imprimirla: quien media temperatura o
    // lubricacion terminaba imprimiendo equipo por equipo desde el catalogo.
    final antesTrabajos = _trabajosPendientesParaImprimir();
    setState(() => _usbRequesting = true);
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final file = File(
        '/data/data/com.example.scv_ptbg/files/usb_sync_request.json',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'id': requestId,
          'action': 'upload_pending',
          'created_at': DateTime.now().toIso8601String(),
        }),
      );

      _snack('Solicitud enviada a la laptop por USB.', AppColors.info);

      final deadline = DateTime.now().add(const Duration(seconds: 120));
      var completedByUsb = false;
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 2));
        await _loadUsbStatus();
        final state = _usbStatus.rawStatus;
        if (_usbStatus.requestId == requestId &&
            (state == 'DONE' || state == 'ERROR')) {
          completedByUsb = state == 'DONE';
          break;
        }
      }

      await _loadData();
      await _loadUsbStatus();

      if (!mounted) return;
      final ok = completedByUsb || _usbStatus.rawStatus == 'DONE';
      _snack(
        ok
            ? 'Sincronizacion USB finalizada.'
            : 'Revise el estado USB: ${_usbStatus.detail}',
        ok ? AppColors.success : AppColors.warning,
      );

      if (ok) {
        final afterPendingIds = _pendientes.map((m) => m.uuid).toSet();
        final uploaded = beforePending
            .where((m) => !afterPendingIds.contains(m.uuid))
            .toList();
        // Lo que dejo de estar pendiente es lo que subio. Se ofrece una
        // planilla por orden de trabajo, que es como se imprime en papel:
        // una hoja por ODT con todos los servicios que se le hicieron.
        final quedan =
            _trabajosPendientesParaImprimir().map((t) => t.clave).toSet();
        final subidos =
            antesTrabajos.where((t) => !quedan.contains(t.clave)).toList();
        if (subidos.isNotEmpty) {
          await _preguntarImprimirPlanillas(subidos);
        } else if (uploaded.isNotEmpty) {
          await _askPrintUploaded(uploaded);
        }
        final afterReplacementIds =
            _replacementPendientes.map((item) => item.operationUuid).toSet();
        final uploadedReplacements = beforeReplacementIds
            .where((id) => !afterReplacementIds.contains(id))
            .length;
        if (uploadedReplacements > 0) {
          _snack(
            '$uploadedReplacements reemplazo(s) sincronizado(s).',
            AppColors.success,
          );
        }
        final afterAlignmentIds =
            _alignmentPendientes.map((item) => item.uuid).toSet();
        final uploadedAlignments = beforeAlignmentIds
            .where((id) => !afterAlignmentIds.contains(id))
            .length;
        if (uploadedAlignments > 0) {
          _snack(
            '$uploadedAlignments alineación(es) sincronizada(s).',
            AppColors.success,
          );
        }
      }
    } catch (e) {
      _snack('No se pudo solicitar la subida USB: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _usbRequesting = false);
    }
  }

  /// Los trabajos pendientes que, una vez subidos, tienen planilla oficial.
  ///
  /// Antes solo se miraba la vibracion: quien sincronizaba temperatura,
  /// lubricacion o alineacion no recibia el ofrecimiento de imprimir y tenia
  /// que ir equipo por equipo desde el catalogo.
  List<_TrabajoImprimible> _trabajosPendientesParaImprimir() {
    final trabajos = <_TrabajoImprimible>[];
    void agregar(int loc, int? odt, String uuid, EquipmentReportType tipo) {
      trabajos.add(_TrabajoImprimible(
        localizacion: loc,
        odt: odt,
        uuid: uuid,
        servicio: tipo,
      ));
    }

    for (final m in _pendientes) {
      agregar(m.localizacion, m.odt, m.uuid, EquipmentReportType.vibration);
    }
    for (final m in _temperaturePendientes) {
      agregar(m.localizacion, m.odt, m.uuid, EquipmentReportType.temperature);
    }
    for (final m in _lubricationPendientes) {
      agregar(m.localizacion, m.odt, m.uuid, EquipmentReportType.lubrication);
    }
    for (final m in _alignmentPendientes) {
      agregar(m.localizacion, m.odt, m.uuid, EquipmentReportType.alignment);
    }
    return trabajos;
  }

  /// Ofrece imprimir la planilla oficial de cada orden que acaba de subir.
  ///
  /// Se agrupa por orden de trabajo porque asi es el papel: una hoja por ODT
  /// con todos los servicios que se le hicieron al equipo en esa visita.
  Future<void> _preguntarImprimirPlanillas(
    List<_TrabajoImprimible> subidos,
  ) async {
    if (!mounted || subidos.isEmpty) return;

    final porOrden = <String, _OrdenImprimible>{};
    for (final t in subidos) {
      porOrden
          .putIfAbsent(
            '${t.localizacion}|${t.odt ?? ""}',
            () => _OrdenImprimible(localizacion: t.localizacion, odt: t.odt),
          )
          .servicios
          .add(t.servicio);
    }
    final ordenes = porOrden.values.toList();
    final elegidas = <_OrdenImprimible>{...ordenes};

    final nombres = <int, String>{};
    for (final orden in ordenes) {
      final equipo = _equiposPorLoc[orden.localizacion];
      nombres[orden.localizacion] = equipo?.equipo.trim().isNotEmpty == true
          ? equipo!.equipo.trim()
          : 'LOC-${orden.localizacion}';
    }

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (hoja) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(hoja).size.height * 0.82,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppColors.shadowLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Row(children: [
                      const Icon(Icons.cloud_done_rounded,
                          color: AppColors.success),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          subidos.length == 1
                              ? '1 trabajo sincronizado'
                              : '${subidos.length} trabajos sincronizados',
                          style: AppText.titulo
                              .copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      ordenes.length == 1
                          ? 'Elige si quieres imprimir su planilla.'
                          : 'Elige de cuáles quieres imprimir la planilla. '
                              'Es una hoja por orden de trabajo.',
                      style: AppText.apoyo
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final orden in ordenes)
                          CheckboxListTile(
                            value: elegidas.contains(orden),
                            onChanged: (marcado) => update(() {
                              if (marcado == true) {
                                elegidas.add(orden);
                              } else {
                                elegidas.remove(orden);
                              }
                            }),
                            dense: true,
                            title: Text(
                              nombres[orden.localizacion] ?? '',
                              style: AppText.cuerpoFuerte
                                  .copyWith(color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              orden.odt == null
                                  ? orden.etiquetaServicios
                                  : '${orden.etiquetaServicios} · '
                                      'ODT ${orden.odt}',
                              style: AppText.apoyo
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(hoja, false),
                          child: const Text('Ahora no'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: elegidas.isEmpty
                              ? null
                              : () => Navigator.pop(hoja, true),
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('IMPRIMIR'),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmado != true || !mounted) return;
    final pedidas = ordenes.where(elegidas.contains).toList();
    var impresas = 0;
    for (final orden in pedidas) {
      if (!mounted) return;
      final equipo = _equiposPorLoc[orden.localizacion];
      if (equipo == null) continue;
      try {
        await EquipmentReportService.request(
          equipo: equipo,
          type: orden.servicios.first,
          types: orden.servicios,
          print: true,
          officialForm: true,
          odt: orden.odt,
        );
        impresas++;
      } catch (e) {
        // Si la laptop no respondio a una, tampoco respondera a las que
        // siguen: cada intento cuesta dos minutos de espera.
        _snack('No se pudo imprimir: $e', AppColors.error);
        break;
      }
    }
    if (!mounted || impresas == 0) return;
    _snack(
      impresas < pedidas.length
          ? 'Se enviaron $impresas de ${pedidas.length}. Revise la laptop.'
          : impresas == 1
              ? 'Planilla enviada a la laptop.'
              : '$impresas planillas enviadas a la laptop.',
      impresas < pedidas.length ? AppColors.warning : AppColors.success,
    );
  }

  /// Tras el sync, deja elegir de cuales de las mediciones subidas se imprime
  /// la planilla.
  ///
  /// Antes se imprimia siempre la primera y las demas se perdian en silencio.
  /// Se sincroniza todo de una sola pasada —la base viaja entera, no por
  /// equipo— y la impresion se decide despues, que es otro ritmo: depende del
  /// papel y de la impresora, no del cable.
  Future<void> _askPrintUploaded(List<MedicionLocal> uploaded) async {
    if (!mounted || uploaded.isEmpty) return;
    final elegidas = <MedicionLocal>{...uploaded};

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppColors.shadowLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_done_rounded,
                            color: AppColors.success),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            uploaded.length == 1
                                ? '1 medicion sincronizada'
                                : '${uploaded.length} mediciones sincronizadas',
                            style: AppText.titulo.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Elige de cuales quieres imprimir la planilla.',
                      style: AppText.cuerpo
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in uploaded)
                          CheckboxListTile(
                            dense: true,
                            activeColor: AppColors.teal,
                            value: elegidas.contains(m),
                            title: Text(
                              'LOC-${m.localizacion}  ${m.sistema}',
                              style: AppText.cuerpoFuerte,
                            ),
                            subtitle: Text('${m.fecha}  ${m.hora}'),
                            onChanged: (checked) => update(() {
                              checked == true
                                  ? elegidas.add(m)
                                  : elegidas.remove(m);
                            }),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            child: const Text('AHORA NO'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: elegidas.isEmpty
                                ? null
                                : () => Navigator.pop(sheetContext, true),
                            icon: const Icon(Icons.print_rounded),
                            label: Text(elegidas.length > 1
                                ? 'IMPRIMIR ${elegidas.length}'
                                : 'IMPRIMIR'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmado != true || !mounted) return;

    // En secuencia: la solicitud viaja por un unico archivo hacia la laptop y
    // printMeasurement espera su confirmacion antes de devolver.
    final pedidas = uploaded.where(elegidas.contains).toList();
    var impresas = 0;
    for (final m in pedidas) {
      if (!mounted) return;
      final ok = await _printLocalMeasurement(m, silencioso: true);
      if (!ok) {
        // Si la laptop no respondio a una, tampoco va a responder a las
        // siguientes: cada intento cuesta dos minutos de espera.
        break;
      }
      impresas++;
    }
    if (!mounted) return;
    if (impresas == 0) return; // el error ya se mostro
    _snack(
      impresas < pedidas.length
          ? 'Se imprimieron $impresas de ${pedidas.length}. Revise la laptop.'
          : impresas == 1
              ? 'Planilla enviada a la laptop.'
              : '$impresas planillas enviadas a la laptop.',
      impresas < pedidas.length ? AppColors.warning : AppColors.success,
    );
  }

  /// [silencioso] evita los avisos por medicion cuando se imprimen varias
  /// seguidas: el resumen lo da quien llama al terminar.
  /// Devuelve true si la laptop confirmo la impresion.
  Future<bool> _printLocalMeasurement(
    MedicionLocal m, {
    bool silencioso = false,
  }) async {
    if (_printing) {
      _snack('Ya hay una impresion en proceso.', AppColors.warning);
      return false;
    }
    setState(() => _printing = true);
    if (!silencioso) {
      _snack('Enviando impresion a la laptop...', AppColors.accent);
    }
    try {
      final equipo = await DbHelper.instance.getEquipoByLocalizacion(
        m.localizacion,
      );
      final info = await DbHelper.instance.getEquipoInfo(m.localizacion);
      final printEquipo = equipo ??
          Equipo(
            id: m.localizacion,
            codeSys: 0,
            equipo: m.sistema,
            localizacion: m.localizacion,
            qrCode: m.localizacion.toString(),
            puntos: 0,
            ptEq: 1,
            sistema: m.sistema,
          );

      await MedicionPrintService.printMeasurement(
        data: MedicionPrintData(
          localizacion: m.localizacion,
          fecha: m.fecha,
          hora: m.hora,
          valores: m.valores,
          rms: m.rms,
          observaciones: m.observaciones,
          equipoNombre: printEquipo.equipo,
          tag: printEquipo.qrDisplay,
          sistema: m.sistema,
          subsistema: printEquipo.subsistema,
          responsable: m.responsable,
          cargo: m.cargo,
        ),
        equipo: printEquipo,
        info: info ?? printEquipo.info,
      );
      if (!silencioso) {
        _snack('Solicitud de impresion enviada.', AppColors.success);
      }
      return true;
    } catch (e) {
      _snack('No se pudo imprimir: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
    return false;
  }

  Future<void> _confirmDeleteEstado(Map<String, dynamic> cambio) async {
    final serial = (cambio['serial'] ?? '').toString();
    final ok = await confirmar(
      context,
      titulo: 'Descartar cambio de estatus',
      mensaje: 'Se descartará el cambio a ${cambio['estado']} de '
          '${_nombreTipoPieza(cambio['tipo']).toLowerCase()} $serial.\n\n'
          'No se subirá a MariaDB. Si la pieza existe y quieres registrarlo, '
          'vuelve a cambiarle el estatus desde el inventario.',
      textoConfirmar: 'DESCARTAR',
      destructivo: true,
    );
    if (!ok || !mounted) return;
    await DbHelper.instance
        .deleteEstadoChange((cambio['uuid'] ?? '').toString());
    if (!mounted) return;
    await _loadData();
    _snack('Cambio de estatus descartado.', AppColors.warning);
  }

  /// Descarta un equipo dado de alta aqui que aun no ha subido.
  ///
  /// Borra tambien el equipo de la lista visible: si se descarta el registro,
  /// no puede quedar un equipo fantasma que la planta no conoce.
  Future<void> _confirmDeleteEquipo(EquipoNuevo equipo) async {
    final ok = await confirmar(
      context,
      titulo: 'Descartar equipo nuevo',
      mensaje: 'Se borrará el registro de ${equipo.titulo} '
          '(LOC-${equipo.localizacion}) y desaparecerá de la lista de equipos.'
          '\n\nTodavía no ha subido, así que no queda rastro en MariaDB. '
          'Habría que registrarlo de nuevo desde cero.',
      textoConfirmar: 'DESCARTAR',
      destructivo: true,
    );
    if (!ok || !mounted) return;
    await DbHelper.instance.deleteEquipoNuevo(equipo.uuid);
    EquipoService.instance.limpiarCache();
    if (!mounted) return;
    await _loadData();
    _snack('Equipo descartado.', AppColors.warning);
  }

  /// Descarta una orden que nunca salio de la tablet.
  ///
  /// Solo se ofrece para ordenes abiertas sin enviar: el cierre de una orden
  /// que ya subio no se puede tirar desde aqui sin dejar la pieza congelada
  /// EN REPARACION en el resto de las tablets.
  Future<void> _confirmDeleteOrden(OrdenReparacion orden) async {
    final ok = await confirmar(
      context,
      titulo: 'Descartar orden de reparación',
      mensaje: 'Se borrará la orden de ${orden.nombreTipo.toLowerCase()} '
          '${orden.serial} hacia ${orden.destino}.\n\n'
          'Todavía no ha subido, así que no queda rastro en MariaDB. Si la '
          'pieza sí salió de planta, vuelve a crearla desde Componentes de '
          'equipos.',
      textoConfirmar: 'DESCARTAR',
      destructivo: true,
    );
    if (!ok || !mounted) return;
    await DbHelper.instance.deleteOrdenReparacion(orden.uuid);
    if (!mounted) return;
    await _loadData();
    _snack('Orden descartada.', AppColors.warning);
  }

  /// 1 Motor, 2 Bomba, 3 Caja, 4 Ventilador.
  String _nombreTipoPieza(Object? tipo) {
    switch (int.tryParse('${tipo ?? ''}') ?? 0) {
      case 1:
        return 'Motor';
      case 2:
        return 'Bomba';
      case 3:
        return 'Caja';
      case 4:
        return 'Ventilador';
      default:
        return 'Pieza';
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    avisar(context, msg, color);
  }

  Future<void> _confirmDelete(MedicionLocal m) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar medición',
      mensaje: 'LOC-${m.localizacion} - ${m.fecha} ${m.hora}\n\n'
          'Esta medición pendiente se quitará de la tablet y no se enviará a MariaDB.',
      textoConfirmar: 'ELIMINAR',
      destructivo: true,
    );

    if (!ok) return;
    await DbHelper.instance.deleteMedicionLocal(m.uuid);
    await _loadData();
    _snack('Medición eliminada de pendientes', AppColors.warning);
  }

  Future<void> _confirmDeleteTemperature(
    TemperatureMeasurement measurement,
  ) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar temperatura',
      mensaje: 'LOC-${measurement.localizacion} - '
          '${measurement.fecha} ${measurement.hora}\n\n'
          'Esta medición pendiente se quitará de la tablet y no se enviará a MariaDB.',
      textoConfirmar: 'ELIMINAR',
      destructivo: true,
    );

    if (!ok) return;
    await DbHelper.instance.deleteTemperature(measurement.uuid);
    await _loadData();
    _snack('Temperatura eliminada de pendientes', AppColors.warning);
  }

  Future<void> _confirmDeleteReplacement(
    ReplacementLocalOperation operation,
  ) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar reemplazo',
      mensaje:
          'LOC-${operation.localizacion} - ${operation.fecha} ${operation.hora}\n\n'
          'Se eliminará ${operation.componentLabels.join(', ')} de los pendientes y no se enviará a MariaDB.',
      textoConfirmar: 'ELIMINAR',
      destructivo: true,
    );
    if (!ok) return;
    await DbHelper.instance.deleteReplacementOperation(operation.operationUuid);
    await _loadData();
    _snack('Reemplazo eliminado de pendientes', AppColors.warning);
  }

  Future<void> _confirmDeleteAlignment(AlignmentMeasurement measurement) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar alineación',
      mensaje: 'LOC-${measurement.localizacion} - '
          '${measurement.fecha} ${measurement.hora}\n\n'
          'Esta alineación pendiente se quitará de la tablet y no se enviará a MariaDB.',
      textoConfirmar: 'ELIMINAR',
      destructivo: true,
    );
    if (!ok) return;
    await DbHelper.instance.deleteAlignment(measurement.uuid);
    await _loadData();
    _snack('Alineación eliminada de pendientes', AppColors.warning);
  }

  /// Deja en la bitacora que el administrador corrigio un trabajo pendiente
  /// y exactamente que cambio. Si no cambio nada, no ensucia el registro.
  Future<void> _registrarEdicion({
    required String servicio,
    required int localizacion,
    required String uuid,
    required Map<String, Object?> antes,
    required Map<String, Object?> despues,
  }) async {
    final cambios = resumenCambios(antes, despues);
    if (cambios.isEmpty) return;
    try {
      await DbHelper.instance.registrarEventoAdmin(
        usuario: await Sesion.usuarioActual(),
        cargo: await Sesion.cargoActual(),
        accion: 'EDICIÓN',
        servicio: servicio,
        localizacion: localizacion,
        uuidMedicion: uuid,
        detalle: cambios,
      );
    } catch (_) {}
  }

  Future<void> _editAlignment(AlignmentMeasurement measurement) async {
    var equipment = await DbHelper.instance.getEquipoByLocalizacion(
      measurement.localizacion,
    );
    equipment ??= Equipo(
      id: measurement.localizacion,
      codeSys: 0,
      equipo: measurement.sistema,
      localizacion: measurement.localizacion,
      puntos: measurement.puntos,
      ptEq: measurement.puntos,
      sistema: measurement.sistema,
      info: EquipoInfo(
        localizacion: measurement.localizacion,
        marca: measurement.marca,
        modelo: measurement.modelo,
        serial: measurement.serial,
      ),
    );
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => AlignmentCaptureScreen(
          equipo: equipment!,
          measurementToEdit: measurement,
        ),
      ),
    );
    if (changed == true) {
      await _loadData();
      _snack('Alineación actualizada en la tablet', AppColors.success);
    }
  }

  Future<void> _editReplacement(ReplacementLocalOperation operation) async {
    final controllers = {
      for (final item in operation.components)
        item.uuid: _PendingReplacementFields(item),
    };
    final equipo = await DbHelper.instance.getEquipoByLocalizacion(
      operation.localizacion,
    );
    if (!mounted) {
      for (final fields in controllers.values) {
        fields.dispose();
      }
      return;
    }

    try {
      // Misma hoja que el editor de mediciones. Antes esto era un AlertDialog
      // con estilo claro en medio de una app oscura: se veia como si fuera de
      // otro programa.
      final save = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (hoja) => HojaEditor(
          icono: Icons.build_circle_outlined,
          titulo: 'Reemplazo LOC-${operation.localizacion}',
          subtitulo: '${equipo?.equipo ?? 'Reemplazo'} · '
              '${operation.fecha} ${operation.hora}',
          onGuardar: () {
            final completo = controllers.values.every(
              (fields) =>
                  fields.brand.text.trim().isNotEmpty &&
                  fields.model.text.trim().isNotEmpty &&
                  fields.serial.text.trim().isNotEmpty,
            );
            if (!completo) {
              _snack(
                'Marca, modelo y serial son obligatorios.',
                AppColors.error,
              );
              return;
            }
            Navigator.pop(hoja, true);
          },
          hijos: [
            for (final item in operation.components) ...[
              TituloSeccion(replacementComponentLabel(item.component)),
              const SizedBox(height: 9),
              _campoReemplazo(controllers[item.uuid]!.brand, 'Marca'),
              const SizedBox(height: 9),
              _campoReemplazo(controllers[item.uuid]!.model, 'Modelo'),
              const SizedBox(height: 9),
              _campoReemplazo(controllers[item.uuid]!.serial, 'Serial'),
              if (controllers[item.uuid]!.technicalFields.isNotEmpty) ...[
                const SizedBox(height: 16),
                const TituloSeccion('Especificaciones técnicas'),
                const SizedBox(height: 9),
                for (final field
                    in controllers[item.uuid]!.technicalFields) ...[
                  _campoReemplazo(field.controller, field.label),
                  const SizedBox(height: 9),
                ],
              ],
              const SizedBox(height: 14),
            ],
          ],
        ),
      );

      if (save != true) return;
      await DbHelper.instance.updateReplacementOperation(operation, {
        for (final entry in controllers.entries)
          entry.key: entry.value.toData(),
      });
      await _registrarEdicion(
        servicio: 'reemplazo',
        localizacion: operation.localizacion,
        uuid: operation.operationUuid,
        antes: {
          for (final item in operation.components) ...{
            '${replacementComponentLabel(item.component)} marca': item.brand,
            '${replacementComponentLabel(item.component)} modelo': item.model,
            '${replacementComponentLabel(item.component)} serial': item.serial,
          },
        },
        despues: {
          for (final item in operation.components) ...{
            '${replacementComponentLabel(item.component)} marca':
                controllers[item.uuid]!.brand.text.trim(),
            '${replacementComponentLabel(item.component)} modelo':
                controllers[item.uuid]!.model.text.trim(),
            '${replacementComponentLabel(item.component)} serial':
                controllers[item.uuid]!.serial.text.trim(),
          },
        },
      );
      if (!mounted) return;
      await _loadData();
      _snack('Reemplazo actualizado en la tablet', AppColors.success);
    } finally {
      for (final fields in controllers.values) {
        fields.dispose();
      }
    }
  }

  Widget _campoReemplazo(TextEditingController controlador, String etiqueta) =>
      TextField(
        controller: controlador,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: etiqueta,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  /// Los puntos del equipo con lo que se le midio, para el editor.
  ///
  /// El nombre de cada punto sale del plan oficial del equipo, el mismo que
  /// usan la captura y el historial. Si el equipo no esta en el catalogo se
  /// cae a un nombre generico en vez de dejar el campo sin titulo.
  List<PuntoServicio> _puntosDeUnValor({
    required Map<String, double?> valores,
    required String prefijo,
    required String etiqueta,
    required Map<int, String> nombres,
  }) {
    int numero(String clave) => int.tryParse(clave.substring(1)) ?? 0;
    final claves = valores.keys.where((k) => k.startsWith(prefijo)).toList()
      ..sort((a, b) => numero(a).compareTo(numero(b)));
    return [
      for (final clave in claves)
        PuntoServicio(
          nombre: nombres[numero(clave)] ?? 'Punto ${numero(clave)}',
          campos: [
            CampoServicio(
              clave: clave,
              etiqueta: etiqueta,
              valor: valores[clave],
            ),
          ],
        ),
    ];
  }

  Future<void> _editTemperature(TemperatureMeasurement measurement) async {
    final equipo = await DbHelper.instance.getEquipoByLocalizacion(
      measurement.localizacion,
    );
    if (!mounted) return;
    final plan = TemperaturePlanResolver.fromPuntos(equipo?.ptEq ?? 0);
    final resultado = await editarServicio(
      context,
      icono: Icons.thermostat_rounded,
      titulo: 'Temperatura LOC-${measurement.localizacion}',
      subtitulo: '${equipo?.equipo ?? measurement.sistema} · '
          '${measurement.fecha} ${measurement.hora}',
      unidad: '°C',
      puntos: _puntosDeUnValor(
        valores: measurement.valores,
        prefijo: 'T',
        etiqueta: 'Temperatura',
        nombres: {for (final p in plan) p.dbPointNumber: p.label},
      ),
      observaciones: measurement.observaciones ?? '',
      responsable: measurement.responsable ?? '',
      cargo: measurement.cargo ?? '',
      odt: measurement.odt,
      fecha: measurement.fecha,
      hora: measurement.hora,
    );
    if (resultado == null || !mounted) return;
    await DbHelper.instance.updateTemperature(
      measurement.copyWith(
        fecha: resultado.fecha,
        hora: resultado.hora,
        valores: resultado.valores,
        observaciones: resultado.observaciones,
        responsable: resultado.responsable,
        cargo: resultado.cargo,
        odt: resultado.odt,
      ),
    );
    await _registrarEdicion(
      servicio: 'temperatura',
      localizacion: measurement.localizacion,
      uuid: measurement.uuid,
      antes: {
        ...measurement.valores,
        'fecha': '${measurement.fecha} ${measurement.hora}',
        'obs': measurement.observaciones,
        'responsable': measurement.responsable,
        'odt': measurement.odt,
      },
      despues: {
        'fecha': '${resultado.fecha} ${resultado.hora}',
        ...resultado.valores,
        'obs': resultado.observaciones,
        'responsable': resultado.responsable,
        'odt': resultado.odt,
      },
    );
    if (!mounted) return;
    await _loadData();
    _snack('Temperatura actualizada.', AppColors.success);
  }

  Future<void> _editLubrication(LubricationMeasurement measurement) async {
    final equipo = await DbHelper.instance.getEquipoByLocalizacion(
      measurement.localizacion,
    );
    if (!mounted) return;
    final plan = LubricationPlanResolver.fromPuntos(equipo?.ptEq ?? 0);
    final resultado = await editarServicio(
      context,
      icono: Icons.oil_barrel_rounded,
      titulo: 'Lubricación LOC-${measurement.localizacion}',
      subtitulo: '${equipo?.equipo ?? measurement.sistema} · '
          '${measurement.fecha} ${measurement.hora}',
      unidad: 'g',
      puntos: _puntosDeUnValor(
        valores: measurement.valores,
        prefijo: 'L',
        etiqueta: 'Gramos aplicados',
        nombres: {for (final p in plan) p.dbPointNumber: p.label},
      ),
      observaciones: measurement.observaciones ?? '',
      responsable: measurement.responsable ?? '',
      cargo: measurement.cargo ?? '',
      odt: measurement.odt,
      fecha: measurement.fecha,
      hora: measurement.hora,
    );
    if (resultado == null || !mounted) return;
    await DbHelper.instance.updateLubrication(
      measurement.copyWith(
        fecha: resultado.fecha,
        hora: resultado.hora,
        valores: resultado.valores,
        observaciones: resultado.observaciones,
        responsable: resultado.responsable,
        cargo: resultado.cargo,
        odt: resultado.odt,
      ),
    );
    await _registrarEdicion(
      servicio: 'lubricación',
      localizacion: measurement.localizacion,
      uuid: measurement.uuid,
      antes: {
        ...measurement.valores,
        'fecha': '${measurement.fecha} ${measurement.hora}',
        'obs': measurement.observaciones,
        'responsable': measurement.responsable,
        'odt': measurement.odt,
      },
      despues: {
        'fecha': '${resultado.fecha} ${resultado.hora}',
        ...resultado.valores,
        'obs': resultado.observaciones,
        'responsable': resultado.responsable,
        'odt': resultado.odt,
      },
    );
    if (!mounted) return;
    await _loadData();
    _snack('Lubricación actualizada.', AppColors.success);
  }

  Future<void> _editPending(MedicionLocal m) async {
    final equipo = await DbHelper.instance.getEquipoByLocalizacion(
      m.localizacion,
    );
    if (!mounted) return;

    // La vibracion mide tres ejes en cada punto, asi que los campos se
    // agrupan bajo el nombre del punto en vez de listar H1, V1, A1, H2...
    // sueltos, que es como se veian antes.
    final plan = equipo == null
        ? const <PuntoCapturaConfig>[]
        : PlanMedicionResolver.fromEquipo(equipo);
    const ejes = {'H': 'Horizontal', 'V': 'Vertical', 'A': 'Axial'};

    int numero(String clave) => int.tryParse(clave.substring(1)) ?? 0;
    final numeros = m.valores.keys.map(numero).toSet().toList()..sort();
    final nombres = {for (final p in plan) p.puntoDb: p.nombre};

    final puntos = <PuntoServicio>[
      for (final n in numeros)
        PuntoServicio(
          nombre: nombres[n] ?? 'Punto de medición $n',
          campos: [
            for (final eje in ejes.entries)
              if (m.valores.containsKey('${eje.key}$n'))
                CampoServicio(
                  clave: '${eje.key}$n',
                  etiqueta: eje.value,
                  valor: m.valores['${eje.key}$n'],
                ),
          ],
        ),
    ];

    final resultado = await editarServicio(
      context,
      icono: Icons.vibration_rounded,
      titulo: 'Vibración LOC-${m.localizacion}',
      subtitulo: '${equipo?.equipo ?? m.sistema} · ${m.fecha} ${m.hora}',
      unidad: 'mm/s',
      puntos: puntos,
      observaciones: m.observaciones ?? '',
      responsable: m.responsable ?? '',
      cargo: m.cargo ?? '',
      odt: m.odt,
      fecha: m.fecha,
      hora: m.hora,
    );
    if (resultado == null || !mounted) return;

    await DbHelper.instance.updateMedicionLocal(
      MedicionLocal(
        uuid: m.uuid,
        localizacion: m.localizacion,
        sistema: m.sistema,
        fecha: resultado.fecha,
        hora: resultado.hora,
        valores: resultado.valores,
        observaciones: resultado.observaciones,
        responsable: resultado.responsable,
        cargo: resultado.cargo,
        marca: m.marca,
        modelo: m.modelo,
        serial: m.serial,
        odt: resultado.odt,
        rms: m.rms,
        sincronizado: m.sincronizado,
        errorSync: m.errorSync,
      ),
    );
    await _registrarEdicion(
      servicio: 'vibración',
      localizacion: m.localizacion,
      uuid: m.uuid,
      antes: {
        ...m.valores,
        'fecha': '${m.fecha} ${m.hora}',
        'obs': m.observaciones,
        'responsable': m.responsable,
        'odt': m.odt,
      },
      despues: {
        'fecha': '${resultado.fecha} ${resultado.hora}',
        ...resultado.valores,
        'obs': resultado.observaciones,
        'responsable': resultado.responsable,
        'odt': resultado.odt,
      },
    );
    if (!mounted) return;
    await _loadData();
    _snack('Medición actualizada.', AppColors.success);
  }

  String _fmt(String iso) {
    try {
      return DateFormat("dd/MM/yyyy · HH:mm").format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return IndustrialShell(
        activeRoute: '/sync',
        child: Scaffold(
          backgroundColor: esterThemeController.isDark
              ? AppColors.bg
              : const Color(0xFFF7FAFE),
          body: const Column(children: [
            IndustrialContentHeader(
              title: 'Sincronización',
              subtitle: 'Descarga · Captura · Envía',
              icon: Icons.sync_rounded,
            ),
            Expanded(
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.teal))),
          ]),
        ),
      );
    }

    return IndustrialShell(
      activeRoute: '/sync',
      child: Scaffold(
        backgroundColor: esterThemeController.isDark
            ? AppColors.bg
            : const Color(0xFFF7FAFE),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const IndustrialContentHeader(
              title: 'Sincronización',
              subtitle: 'Descarga · Captura · Envía',
              icon: Icons.sync_rounded,
            ),
            // Conexión
            _UsbStatusBanner(status: _usbStatus),

            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    value: '$_pendingTotal',
                    label: 'PENDIENTES',
                    color: _pendingTotal == 0
                        ? AppColors.success
                        : AppColors.orange,
                    icon: Icons.cloud_upload_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    value: '$_hoy',
                    label: 'HOY',
                    color: AppColors.cyan,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    value: '$_errores',
                    label: 'ERRORES',
                    color: _errores > 0
                        ? AppColors.error
                        : AppColors.textSecondary,
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // PASO 1
            _StepCard(
              num: '01',
              title: 'Descargar datos',
              desc:
                  'Baja equipos, datos técnicos y lecturas mediante la laptop USB.',
              color: AppColors.cyan,
              children: [
                if (_ultimaDescarga != null)
                  _InfoChip(
                    icon: Icons.check_circle_outline_rounded,
                    text: 'Última descarga: ${_fmt(_ultimaDescarga!)}',
                    color: AppColors.success,
                  ),
                if (_dlMsg.isNotEmpty)
                  _InfoChip(
                    icon: Icons.info_outline_rounded,
                    text: _dlMsg,
                    color: AppColors.cyan,
                  ),
                const SizedBox(height: 12),
                GradBtn.cyan(
                  label: _downloading
                      ? _dlMsg
                      : !_usbStatus.online
                          ? 'Conecta la laptop por USB'
                          : 'Descargar equipos y lecturas',
                  icon: _downloading ? null : Icons.download_rounded,
                  loading: _downloading,
                  onTap: (!_usbStatus.online || _downloading)
                      ? null
                      : _requestUsbDownload,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // PASO 2
            _StepCard(
              num: '02',
              title: 'Capturar offline',
              desc:
                  'Trabaja en planta; todo se guarda localmente hasta conectar el USB.',
              color: AppColors.orange,
              children: [
                _InfoChip(
                  icon: Icons.pending_outlined,
                  text: '$_pendingTotal trabajos sin enviar',
                  color:
                      _pendingTotal == 0 ? AppColors.success : AppColors.orange,
                ),
                _InfoChip(
                  icon: Icons.check_circle_outline_rounded,
                  text: '$_hoy trabajos sincronizados hoy',
                  color: AppColors.success,
                ),
                if (_pendingTotal > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        ..._pendientes.map(
                          (m) => _PendRow(
                            m: m,
                            equipo: _equiposPorLoc[m.localizacion],
                            onEdit: _esAdmin ? () => _editPending(m) : null,
                            onDelete: () => _confirmDelete(m),
                          ),
                        ),
                        ..._temperaturePendientes.map(
                          (temperatura) => _FilaPendiente(
                            icono: Icons.thermostat_rounded,
                            color: AppColors.teal,
                            tipo: 'temperatura',
                            titulo:
                                'Temperatura LOC-${temperatura.localizacion}',
                            detalle: '${temperatura.fecha} ${temperatura.hora}',
                            error: temperatura.errorSync,
                            onEditar: _esAdmin
                                ? () => _editTemperature(temperatura)
                                : null,
                            onEliminar: () =>
                                _confirmDeleteTemperature(temperatura),
                          ),
                        ),
                        ..._replacementPendientes.map(
                          (operation) => _ReplacementPendRow(
                            operation: operation,
                            equipo: _equiposPorLoc[operation.localizacion],
                            onEdit: _esAdmin
                                ? () => _editReplacement(operation)
                                : null,
                            onDelete: () =>
                                _confirmDeleteReplacement(operation),
                          ),
                        ),
                        ..._alignmentPendientes.map(
                          (alignment) => _AlignmentPendRow(
                            measurement: alignment,
                            onEdit: _esAdmin
                                ? () => _editAlignment(alignment)
                                : null,
                            onDelete: () => _confirmDeleteAlignment(alignment),
                          ),
                        ),
                        ..._lubricationPendientes.map(
                          (lubricacion) => _FilaPendiente(
                            icono: Icons.oil_barrel_rounded,
                            color: AppColors.orange,
                            tipo: 'lubricación',
                            titulo:
                                'Lubricación LOC-${lubricacion.localizacion}',
                            detalle: '${lubricacion.fecha} ${lubricacion.hora}',
                            error: lubricacion.errorSync,
                            onEditar: _esAdmin
                                ? () => _editLubrication(lubricacion)
                                : null,
                            onEliminar: () async {
                              await DbHelper.instance
                                  .deleteLubrication(lubricacion.uuid);
                              await _loadData();
                            },
                          ),
                        ),
                        ..._couplingPendientes.map(
                          (cambio) => _FilaPendiente(
                            icono: Icons.settings_input_component_rounded,
                            color: AppColors.teal,
                            tipo: 'cambio de coupling',
                            titulo:
                                'Cambio de coupling LOC-${cambio.localizacion}',
                            detalle: '${cambio.fecha} ${cambio.hora}',
                            error: cambio.errorSync,
                            onEliminar: () async {
                              await DbHelper.instance
                                  .deleteCouplingChange(cambio.uuid);
                              await _loadData();
                            },
                          ),
                        ),
                        ..._platoPendientes.map((limpieza) => _FilaPendiente(
                              icono: Icons.cleaning_services_rounded,
                              color: AppColors.teal,
                              tipo: 'limpieza de plato',
                              titulo: 'Limpieza LOC-${limpieza.localizacion}',
                              detalle:
                                  '${limpieza.fecha} ${limpieza.hora} · ${limpieza.horasFuncionamiento} h · ODT ${limpieza.odt}',
                              error: limpieza.errorSync,
                              onEliminar: () async {
                                await DbHelper.instance
                                    .deleteLimpiezaPlato(limpieza.uuid);
                                await _loadData();
                              },
                            )),
                        ..._correaPendientes.map(
                          (ajuste) => _FilaPendiente(
                            icono: Icons.settings_backup_restore_rounded,
                            color: AppColors.orange,
                            tipo: 'ajuste de correa',
                            titulo:
                                'Ajuste de correa LOC-${ajuste.localizacion}',
                            detalle: '${ajuste.fecha} ${ajuste.hora} · '
                                '${ajuste.ajustada ? 'Ajustada' : 'Sin ajustar'}'
                                '${ajuste.tension == null ? '' : ' · tensión ${ajuste.tension}'}',
                            error: ajuste.errorSync,
                            onEliminar: () async {
                              await DbHelper.instance
                                  .deleteAjusteCorrea(ajuste.uuid);
                              await _loadData();
                            },
                          ),
                        ),
                        // Cambios de estatus del inventario. No se pueden
                        // editar desde aqui: se corrigen volviendo a cambiar
                        // el estatus de la pieza.
                        ..._estadoPendientes.map((cambio) {
                          final serial = (cambio['serial'] ?? '').toString();
                          final estado = (cambio['estado'] ?? '').toString();
                          final sitio =
                              (cambio['localizacion'] ?? '').toString();
                          return _FilaPendiente(
                            icono: Icons.inventory_2_rounded,
                            color: AppColors.cyan,
                            tipo: 'cambio de estatus',
                            titulo: '${_nombreTipoPieza(cambio['tipo'])} '
                                '$serial → $estado',
                            detalle: sitio.isEmpty
                                ? '${cambio['fecha']} ${cambio['hora']}'
                                : '$sitio · ${cambio['fecha']} '
                                    '${cambio['hora']}',
                            error: (cambio['error_sync'] ?? '').toString(),
                            onEliminar: () => _confirmDeleteEstado(cambio),
                          );
                        }),
                        ..._blackStartPendientes.map(
                          (checklist) => _FilaPendiente(
                            icono: Icons.bolt_rounded,
                            color: AppColors.orange,
                            tipo: 'check list',
                            titulo: 'Check list · Black start',
                            detalle: checklist.conforme
                                ? 'Todo apto · '
                                    '${checklist.fecha} ${checklist.hora}'
                                : '${checklist.noAptos} NO APTO · '
                                    '${checklist.fecha} ${checklist.hora}',
                            error: checklist.errorSync,
                            onEliminar: () async {
                              await DbHelper.instance
                                  .deleteChecklistBlackStart(checklist.uuid);
                              await _loadData();
                            },
                          ),
                        ),
                        ..._checklistPendientes.map(
                          (checklist) => _FilaPendiente(
                            icono: Icons.fact_check_rounded,
                            color: AppColors.orange,
                            tipo: 'check list',
                            titulo: 'Check list · ${checklist.equipo}',
                            detalle: checklist.conforme
                                ? 'Sin hallazgos · '
                                    '${checklist.fecha} ${checklist.hora}'
                                : '${checklist.hallazgos} en NO · '
                                    '${checklist.fecha} ${checklist.hora}',
                            error: checklist.errorSync,
                            onEliminar: () async {
                              await DbHelper.instance
                                  .deleteChecklistCompresor(checklist.uuid);
                              await _loadData();
                            },
                          ),
                        ),
                        // Equipos nuevos. Van primero porque son los que mas
                        // bloquean: hasta que suben no se puede medir el
                        // equipo ni imprimir su planilla.
                        ..._equipoPendientes.map(
                          (equipo) => _FilaPendiente(
                            icono: Icons.precision_manufacturing_rounded,
                            color: AppColors.orange,
                            tipo: 'equipo',
                            titulo: 'Equipo nuevo · ${equipo.titulo}',
                            detalle: 'LOC-${equipo.localizacion} · '
                                '${equipo.sistema} · '
                                '${equipo.fecha} ${equipo.hora}',
                            error: equipo.errorSync,
                            onEliminar: () => _confirmDeleteEquipo(equipo),
                          ),
                        ),
                        // Ordenes de reparacion. Se muestran todas, sin tope:
                        // hasta que suben, la orden no se puede finalizar, asi
                        // que esconder una detras de un "+3 mas" dejaria al
                        // tecnico sin saber que le falta subir.
                        ..._ordenPendientes.map((orden) {
                          final cierre = !orden.abierta;
                          return _FilaPendiente(
                            icono: cierre
                                ? Icons.task_alt_rounded
                                : Icons.build_circle_rounded,
                            color: AppColors.orange,
                            tipo: 'orden',
                            titulo: cierre
                                ? 'Cierre de orden · '
                                    '${orden.nombreTipo} ${orden.serial}'
                                : 'Orden de reparacion · '
                                    '${orden.nombreTipo} ${orden.serial}',
                            detalle: cierre
                                ? '${orden.resultado ?? ''} · '
                                    '${orden.fechaRetorno ?? ''} '
                                    '${orden.horaRetorno ?? ''}'
                                : '${orden.destino} · '
                                    '${orden.fechaSalida} '
                                    '${orden.horaSalida}',
                            error: orden.errorSync,
                            onEliminar: orden.puedeDescartarse
                                ? () => _confirmDeleteOrden(orden)
                                : null,
                          );
                        }),
                        if (_pendingTotal > _visiblePendingTotal)
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              '+ ${_pendingTotal - _visiblePendingTotal} mas...',
                              style: AppText.apoyo.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // PASO 3
            _StepCard(
              num: '03',
              title: 'Subir por USB',
              desc:
                  'Deja el programa USB abierto en la laptop y controla la subida desde la tablet.',
              color: AppColors.success,
              children: [
                if (_ultimaSync != null)
                  _InfoChip(
                    icon: Icons.cloud_done_outlined,
                    text: 'Último envío anterior: ${_fmt(_ultimaSync!)}',
                    color: AppColors.success,
                  ),
                const _InfoChip(
                  icon: Icons.usb_rounded,
                  text:
                      'El programa de la laptop puede estar minimizado; debe seguir abierto.',
                  color: AppColors.cyan,
                ),
                _InfoChip(
                  icon: _usbStatus.online
                      ? Icons.link_rounded
                      : Icons.link_off_rounded,
                  text: '${_usbStatus.label} · ${_usbStatus.detail}',
                  color:
                      _usbStatus.online ? AppColors.success : AppColors.error,
                ),
                _InfoChip(
                  icon: Icons.pending_actions_rounded,
                  text: '$_pendingTotal trabajos listos para subir',
                  color:
                      _pendingTotal == 0 ? AppColors.success : AppColors.orange,
                ),
                const SizedBox(height: 12),
                GradBtn.primary(
                  label: _usbRequesting
                      ? 'Subiendo desde laptop...'
                      : !_usbStatus.online
                          ? 'Conecta USB para subir'
                          : _pendingTotal == 0
                              ? 'Sin pendientes para subir'
                              : 'Sincronizar trabajos por USB',
                  icon: _usbRequesting ? null : Icons.cloud_upload_rounded,
                  loading: _usbRequesting,
                  onTap: (!_usbStatus.online ||
                          _usbRequesting ||
                          _pendingTotal == 0)
                      ? null
                      : _requestUsbUpload,
                ),
                if (_errores > 0) ...[
                  const SizedBox(height: 8),
                  GradBtn(
                    label: 'Limpiar $_errores errores locales',
                    icon: Icons.cleaning_services_rounded,
                    gradient: AppColors.gradError,
                    shadows: [
                      BoxShadow(
                        color: AppColors.error.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    onTap: () async {
                      await Future.wait([
                        DbHelper.instance.clearErrors(),
                        DbHelper.instance.clearTemperatureErrors(),
                        DbHelper.instance.clearReplacementErrors(),
                        DbHelper.instance.clearAlignmentErrors(),
                        DbHelper.instance.clearLubricationErrors(),
                      ]);
                      await _loadData();
                    },
                  ),
                ],
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.shadowSm,
          border: Border(bottom: BorderSide(color: color, width: 2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppText.display.copyWith(color: color),
            ),
            Text(
              label,
              style: AppText.micro.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

class _StepCard extends StatelessWidget {
  final String num, title, desc;
  final Color color;
  final List<Widget> children;
  const _StepCard({
    required this.num,
    required this.title,
    required this.desc,
    required this.color,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.shadowSm,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      num,
                      style: AppText.micro.copyWith(color: color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: AppText.seccion.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
}

class _UsbStatusBanner extends StatelessWidget {
  final UsbSyncStatus status;
  const _UsbStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.online ? AppColors.success : AppColors.error;
    final bg = status.online ? AppColors.successBg : AppColors.errorBg;
    final icon = status.online ? Icons.usb_rounded : Icons.usb_off_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        boxShadow: AppColors.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conexion USB laptop: ${status.label}',
                  style: AppText.seccion.copyWith(color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  status.detail,
                  style: AppText.apoyo.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendRow extends StatelessWidget {
  final MedicionLocal m;
  final Equipo? equipo;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _PendRow({
    required this.m,
    required this.equipo,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = equipo?.equipo.trim().isNotEmpty == true
        ? equipo!.equipo.trim()
        : m.sistema;
    final tag = equipo?.scada?.trim() ?? '';
    return _FilaPendiente(
      icono: Icons.vibration_rounded,
      color: AppColors.orange,
      tipo: 'medición',
      titulo: 'LOC-${m.localizacion} · $nombre',
      detalle: tag.isNotEmpty
          ? 'TAG: $tag · ${m.fecha}  ${m.hora}'
          : '${m.fecha}  ${m.hora}',
      error: m.errorSync,
      onEditar: onEdit,
      onEliminar: onDelete,
    );
  }
}

class _ReplacementPendRow extends StatelessWidget {
  const _ReplacementPendRow({
    required this.operation,
    required this.equipo,
    required this.onEdit,
    required this.onDelete,
  });

  final ReplacementLocalOperation operation;
  final Equipo? equipo;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final nombre = equipo?.equipo.trim();
    return _FilaPendiente(
      icono: Icons.build_circle_outlined,
      color: AppColors.cyan,
      tipo: 'reemplazo',
      titulo: 'LOC-${operation.localizacion} · '
          '${nombre?.isNotEmpty == true ? nombre : 'Reemplazo'}',
      detalle: '${operation.componentLabels.join(', ')} · '
          '${operation.fecha} ${operation.hora}',
      error: operation.hasError ? 'Error al subir' : null,
      onEditar: onEdit,
      onEliminar: onDelete,
    );
  }
}

class _AlignmentPendRow extends StatelessWidget {
  const _AlignmentPendRow({
    required this.measurement,
    required this.onEdit,
    required this.onDelete,
  });

  final AlignmentMeasurement measurement;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _FilaPendiente(
        icono: Icons.straighten_rounded,
        color: AppColors.teal,
        tipo: 'alineación',
        titulo: 'Alineación LOC-${measurement.localizacion}',
        detalle: '${measurement.fecha} ${measurement.hora}',
        error: measurement.errorSync,
        onEditar: onEdit,
        onEliminar: onDelete,
      );
}

/// Una linea de la lista de trabajos sin enviar.
///
/// La usan los once tipos de trabajo que pueden quedar pendientes, desde una
/// medicion de vibracion hasta una orden de reparacion, y por eso existe:
/// antes cada uno se dibujaba por su cuenta —tres con widgets propios y ocho
/// con ListTile crudo— y en la misma lista convivian tres tamanos de letra y
/// dos de icono. Leerla costaba porque nada se alineaba con nada.
///
/// Todos los tipos entran en la misma forma: cuadro de icono, titulo, una
/// linea de detalle y los botones de la derecha.
class _FilaPendiente extends StatelessWidget {
  const _FilaPendiente({
    required this.icono,
    required this.color,
    required this.tipo,
    required this.titulo,
    required this.detalle,
    this.error,
    this.onEditar,
    this.onEliminar,
  });

  final IconData icono;

  /// Color del cuadro del icono, para distinguir el tipo de trabajo de un
  /// vistazo sin cambiar la forma de la fila.
  final Color color;

  /// Como se llama esto en los tooltips: "Modificar {tipo}".
  final String tipo;

  final String titulo;
  final String detalle;

  /// El motivo por el que fallo al subir, si fallo.
  final String? error;

  /// Sin [onEditar] no se dibuja el lapiz. Hay trabajos que no se corrigen
  /// desde aqui: un cambio de estatus se arregla volviendo a cambiarlo, y una
  /// orden ya subida no se descarta.
  final VoidCallback? onEditar;
  final VoidCallback? onEliminar;

  static const _ladoIcono = 28.0;
  static const _tamIcono = 17.0;
  static const _tamBoton = 18.0;

  @override
  Widget build(BuildContext context) {
    final fallo = (error ?? '').trim();
    final conError = fallo.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: _ladoIcono,
            height: _ladoIcono,
            decoration: BoxDecoration(
              color:
                  (conError ? AppColors.error : color).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              icono,
              size: _tamIcono,
              color: conError ? AppColors.error : color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cuerpoFuerte
                      .copyWith(color: AppColors.textPrimary),
                ),
                Text(
                  conError ? fallo : detalle,
                  // El detalle normal ocupa una linea, para que todas las
                  // filas midan igual. El motivo de un fallo puede llevar
                  // dos: es lo que dice si vale la pena reintentar o
                  // descartarlo, y cortado a la mitad no sirve de nada.
                  maxLines: conError ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.apoyo.copyWith(
                    color: conError ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (conError)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ERR',
                style: AppText.micro.copyWith(color: AppColors.error),
              ),
            ),
          if (onEditar != null)
            IconButton(
              tooltip: 'Modificar $tipo',
              visualDensity: VisualDensity.compact,
              onPressed: onEditar,
              icon: const Icon(Icons.edit_rounded,
                  size: _tamBoton, color: AppColors.teal),
            ),
          if (onEliminar != null)
            IconButton(
              tooltip: 'Eliminar $tipo',
              visualDensity: VisualDensity.compact,
              onPressed: onEliminar,
              icon: const Icon(Icons.delete_outline_rounded,
                  size: _tamBoton, color: AppColors.error),
            ),
        ],
      ),
    );
  }
}

class _PendingReplacementFields {
  _PendingReplacementFields(ReplacementLocalItem item)
      : updateTechnicalSpecs = item.updateTechnicalSpecs,
        brand = TextEditingController(text: item.brand),
        model = TextEditingController(text: item.model),
        serial = TextEditingController(text: item.serial),
        voltage = TextEditingController(text: item.voltage),
        current = TextEditingController(text: item.current),
        rpm = TextEditingController(text: item.rpm),
        serviceFactor = TextEditingController(text: item.serviceFactor),
        horsepower = TextEditingController(text: item.horsepower),
        frame = TextEditingController(text: item.frame),
        driveBearing = TextEditingController(text: item.driveBearing),
        oppositeBearing = TextEditingController(text: item.oppositeBearing),
        cycle = TextEditingController(text: item.cycle),
        start = TextEditingController(text: item.start),
        phases = TextEditingController(text: item.phases),
        tension = TextEditingController(text: item.tension),
        lubrication = TextEditingController(text: item.lubrication);

  final bool updateTechnicalSpecs;
  final TextEditingController brand;
  final TextEditingController model;
  final TextEditingController serial;
  final TextEditingController voltage;
  final TextEditingController current;
  final TextEditingController rpm;
  final TextEditingController serviceFactor;
  final TextEditingController horsepower;
  final TextEditingController frame;
  final TextEditingController driveBearing;
  final TextEditingController oppositeBearing;
  final TextEditingController cycle;
  final TextEditingController start;
  final TextEditingController phases;
  final TextEditingController tension;
  final TextEditingController lubrication;

  List<({String label, TextEditingController controller})>
      get technicalFields => [
            (label: 'Voltaje nominal', controller: voltage),
            (label: 'Corriente / FLA', controller: current),
            (label: 'RPM', controller: rpm),
            (label: 'Factor de servicio (SF)', controller: serviceFactor),
            (label: 'Potencia (HP)', controller: horsepower),
            (label: 'Frame', controller: frame),
            (label: 'Rodamiento lado acople', controller: driveBearing),
            (label: 'Rodamiento lado libre', controller: oppositeBearing),
            (label: 'Ciclo / Hz', controller: cycle),
            (label: 'Tipo de arranque', controller: start),
            (label: 'Fases (PH)', controller: phases),
            (label: 'Tension', controller: tension),
            (label: 'Lubricacion', controller: lubrication),
          ];

  ReplacementData toData() => ReplacementData(
        brand: brand.text,
        model: model.text,
        serial: serial.text,
        updateTechnicalSpecs: updateTechnicalSpecs,
        voltage: voltage.text,
        current: current.text,
        rpm: rpm.text,
        serviceFactor: serviceFactor.text,
        horsepower: horsepower.text,
        frame: frame.text,
        driveBearing: driveBearing.text,
        oppositeBearing: oppositeBearing.text,
        cycle: cycle.text,
        start: start.text,
        phases: phases.text,
        tension: tension.text,
        lubrication: lubrication.text,
      );

  void dispose() {
    for (final controller in [
      brand,
      model,
      serial,
      ...technicalFields.map((field) => field.controller),
    ]) {
      controller.dispose();
    }
  }
}

/// Un trabajo subido que tiene planilla oficial que imprimir.
class _TrabajoImprimible {
  const _TrabajoImprimible({
    required this.localizacion,
    required this.odt,
    required this.uuid,
    required this.servicio,
  });

  final int localizacion;
  final int? odt;
  final String uuid;
  final EquipmentReportType servicio;

  /// Identifica el trabajo entre el antes y el despues del sync.
  String get clave => '${servicio.code}|$uuid';
}

/// Una orden de trabajo con los servicios que subieron para ella: es
/// exactamente una hoja de planilla.
class _OrdenImprimible {
  _OrdenImprimible({required this.localizacion, required this.odt});

  final int localizacion;
  final int? odt;
  final Set<EquipmentReportType> servicios = <EquipmentReportType>{};

  static const _nombres = <String, String>{
    'vibration': 'Vibración',
    'temperature': 'Temperatura',
    'lubrication': 'Lubricación',
    'alignment': 'Alineación',
  };

  String get etiquetaServicios =>
      servicios.map((s) => _nombres[s.code] ?? s.code).join(' · ');
}
