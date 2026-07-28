import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../models/models.dart';
import '../models/equipo_visual_config.dart';
import '../models/measurement_editing.dart';
import '../models/measurement_quality.dart';
import '../models/usb_sync_status.dart';
import '../widgets/equipo_punto_viewer.dart';
import '../services/api_service.dart';
import '../db/db_helper.dart';

class CaptureScreen extends StatefulWidget {
  final Equipo equipo;

  const CaptureScreen({super.key, required this.equipo});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _valCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _focus = FocusNode();

  late final EquipoVisualConfig _visualConfig;
  List<MedicionStep> _steps = [];
  int _idx = 0;
  bool _loading = true;
  bool _saving = false;
  bool _finished = false;
  UltimaLectura? _ultima;
  EquipoInfo? _info;
  String? _ultimaFecha;
  UsbSyncStatus _usbStatus = UsbSyncStatus.fromValues(
    status: null,
    serial: null,
    detail: null,
    lastSeen: null,
    now: DateTime.now(),
  );
  Timer? _usbStatusTimer;

  @override
  void initState() {
    super.initState();
    _visualConfig = EquipoVisualResolver.fromEquipo(widget.equipo);
    _valCtrl.addListener(_onValueChanged);
    _loadUsbStatus();
    _usbStatusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadUsbStatus(),
    );
    _load();
  }

  @override
  void dispose() {
    _usbStatusTimer?.cancel();
    _valCtrl.removeListener(_onValueChanged);
    _valCtrl.dispose();
    _obsCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  MedicionStep get _current => _steps[_idx];
  double? get _anterior => _ultima?.valores[_current.dbColumn];
  double get _progress => _steps.isEmpty ? 0 : (_idx + 1) / _steps.length;

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

    if (!mounted || fileStatus == null) return;
    setState(() => _usbStatus = fileStatus!);
  }

  Future<void> _load() async {
    final steps = <MedicionStep>[];

    // MDB_EQUIPO.PUNTOS define la distribución física y las columnas reales
    // que deben llenarse en MDB_VIBR_MUES. El punto mostrado al operador puede
    // ser distinto del número de columna: por ejemplo, Punto 3 de una bomba
    // escribe en H5/V5/A5.
    final plan = PlanMedicionResolver.fromEquipo(widget.equipo);

    for (final punto in plan) {
      for (final eje in const ['H', 'V', 'A']) {
        steps.add(
          MedicionStep(
            puntoN: punto.puntoPantalla,
            visualPuntoN: punto.puntoVisual,
            dbPuntoN: punto.puntoDb,
            eje: eje,
            etiqueta: punto.nombre,
          ),
        );
      }
    }

    UltimaLectura? ul;
    EquipoInfo? info = widget.equipo.info;

    if (!kIsWeb) {
      try {
        ul = await DbHelper.instance
            .getUltimaLectura(widget.equipo.localizacion);
      } catch (_) {}

      if (info == null || info.isEmpty) {
        try {
          info =
              await DbHelper.instance.getEquipoInfo(widget.equipo.localizacion);
        } catch (_) {}
      }
    }

    // Consultamos también el servidor y comparamos fecha/hora. Así una fila
    // antigua nunca reemplaza una lectura más reciente guardada en la tablet.
    try {
      final remota = await ApiService.instance
          .fetchUltimaLectura(widget.equipo.localizacion);
      if (remota != null) {
        if (ul == null || remota.fechaHora.isAfter(ul.fechaHora)) {
          ul = remota;
        }
        if (!kIsWeb) {
          try {
            await DbHelper.instance.upsertUltimaLectura(remota);
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      final remoteInfo =
          await ApiService.instance.fetchEquipoInfo(widget.equipo.localizacion);
      if (remoteInfo != null && !remoteInfo.isEmpty) {
        info = remoteInfo;
        if (!kIsWeb) {
          try {
            await DbHelper.instance.upsertEquipoInfo(remoteInfo);
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _steps = steps;
      _ultima = ul;
      _info = info;
      _ultimaFecha = ul == null ? null : '${ul.fecha} ${ul.hora}';
      _loading = false;
    });

    // Al entrar a iniciar medición, abrimos el teclado automáticamente
    // para que el operador solo capture la lectura y avance.
    _openKeyboardLater();
  }

  void _openKeyboardLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) return;
      _focus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  double? _parseValue() {
    final text = _valCtrl.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  void _saveCurrent({bool requireValue = false}) {
    final value = _parseValue();
    if (requireValue && value == null) {
      _showSnack(
          'Ingrese la lectura en mm/s antes de continuar.', AppColors.warning);
      throw const _MissingValueException();
    }

    _current.valor = value;
  }

  Future<void> _next() async {
    if (_saving || _steps.isEmpty) return;

    try {
      _saveCurrent(requireValue: true);
    } on _MissingValueException {
      return;
    }

    if (_idx >= _steps.length - 1) {
      await _openGeneralObservationDialog();
      return;
    }

    setState(() {
      _idx++;
      _valCtrl.text = _current.valor?.toString() ?? '';
    });

    _openKeyboardLater();
  }

  bool get _hasMeasurementProgress {
    if (_finished || _saving || _loading || _steps.isEmpty) return false;
    if (_idx > 0) return true;
    if (_valCtrl.text.trim().isNotEmpty) return true;
    if (_obsCtrl.text.trim().isNotEmpty) return true;
    return _steps.any((step) => step.valor != null);
  }

  Future<bool> _confirmExitIfNeeded() async {
    if (!_hasMeasurementProgress) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Salir de la medicion'),
        content: const Text(
          'Esta medicion no se ha terminado. Si sales ahora se perderan los valores capturados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _back() async {
    if (_saving) return;

    try {
      _saveCurrent();
    } catch (_) {}

    if (_idx == 0) {
      final shouldExit = await _confirmExitIfNeeded();
      if (!mounted || !shouldExit) {
        _openKeyboardLater();
        return;
      }
      Navigator.pop(context);
      return;
    }

    setState(() {
      _idx--;
      _valCtrl.text = _current.valor?.toString() ?? '';
    });

    _openKeyboardLater();
  }

  Future<void> _openGeneralObservationDialog() async {
    var draft = _obsCtrl.text;

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Observacion general'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Observacion general de la muestra...',
          ),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Atras'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Sin observacion'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) {
      _openKeyboardLater();
      return;
    }
    _obsCtrl.text = result.trim();
    await _finish();
  }

  Future<void> _finish() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final now = DateTime.now();
    final vals = <String, double?>{};

    for (final step in _steps) {
      vals[step.dbColumn] = step.valor;
    }

    final rms = calculateRms(vals);
    final obsStr = cleanGeneralObservation(_obsCtrl.text);
    String responsable = '';
    String cargo = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      responsable = (prefs.getString('responsable') ??
              prefs.getString('username') ??
              '')
          .trim();
      cargo = (prefs.getString('cargo') ?? prefs.getString('rol') ?? '').trim();
    } catch (_) {}

    final medicion = MedicionLocal(
      uuid: const Uuid().v4(),
      localizacion: widget.equipo.localizacion,
      sistema: widget.equipo.sistema,
      fecha: DateFormat('yyyy-MM-dd').format(now),
      hora: DateFormat('HH:mm:ss').format(now),
      valores: vals,
      rms: rms,
      observaciones: obsStr,
      responsable: responsable,
      cargo: cargo,
      marca: (_info ?? widget.equipo.info)?.marca,
      modelo: (_info ?? widget.equipo.info)?.modelo,
      serial: (_info ?? widget.equipo.info)?.serial,
    );

    if (!kIsWeb) {
      try {
        await DbHelper.instance.insertMedicion(medicion);
      } catch (e) {
        if (mounted) {
          _showSnack('No se pudo guardar localmente: $e', AppColors.error);
        }
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    _finished = true;
    _showSuccessDialog(medicion);
  }

  String _cleanInfoValue(String? value, {String fallback = 'Sin datos'}) {
    if (value == null) return fallback;
    final v = value.trim();
    if (v.isEmpty ||
        v.toUpperCase() == 'NULL' ||
        v.toUpperCase() == 'SIN DATOS') {
      return fallback;
    }
    return v;
  }

  void _showEquipmentDetails() {
    final info = _info ?? widget.equipo.info;

    final details = <_InfoItem>[
      _InfoItem('Equipo', widget.equipo.equipo),
      _InfoItem('Sistema', widget.equipo.sistema),
      _InfoItem('LC', widget.equipo.localizacion.toString()),
      _InfoItem('QR', _cleanInfoValue(widget.equipo.qrDisplay)),
      _InfoItem('PUNTOS', widget.equipo.ptEq.toString()),
      _InfoItem('Marca', _cleanInfoValue(info?.marca)),
      _InfoItem('Modelo', _cleanInfoValue(info?.modelo)),
      _InfoItem('Serial', _cleanInfoValue(info?.serial)),
      _InfoItem('HP', _cleanInfoValue(info?.hp)),
      _InfoItem('Voltaje', _cleanInfoValue(info?.volts)),
      _InfoItem('FLA', _cleanInfoValue(info?.fla)),
      _InfoItem('SF', _cleanInfoValue(info?.sf)),
      _InfoItem('Hz', _cleanInfoValue(info?.hz)),
      _InfoItem('RPM', _cleanInfoValue(info?.rpm)),
      _InfoItem('Arranque', _cleanInfoValue(info?.start)),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.tealLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.precision_manufacturing_rounded,
                          color: AppColors.teal,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalles del equipo',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Información técnica descargada de la base de datos',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                    itemCount: details.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = details[i];
                      final important = item.label == 'Serial' ||
                          item.label == 'Modelo' ||
                          item.label == 'Marca';

                      return _DetailRow(
                        label: item.label,
                        value: item.value,
                        important: important,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSuccessDialog(MedicionLocal medicion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.teal),
            SizedBox(width: 10),
            Text('Medición guardada'),
          ],
        ),
        content: Text(
          'Equipo: ${widget.equipo.equipo}\n'
          'Serial: ${_cleanInfoValue(_info?.serial)}\n'
          'Fecha: ${medicion.fecha}\n'
          'Hora: ${medicion.hora}\n\n'
          'Quedó guardada en la tablet para sincronizar.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop(true);
                }
              });
            },
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.teal),
              ),
            ),
          ],
        ),
      );
    }

    if (_steps.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(
                child: Text(
                  'No hay puntos configurados para este equipo.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final current = _current;
    final ejeNombre = nombreOrientacion(current.eje);
    final ejeColor = colorOrientacionUi(current.eje);
    final anterior = _anterior;
    final isLast = _idx == _steps.length - 1;

    final media = MediaQuery.of(context);
    final size = media.size;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final isLandscape = size.width > size.height;
    final compactMode = keyboardOpen || isLandscape || size.height < 760;

    // La imagen NO cambia de tamaño cuando se abre el teclado.
    // Solo se compacta el panel de entrada y los botones.
    final imageHeight = isLandscape
        ? (size.height * 0.34).clamp(175.0, 255.0).toDouble()
        : (size.height * 0.28).clamp(220.0, 315.0).toDouble();

    return WillPopScope(
      onWillPop: _confirmExitIfNeeded,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.bg,
        body: SafeArea(
        child: Column(
          children: [
            _buildHeader(compact: compactMode),
            _buildProgressStrip(compact: compactMode),
            // Detalles técnicos movidos a un botón para no cargar la pantalla.
            SizedBox(
              height: imageHeight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    12, keyboardOpen ? 5 : 8, 12, keyboardOpen ? 4 : 6),
                child: EquipoPuntoViewer(
                  config: _visualConfig,
                  punto: current.visualPuntoN,
                  puntoEtiqueta: current.puntoN,
                  dbColumn: current.dbColumn,
                  eje: current.eje,
                  lecturaAnterior: anterior,
                  fechaAnterior: _ultimaFecha,
                  showFooter: false,
                  marca: _cleanInfoValue((_info ?? widget.equipo.info)?.marca),
                  modelo:
                      _cleanInfoValue((_info ?? widget.equipo.info)?.modelo),
                  serial:
                      _cleanInfoValue((_info ?? widget.equipo.info)?.serial),
                  onLegendTap: _showEquipmentDetails,
                ),
              ),
            ),
            Expanded(
              child: _buildOperatorPanel(
                current: current,
                ejeNombre: ejeNombre,
                ejeColor: ejeColor,
                anterior: anterior,
                isLast: isLast,
                compact: compactMode,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader({bool compact = false}) {
    return Container(
      height: compact ? 50 : 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(gradient: AppColors.gradPrimary),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            child: Material(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () {
                  _back();
                },
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.equipo.equipo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${widget.equipo.qrDisplay}  ·  ${widget.equipo.sistema}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.teal.withValues(alpha: 0.95),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            child: Material(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: _showEquipmentDetails,
                child: Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: compact ? 20 : 23,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10, vertical: compact ? 5 : 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Text(
              '${_steps.length ~/ 3} pts',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStrip({bool compact = false}) {
    return Container(
      height: compact ? 30 : 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: AppColors.surface,
      child: Row(
        children: [
          Text(
            'Paso ${_idx + 1}/${_steps.length}',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: compact ? 6 : 8,
                backgroundColor: AppColors.bg2,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.teal),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(_progress * 100).round()}%',
            style: TextStyle(
              color: AppColors.teal,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          _usbMiniChip(compact: compact),
        ],
      ),
    );
  }

  Widget _usbMiniChip({required bool compact}) {
    final bool connected = _usbStatus.online;
    final Color color = connected ? AppColors.success : AppColors.warning;
    return Tooltip(
      message: _usbStatus.detail,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.usb_rounded : Icons.usb_off_rounded,
              size: compact ? 13 : 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              connected ? 'USB ON' : 'USB OFF',
              style: TextStyle(
                color: color,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipoInfoStrip({bool compact = false}) {
    String clean(String? value, {String fallback = 'Sin datos'}) {
      if (value == null) return fallback;
      final v = value.trim();
      if (v.isEmpty ||
          v.toUpperCase() == 'NULL' ||
          v.toUpperCase() == 'SIN DATOS') {
        return fallback;
      }
      return v;
    }

    final info = _info ?? widget.equipo.info;

    final topItems = <_InfoItem>[
      _InfoItem('Serial', clean(info?.serial)),
      _InfoItem('Modelo', clean(info?.modelo)),
      _InfoItem('Marca', clean(info?.marca)),
    ];

    final bottomItems = <_InfoItem>[
      _InfoItem('LC', widget.equipo.localizacion.toString()),
      _InfoItem('QR', clean(widget.equipo.qrDisplay)),
      _InfoItem('HP', clean(info?.hp)),
      _InfoItem('Voltaje', clean(info?.volts)),
      _InfoItem('FLA', clean(info?.fla)),
      _InfoItem('SF', clean(info?.sf)),
      _InfoItem('Hz', clean(info?.hz)),
      _InfoItem('RPM', clean(info?.rpm)),
      _InfoItem('Arranque', clean(info?.start)),
    ];

    Widget chipRow(List<_InfoItem> items, {required bool important}) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _InfoChip(
                label: items[i].label,
                value: items[i].value,
                compact: compact,
                important: important,
              ),
              if (i != items.length - 1) SizedBox(width: compact ? 6 : 8),
            ],
          ],
        ),
      );
    }

    return Container(
      height: compact ? 76 : 92,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10, compact ? 6 : 8, 10, compact ? 6 : 8),
      decoration: const BoxDecoration(
        color: AppColors.surface2,
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.28)),
            ),
            child: Icon(
              Icons.badge_rounded,
              color: AppColors.teal,
              size: compact ? 24 : 28,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chipRow(topItems, important: true),
                SizedBox(height: compact ? 5 : 7),
                chipRow(bottomItems, important: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperatorPanel({
    required MedicionStep current,
    required String ejeNombre,
    required Color ejeColor,
    required double? anterior,
    required bool isLast,
    required bool compact,
  }) {
    final anteriorText = _fmtAnterior(anterior);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10, compact ? 5 : 7, 10, compact ? 5 : 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildInstructionCard(
            current: current,
            ejeNombre: ejeNombre,
            ejeColor: ejeColor,
            anteriorText: anteriorText,
            compact: compact,
          ),
          SizedBox(height: compact ? 5 : 7),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildInputBox(
                      current: current, ejeColor: ejeColor, compact: compact),
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: 4,
                  child: _buildPreviousBox(
                    anteriorText: anteriorText,
                    ejeColor: ejeColor,
                    compact: compact,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 5 : 7),
          _buildActionButtons(isLast: isLast, compact: compact),
        ],
      ),
    );
  }

  Widget _buildInstructionCard({
    required MedicionStep current,
    required String ejeNombre,
    required Color ejeColor,
    required String anteriorText,
    required bool compact,
  }) {
    return Container(
      height: compact ? 42 : 50,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: ejeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ejeColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 31 : 37,
            height: compact ? 31 : 37,
            decoration: BoxDecoration(
              color: ejeColor,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_iconForEje(current.eje),
                color: Colors.white, size: compact ? 19 : 23),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Punto ${current.puntoN}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  current.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10, vertical: compact ? 5 : 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: ejeColor.withValues(alpha: 0.22)),
            ),
            child: Text(
              ejeCorto(current.eje),
              style: TextStyle(
                color: ejeColor,
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBox({
    required MedicionStep current,
    required Color ejeColor,
    required bool compact,
  }) {
    final quality = VibrationQuality.fromValue(_parseValue());
    final qualityColor = _qualityColor(quality.level);
    final qualityBg = _qualityBg(quality.level);

    return Container(
      padding: EdgeInsets.all(compact ? 7 : 9),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_rounded, color: AppColors.teal, size: 16),
              const SizedBox(width: 5),
              Text(
                'Lectura nueva',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              const Text(
                'mm/s',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          TextField(
            controller: _valCtrl,
            focusNode: _focus,
            maxLines: 1,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
            ],
            style: TextStyle(
              fontSize: compact ? 22 : 27,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 9, vertical: compact ? 8 : 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.borderDark),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.borderDark),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ejeColor, width: 2.0),
              ),
            ),
            onSubmitted: (_) => _next(),
          ),
          SizedBox(height: compact ? 4 : 6),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: qualityBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: qualityColor.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(_qualityIcon(quality.level),
                    color: qualityColor, size: compact ? 14 : 16),
                const SizedBox(width: 6),
                Text(
                  quality.label,
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quality.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _qualityColor(VibrationQualityLevel level) {
    switch (level) {
      case VibrationQualityLevel.empty:
        return AppColors.textSecondary;
      case VibrationQualityLevel.normal:
        return AppColors.success;
      case VibrationQualityLevel.warning:
        return AppColors.warning;
      case VibrationQualityLevel.danger:
      case VibrationQualityLevel.extreme:
        return AppColors.error;
    }
  }

  Color _qualityBg(VibrationQualityLevel level) {
    switch (level) {
      case VibrationQualityLevel.empty:
        return Colors.white;
      case VibrationQualityLevel.normal:
        return AppColors.successBg;
      case VibrationQualityLevel.warning:
        return AppColors.warningBg;
      case VibrationQualityLevel.danger:
      case VibrationQualityLevel.extreme:
        return AppColors.errorBg;
    }
  }

  IconData _qualityIcon(VibrationQualityLevel level) {
    switch (level) {
      case VibrationQualityLevel.empty:
        return Icons.radio_button_unchecked_rounded;
      case VibrationQualityLevel.normal:
        return Icons.check_circle_outline_rounded;
      case VibrationQualityLevel.warning:
        return Icons.warning_amber_rounded;
      case VibrationQualityLevel.danger:
      case VibrationQualityLevel.extreme:
        return Icons.error_outline_rounded;
    }
  }

  Widget _buildPreviousBox({
    required String anteriorText,
    required Color ejeColor,
    required bool compact,
  }) {
    final hasAnterior = anteriorText != 'N/A';

    return Container(
      padding: EdgeInsets.all(compact ? 7 : 9),
      decoration: BoxDecoration(
        color: hasAnterior ? AppColors.headerTop : AppColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAnterior ? AppColors.headerTop : AppColors.borderDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasAnterior
                ? Icons.history_rounded
                : Icons.history_toggle_off_rounded,
            color: hasAnterior ? Colors.white : AppColors.textSecondary,
            size: compact ? 18 : 21,
          ),
          SizedBox(height: compact ? 2 : 3),
          Text(
            'Lectura anterior',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasAnterior ? Colors.white70 : AppColors.textSecondary,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 1 : 3),
          Text(
            anteriorText == 'N/A' ? 'Sin dato' : '$anteriorText mm/s',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasAnterior ? Colors.white : AppColors.textPrimary,
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 2),
            Text(
              _ultimaFecha == null || _ultimaFecha!.trim().isEmpty
                  ? 'Sin fecha'
                  : _ultimaFecha!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasAnterior ? Colors.white70 : AppColors.textHint,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons({
    required bool isLast,
    required bool compact,
  }) {
    return SizedBox(
      height: compact ? 38 : 42,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _ActionButtonLite(
              text: _idx == 0 ? 'Salir' : 'Atrás',
              icon: Icons.arrow_back_rounded,
              filled: false,
              color: AppColors.headerTop,
              onPressed: _saving
                  ? null
                  : () {
                      _back();
                    },
              compact: compact,
            ),
          ),
          Expanded(
            flex: 5,
            child: _ActionButtonLite(
              text: isLast ? 'Guardar' : 'Siguiente',
              icon: isLast ? Icons.save_rounded : Icons.arrow_forward_rounded,
              filled: true,
              color: isLast ? AppColors.success : AppColors.teal,
              onPressed: _saving ? null : _next,
              compact: compact,
              loading: _saving,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtAnterior(double? value) {
    if (value == null) return 'N/A';
    return value.toStringAsFixed(2);
  }

  IconData _iconForEje(String eje) {
    switch (eje.toUpperCase()) {
      case 'H':
        return Icons.swap_horiz_rounded;
      case 'V':
        return Icons.swap_vert_rounded;
      case 'A':
        return Icons.keyboard_double_arrow_right_rounded;
      default:
        return Icons.location_on_outlined;
    }
  }
}

class _ActionButtonLite extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback? onPressed;
  final bool compact;
  final bool loading;

  const _ActionButtonLite({
    required this.text,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onPressed,
    required this.compact,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          SizedBox(
            width: compact ? 14 : 16,
            height: compact ? 14 : 16,
            child: CircularProgressIndicator(
              color: filled ? Colors.white : color,
              strokeWidth: 2,
            ),
          )
        else
          Icon(icon, size: compact ? 16 : 18),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (filled) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          textStyle: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w900,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        padding: EdgeInsets.zero,
        textStyle: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w900,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool important;

  const _DetailRow({
    required this.label,
    required this.value,
    this.important = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toUpperCase();
    final noData =
        normalized.isEmpty || normalized == 'SIN DATOS' || normalized == 'NULL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: important ? AppColors.tealLight : AppColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: important
              ? AppColors.teal.withValues(alpha: 0.32)
              : AppColors.borderDark,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: TextStyle(
                color: important ? AppColors.teal : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              noData ? 'Sin datos' : value.trim(),
              style: TextStyle(
                color: noData ? AppColors.textHint : AppColors.textPrimary,
                fontSize: important ? 16 : 14,
                fontWeight: FontWeight.w900,
                height: 1.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  final bool important;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.compact,
    this.important = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toUpperCase();
    final noData =
        normalized.isEmpty || normalized == 'SIN DATOS' || normalized == 'NULL';
    final double labelSize =
        compact ? (important ? 10.5 : 9.5) : (important ? 12.0 : 10.5);
    final double valueSize =
        compact ? (important ? 13.5 : 11.5) : (important ? 15.5 : 12.5);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: important ? AppColors.tealLight : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: important
              ? AppColors.teal.withValues(alpha: 0.28)
              : AppColors.borderDark,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: important ? AppColors.teal : AppColors.textSecondary,
              fontSize: labelSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            noData ? 'Sin datos' : value.trim(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: noData ? AppColors.textHint : AppColors.textPrimary,
              fontSize: valueSize,
              fontWeight: FontWeight.w900,
              letterSpacing: important ? 0.1 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingValueException implements Exception {
  const _MissingValueException();
}
