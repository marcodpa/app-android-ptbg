import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import '../db/db_helper.dart';
import '../models/measurement_editing.dart';
import '../models/models.dart';
import '../models/operation_flow.dart';
import '../models/replacement_request.dart';
import '../models/temperature_measurement.dart';
import '../models/usb_sync_status.dart';
import '../services/api_service.dart';
import '../services/equipo_service.dart';
import '../services/mediciones_service.dart';
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
  bool _loading = true, _online = false, _checking = false;
  bool _downloading = false, _usbRequesting = false;
  bool _printing = false;
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
      _alignmentPendientes.length;

  int get _visiblePendingTotal =>
      (_pendientes.length > 4 ? 4 : _pendientes.length) +
      (_temperaturePendientes.length > 4 ? 4 : _temperaturePendientes.length) +
      (_replacementPendientes.length > 4 ? 4 : _replacementPendientes.length) +
      (_alignmentPendientes.length > 4 ? 4 : _alignmentPendientes.length);

  @override
  void initState() {
    super.initState();
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
    await Future.wait([_checkOnline(), _loadData()]);
    await _loadUsbStatus();
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
    setState(() => _usbStatus = status);
  }

  Future<void> _checkOnline() async {
    setState(() => _checking = true);
    final ok = await ApiService.instance.checkConexion();
    if (mounted) {
      setState(() {
        _online = ok;
        _checking = false;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final pend = await DbHelper.instance.getPendientes();
      final temperatures = await DbHelper.instance.getPendingTemperatures();
      final replacements = await DbHelper.instance.getPendingReplacements();
      final alignments = await DbHelper.instance.getPendingAlignments();
      final sinc = await DbHelper.instance.getSincronizadasHoy();
      final syncedTemperatures =
          await DbHelper.instance.countSyncedTemperaturesToday();
      final syncedReplacements =
          await DbHelper.instance.countSyncedReplacementsToday();
      final syncedAlignments =
          await DbHelper.instance.countSyncedAlignmentsToday();
      final errs = await DbHelper.instance.countErrores();
      final temperatureErrors =
          await DbHelper.instance.countTemperatureErrors();
      final replacementErrors =
          await DbHelper.instance.countReplacementErrors();
      final alignmentErrors = await DbHelper.instance.countAlignmentErrors();
      if (mounted) {
        setState(() {
          _pendientes = pend;
          _temperaturePendientes = temperatures;
          _replacementPendientes = replacements;
          _alignmentPendientes = alignments;
          _hoy = sinc.length +
              syncedTemperatures +
              syncedReplacements +
              syncedAlignments;
          _errores =
              errs + temperatureErrors + replacementErrors + alignmentErrors;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _descargar() async {
    if (!_online || _downloading) return;

    setState(() {
      _downloading = true;
      _dlMsg = 'Descargando equipos…';
    });

    try {
      final equipos = await ApiService.instance.fetchEquipos();

      if (!kIsWeb) {
        await DbHelper.instance.upsertEquipos(equipos);
      }

      EquipoService.instance.limpiarCache();
      await EquipoService.instance.cargar(forceRefresh: false);

      if (mounted) {
        setState(() {
          _dlMsg =
              '✓ ${equipos.length} equipos · Descargando todas las mediciones…';
        });
      }

      int totalMediciones = 0;
      int lecturasOk = 0;

      try {
        // Descarga el histórico completo de MOT_VIBR_MUES. La tablet lo guarda
        // en SQLite y calcula por fecha/hora la última fila de cada equipo.
        final mediciones = await MedicionesService.instance.descargarTodas();
        totalMediciones = mediciones.length;
        lecturasOk = mediciones
            .where((m) => m.localizacion > 0)
            .map((m) => m.localizacion)
            .toSet()
            .length;

        if (!kIsWeb) {
          await DbHelper.instance.upsertMedicionesRemotas(
            mediciones,
            reemplazarTodo: true,
          );
        }
      } catch (_) {
        // Respaldo: si el endpoint histórico todavía no está disponible,
        // descargamos al menos la lectura más nueva de cada equipo.
        try {
          final ultimas =
              await MedicionesService.instance.descargarUltimasPorEquipo();
          lecturasOk = ultimas.length;
          totalMediciones = ultimas.length;
          if (!kIsWeb) {
            await DbHelper.instance.upsertMedicionesRemotas(ultimas);
          }
        } catch (_) {
          final ultimas = await ApiService.instance.fetchUltimasLecturas();
          for (final lectura in ultimas) {
            if (!kIsWeb) {
              await DbHelper.instance.upsertUltimaLectura(lectura);
            }
            lecturasOk++;
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      await prefs.setString('ultima_descarga', now);

      if (mounted) {
        setState(() {
          _ultimaDescarga = now;
          _downloading = false;
          _dlMsg = '✓ ${equipos.length} equipos · '
              '$totalMediciones mediciones · '
              '$lecturasOk equipos con lectura';
        });
      }

      _snack(
        '✓ Histórico y últimas lecturas guardados para trabajar offline.',
        AppColors.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _dlMsg = 'Error: $e';
        });
      }
      _snack('Error al descargar: $e', AppColors.error);
    }
  }

  Future<void> _requestUsbUpload() async {
    if (kIsWeb || _usbRequesting || !_usbStatus.online) return;

    final beforePending = List<MedicionLocal>.from(_pendientes);
    final beforeReplacementIds =
        _replacementPendientes.map((item) => item.operationUuid).toSet();
    final beforeAlignmentIds =
        _alignmentPendientes.map((item) => item.uuid).toSet();
    setState(() => _usbRequesting = true);
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final file =
          File('/data/data/com.example.scv_ptbg/files/usb_sync_request.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'id': requestId,
        'action': 'upload_pending',
        'created_at': DateTime.now().toIso8601String(),
      }));

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
        if (uploaded.isNotEmpty) {
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

  Future<void> _askPrintUploaded(List<MedicionLocal> uploaded) async {
    if (!mounted) return;
    final target = uploaded.first;
    final more = uploaded.length > 1
        ? '\n\nSe subieron ${uploaded.length} mediciones; se imprimira la primera.'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Medicion sincronizada'),
        content: Text(
          'La medicion LOC-${target.localizacion} ${target.fecha} ${target.hora} ya se subio a MariaDB.\n\n'
          'Quieres imprimir el formato de esta medicion?$more',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Imprimir'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await _printLocalMeasurement(target);
    }
  }

  Future<void> _printLocalMeasurement(MedicionLocal m) async {
    if (_printing) {
      _snack('Ya hay una impresion en proceso.', AppColors.warning);
      return;
    }
    setState(() => _printing = true);
    _snack('Enviando impresion a la laptop...', AppColors.accent);
    try {
      final equipo =
          await DbHelper.instance.getEquipoByLocalizacion(m.localizacion);
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
      _snack('Solicitud de impresion enviada.', AppColors.success);
    } catch (e) {
      _snack('No se pudo imprimir: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  Future<void> _confirmDelete(MedicionLocal m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar medicion'),
        content: Text(
          'LOC-${m.localizacion} - ${m.fecha} ${m.hora}\n\n'
          'Esta medicion pendiente se quitara de la tablet y no se enviara a MariaDB.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await DbHelper.instance.deleteMedicionLocal(m.uuid);
    await _loadData();
    _snack('Medicion eliminada de pendientes', AppColors.warning);
  }

  Future<void> _confirmDeleteReplacement(
    ReplacementLocalOperation operation,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar reemplazo'),
        content: Text(
          'LOC-${operation.localizacion} - ${operation.fecha} ${operation.hora}\n\n'
          'Se eliminara ${operation.componentLabels.join(', ')} de los pendientes y no se enviara a MariaDB.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DbHelper.instance.deleteReplacementOperation(operation.operationUuid);
    await _loadData();
    _snack('Reemplazo eliminado de pendientes', AppColors.warning);
  }

  Future<void> _confirmDeleteAlignment(
    AlignmentMeasurement measurement,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar alineación'),
        content: Text(
          'LOC-${measurement.localizacion} - '
          '${measurement.fecha} ${measurement.hora}\n\n'
          'Esta alineación pendiente se quitará de la tablet y no se enviará a MariaDB.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DbHelper.instance.deleteAlignment(measurement.uuid);
    await _loadData();
    _snack('Alineación eliminada de pendientes', AppColors.warning);
  }

  Future<void> _editAlignment(AlignmentMeasurement measurement) async {
    var equipment = await DbHelper.instance
        .getEquipoByLocalizacion(measurement.localizacion);
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

  Future<void> _editReplacement(
    ReplacementLocalOperation operation,
  ) async {
    final controllers = {
      for (final item in operation.components)
        item.uuid: _PendingReplacementFields(item),
    };

    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Editar reemplazo LOC-${operation.localizacion}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in operation.components) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        replacementComponentLabel(item.component),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.headerTop,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controllers[item.uuid]!.brand,
                      decoration: const InputDecoration(labelText: 'Marca'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controllers[item.uuid]!.model,
                      decoration: const InputDecoration(labelText: 'Modelo'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controllers[item.uuid]!.serial,
                      decoration: const InputDecoration(labelText: 'Serial'),
                    ),
                    if (item.component == ReplacementComponent.motor &&
                        item.updateTechnicalSpecs) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Especificaciones tecnicas',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.headerTop,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final field
                          in controllers[item.uuid]!.technicalFields) ...[
                        TextField(
                          controller: field.controller,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(labelText: field.label),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final complete = controllers.values.every(
                  (fields) =>
                      fields.brand.text.trim().isNotEmpty &&
                      fields.model.text.trim().isNotEmpty &&
                      fields.serial.text.trim().isNotEmpty,
                );
                if (!complete) {
                  _snack(
                    'Marca, modelo y serial son obligatorios.',
                    AppColors.error,
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar'),
            ),
          ],
        ),
      );

      if (save != true) return;
      await DbHelper.instance.updateReplacementOperation(
        operation,
        {
          for (final entry in controllers.entries)
            entry.key: entry.value.toData(),
        },
      );
      await _loadData();
      _snack('Reemplazo actualizado en la tablet', AppColors.success);
    } finally {
      for (final fields in controllers.values) {
        fields.dispose();
      }
    }
  }

  Future<void> _editPending(MedicionLocal m) async {
    final obsCtrl = TextEditingController(text: m.observaciones ?? '');
    final keys = m.valores.keys.toList()
      ..sort((a, b) {
        final ejeCmp = a.substring(0, 1).compareTo(b.substring(0, 1));
        if (ejeCmp != 0) return ejeCmp;
        final na = int.tryParse(a.substring(1)) ?? 0;
        final nb = int.tryParse(b.substring(1)) ?? 0;
        return na.compareTo(nb);
      });
    final controllers = {
      for (final key in keys)
        key: TextEditingController(
          text: m.valores[key]?.toStringAsFixed(2) ?? '',
        ),
    };

    try {
      final updated = await showModalBottomSheet<MedicionLocal>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
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
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note_rounded,
                              color: AppColors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Revisar LOC-${m.localizacion}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final key in keys)
                                SizedBox(
                                  width: 92,
                                  child: TextField(
                                    controller: controllers[key],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9\.,]')),
                                    ],
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      labelText: key,
                                      suffixText: 'mm/s',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: obsCtrl,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Observación general',
                              hintText: 'Nota general de la muestra',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Map<String, double?> valores;
                                try {
                                  valores = editedMeasurementValues(
                                    current: m.valores,
                                    edits: {
                                      for (final entry in controllers.entries)
                                        entry.key: entry.value.text,
                                    },
                                  );
                                } on FormatException {
                                  _snack(
                                    'Revise los valores: solo se permiten números.',
                                    AppColors.error,
                                  );
                                  return;
                                }
                                final rms = calculateRms(valores);
                                final obs =
                                    cleanGeneralObservation(obsCtrl.text);
                                Navigator.pop(
                                  context,
                                  MedicionLocal(
                                    uuid: m.uuid,
                                    localizacion: m.localizacion,
                                    sistema: m.sistema,
                                    fecha: m.fecha,
                                    hora: m.hora,
                                    valores: valores,
                                    rms: rms,
                                    observaciones: obs,
                                    responsable: m.responsable,
                                    cargo: m.cargo,
                                    marca: m.marca,
                                    modelo: m.modelo,
                                    serial: m.serial,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (updated == null) return;
      await DbHelper.instance.updateMedicionLocal(updated);
      await _loadData();
      _snack('Medicion actualizada en la tablet', AppColors.success);
    } finally {
      obsCtrl.dispose();
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
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
      return const Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppHeader(
          title: 'Sincronizacion',
          subtitle: 'Descarga - Captura - Envia',
        ),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.teal),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AppHeader(
          title: 'Sincronización', subtitle: 'Descarga · Captura · Envía'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Conexión
        ConnectionBanner(
            online: _online,
            checking: _checking,
            subtitle: _online ? 'Servidor activo' : 'Trabajando offline',
            onTap: _checkOnline),

        const SizedBox(height: 12),

        _UsbStatusBanner(status: _usbStatus),

        const SizedBox(height: 20),

        // Stats row
        Row(children: [
          Expanded(
              child: _StatTile(
                  value: '$_pendingTotal',
                  label: 'PENDIENTES',
                  color:
                      _pendingTotal == 0 ? AppColors.success : AppColors.orange,
                  icon: Icons.cloud_upload_outlined)),
          const SizedBox(width: 10),
          Expanded(
              child: _StatTile(
                  value: '$_hoy',
                  label: 'HOY',
                  color: AppColors.cyan,
                  icon: Icons.check_circle_outline_rounded)),
          const SizedBox(width: 10),
          Expanded(
              child: _StatTile(
                  value: '$_errores',
                  label: 'ERRORES',
                  color:
                      _errores > 0 ? AppColors.error : AppColors.textSecondary,
                  icon: Icons.warning_amber_rounded)),
        ]),

        const SizedBox(height: 24),

        // PASO 1
        _StepCard(
            num: '01',
            title: 'Descargar datos',
            desc: 'Baja equipos y lecturas anteriores para trabajar sin WiFi.',
            color: AppColors.cyan,
            children: [
              if (_ultimaDescarga != null)
                _InfoChip(
                    icon: Icons.check_circle_outline_rounded,
                    text: 'Última descarga: ${_fmt(_ultimaDescarga!)}',
                    color: AppColors.success),
              if (_dlMsg.isNotEmpty)
                _InfoChip(
                    icon: Icons.info_outline_rounded,
                    text: _dlMsg,
                    color: AppColors.cyan),
              const SizedBox(height: 12),
              GradBtn.cyan(
                  label: _downloading
                      ? _dlMsg
                      : !_online
                          ? 'Necesita conexión WiFi'
                          : 'Descargar equipos y lecturas',
                  icon: _downloading ? null : Icons.download_rounded,
                  loading: _downloading,
                  onTap: (!_online || _downloading) ? null : _descargar),
            ]),

        const SizedBox(height: 12),

        // PASO 2
        _StepCard(
            num: '02',
            title: 'Capturar offline',
            desc:
                'Desconectate del WiFi y salí a la planta. Todo se guarda en la tablet.',
            color: AppColors.orange,
            children: [
              _InfoChip(
                  icon: Icons.pending_outlined,
                  text: '$_pendingTotal trabajos sin enviar',
                  color: _pendingTotal == 0
                      ? AppColors.success
                      : AppColors.orange),
              _InfoChip(
                  icon: Icons.check_circle_outline_rounded,
                  text: '$_hoy trabajos sincronizados hoy',
                  color: AppColors.success),
              if (_pendingTotal > 0) ...[
                const SizedBox(height: 10),
                Container(
                    decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border)),
                    child: Column(children: [
                      ..._pendientes.take(4).map((m) => _PendRow(
                            m: m,
                            onEdit: () => _editPending(m),
                            onDelete: () => _confirmDelete(m),
                          )),
                      ..._temperaturePendientes.take(4).map(
                            (temperature) => ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.thermostat_rounded,
                                color: AppColors.teal,
                              ),
                              title: Text(
                                'Temperatura LOC-${temperature.localizacion}',
                              ),
                              subtitle: Text(
                                '${temperature.fecha} ${temperature.hora}',
                              ),
                              trailing: const Text('°C'),
                            ),
                          ),
                      ..._replacementPendientes.take(4).map(
                            (operation) => _ReplacementPendRow(
                              operation: operation,
                              onEdit: () => _editReplacement(operation),
                              onDelete: () =>
                                  _confirmDeleteReplacement(operation),
                            ),
                          ),
                      ..._alignmentPendientes.take(4).map(
                            (alignment) => _AlignmentPendRow(
                              measurement: alignment,
                              onEdit: () => _editAlignment(alignment),
                              onDelete: () =>
                                  _confirmDeleteAlignment(alignment),
                            ),
                          ),
                      if (_pendingTotal > _visiblePendingTotal)
                        Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                                '+ ${_pendingTotal - _visiblePendingTotal} mas...',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary))),
                    ])),
              ],
            ]),

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
                    color: AppColors.success),
              const _InfoChip(
                  icon: Icons.usb_rounded,
                  text:
                      'El programa de la laptop puede estar minimizado; debe seguir abierto.',
                  color: AppColors.cyan),
              _InfoChip(
                  icon: _usbStatus.online
                      ? Icons.link_rounded
                      : Icons.link_off_rounded,
                  text: '${_usbStatus.label} · ${_usbStatus.detail}',
                  color:
                      _usbStatus.online ? AppColors.success : AppColors.error),
              _InfoChip(
                  icon: Icons.pending_actions_rounded,
                  text: '$_pendingTotal trabajos listos para subir',
                  color: _pendingTotal == 0
                      ? AppColors.success
                      : AppColors.orange),
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
                      : _requestUsbUpload),
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
                          offset: const Offset(0, 4))
                    ],
                    onTap: () async {
                      await Future.wait([
                        DbHelper.instance.clearErrors(),
                        DbHelper.instance.clearTemperatureErrors(),
                        DbHelper.instance.clearReplacementErrors(),
                        DbHelper.instance.clearAlignmentErrors(),
                      ]);
                      await _loadData();
                    }),
              ],
            ]),

        const SizedBox(height: 40),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  final Color color;
  final IconData icon;
  const _StatTile(
      {required this.value,
      required this.label,
      required this.color,
      required this.icon});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.shadowSm,
          border: Border(bottom: BorderSide(color: color, width: 2))),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'monospace')),
        Text(label,
            style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      ]));
}

class _StepCard extends StatelessWidget {
  final String num, title, desc;
  final Color color;
  final List<Widget> children;
  const _StepCard(
      {required this.num,
      required this.title,
      required this.desc,
      required this.color,
      required this.children});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.shadowSm,
          border: Border(left: BorderSide(color: color, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Center(
                  child: Text(num,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace')))),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 4),
        Text(desc,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 12),
        ...children,
      ]));
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 7),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary))),
      ]));
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
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status.detail,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PendRow({
    required this.m,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Row(children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: m.errorSync != null ? AppColors.error : AppColors.orange,
                shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
            child: FutureBuilder<Equipo?>(
                future:
                    DbHelper.instance.getEquipoByLocalizacion(m.localizacion),
                builder: (context, snap) {
                  final eq = snap.data;
                  final nombre = eq?.equipo.trim().isNotEmpty == true
                      ? eq!.equipo.trim()
                      : m.sistema;
                  final tag = eq?.scada?.trim();
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LOC-${m.localizacion} · $nombre',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        Text(
                            tag != null && tag.isNotEmpty
                                ? 'TAG: $tag · ${m.fecha}  ${m.hora}'
                                : '${m.fecha}  ${m.hora}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontFamily: 'monospace')),
                      ]);
                })),
        if (m.errorSync != null)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('ERR',
                  style: TextStyle(
                      fontSize: 9,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700))),
        IconButton(
          tooltip: 'Modificar medicion',
          visualDensity: VisualDensity.compact,
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.teal),
        ),
        IconButton(
          tooltip: 'Eliminar medicion',
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: AppColors.error),
        ),
      ]));
}

class _ReplacementPendRow extends StatelessWidget {
  const _ReplacementPendRow({
    required this.operation,
    required this.onEdit,
    required this.onDelete,
  });

  final ReplacementLocalOperation operation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.build_circle_outlined,
              size: 17,
              color: AppColors.cyan,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<Equipo?>(
              future: DbHelper.instance
                  .getEquipoByLocalizacion(operation.localizacion),
              builder: (context, snapshot) {
                final equipment = snapshot.data?.equipo.trim();
                final components = operation.componentLabels.join(', ');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOC-${operation.localizacion} · ${equipment?.isNotEmpty == true ? equipment : 'Reemplazo'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$components · ${operation.fecha} ${operation.hora}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (operation.hasError)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ERR',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Modificar reemplazo',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_rounded,
              size: 18,
              color: AppColors.teal,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar reemplazo',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.error,
            ),
          ),
        ],
      ),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.straighten_rounded,
              size: 17,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alineación LOC-${measurement.localizacion}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${measurement.fecha} ${measurement.hora}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (measurement.errorSync != null)
            const Text(
              'ERR',
              style: TextStyle(
                fontSize: 9,
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          IconButton(
            tooltip: 'Modificar alineación',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_rounded,
              size: 18,
              color: AppColors.teal,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar alineación',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.error,
            ),
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
