import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../models/models.dart';
import '../models/measurement_validation.dart';
import '../models/equipo_visual_config.dart';
import '../models/measurement_editing.dart';
import '../models/measurement_quality.dart';
import '../models/usb_sync_status.dart';
import '../widgets/avisos.dart';
import '../widgets/capture_summary.dart';
import '../widgets/equipo_punto_viewer.dart';
import '../widgets/fecha_medicion.dart';
import '../widgets/industrial_header_style.dart';
import '../services/api_service.dart';
import '../db/db_helper.dart';

class CaptureScreen extends StatefulWidget {
  final Equipo equipo;
  final int? odt;

  const CaptureScreen({super.key, required this.equipo, this.odt});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _valCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _fechaMedicion = FechaHoraMedicion();
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
    // Cada 3 segundos entra un tick; sin esta comparacion la pantalla de
    // captura entera —con su visor CustomPaint— se redibujaba aunque el
    // estado USB no hubiera cambiado.
    if (fileStatus == _usbStatus) return;
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

    // El servidor se consulta DESPUES de dibujar. Antes se esperaban estas
    // dos llamadas antes de mostrar nada y, en una tablet que trabaja por
    // USB —sin ruta al servidor de la planta—, cada una agota su tiempo de
    // espera: el mecanico miraba el circulito en cada equipo que media.
    _refrescarDesdeServidor();
  }

  /// Trae del servidor la ultima lectura y la ficha tecnica, y actualiza la
  /// pantalla si llegan. Sin red no pasa nada: la captura ya esta lista.
  Future<void> _refrescarDesdeServidor() async {
    try {
      final remota = await ApiService.instance
          .fetchUltimaLectura(widget.equipo.localizacion);
      if (remota != null) {
        final actual = _ultima;
        if (actual == null || remota.fechaHora.isAfter(actual.fechaHora)) {
          if (!kIsWeb) {
            try {
              await DbHelper.instance.upsertUltimaLectura(remota);
            } catch (_) {}
          }
          if (mounted) {
            setState(() {
              _ultima = remota;
              _ultimaFecha = '${remota.fecha} ${remota.hora}';
            });
          }
        }
      }
    } catch (_) {}

    try {
      final remoteInfo =
          await ApiService.instance.fetchEquipoInfo(widget.equipo.localizacion);
      if (remoteInfo != null && !remoteInfo.isEmpty) {
        if (!kIsWeb) {
          try {
            await DbHelper.instance.upsertEquipoInfo(remoteInfo);
          } catch (_) {}
        }
        if (mounted) setState(() => _info = remoteInfo);
      }
    } catch (_) {}
  }

  void _openKeyboardLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) return;
      _focus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  double? _parseValue() {
    return MeasurementValidation.parseDecimal(_valCtrl.text);
  }

  void _saveCurrent({bool requireValue = false}) {
    final value = _parseValue();
    final error = requireValue
        ? MeasurementValidation.requiredNumber(_valCtrl.text)
        : null;
    if (error != null) {
      avisar(context, error, AppColors.warning);
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
    return confirmar(
      context,
      titulo: 'Salir de la medición',
      mensaje:
          'Esta medición no se ha terminado. Si sales ahora se perderán los valores capturados.',
      textoConfirmar: 'SALIR',
      destructivo: true,
    );
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

  /// Agrupa los pasos por punto: cada paso es un eje, y la tabla es por punto.
  List<CaptureSummaryRow> _resumenPuntos() {
    final orden = <int>[];
    final ejes = <int, Map<String, double?>>{};
    final nombres = <int, String>{};
    for (final step in _steps) {
      if (!ejes.containsKey(step.puntoN)) {
        orden.add(step.puntoN);
        ejes[step.puntoN] = <String, double?>{};
        nombres[step.puntoN] = step.etiqueta;
      }
      ejes[step.puntoN]![step.eje.toUpperCase()] = step.valor;
    }
    return [
      for (final punto in orden)
        CaptureSummaryRow(
          numero: '$punto',
          nombre: nombres[punto] ?? 'Punto $punto',
          valores: [
            for (final eje in const ['H', 'V', 'A'])
              CaptureSummary.formatear(ejes[punto]![eje]),
          ],
        ),
    ];
  }

  Future<void> _openGeneralObservationDialog() async {
    var draft = _obsCtrl.text;

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Observacion general'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // El resumen de lo medido queda a la vista mientras escribe:
                // ver el valor de cada punto es lo que le hace recordar que
                // encontro ahi.
                CaptureSummary(
                  headers: const ['H', 'V', 'A'],
                  rows: _resumenPuntos(),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: draft,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Observacion general de la muestra...',
                  ),
                  onChanged: (value) => draft = value,
                ),
                const SizedBox(height: 12),
                // Para la medicion hecha antes sin la tablet a mano.
                SelectorFechaMedicion(valor: _fechaMedicion),
              ],
            ),
          ),
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
      responsable =
          (prefs.getString('responsable') ?? prefs.getString('username') ?? '')
              .trim();
      cargo = (prefs.getString('cargo') ?? prefs.getString('rol') ?? '').trim();
    } catch (_) {}

    final medicion = MedicionLocal(
      uuid: const Uuid().v4(),
      localizacion: widget.equipo.localizacion,
      sistema: widget.equipo.sistema,
      fecha: _fechaMedicion.fecha,
      hora: _fechaMedicion.hora,
      valores: vals,
      rms: rms,
      observaciones: obsStr,
      responsable: responsable,
      cargo: cargo,
      marca: (_info ?? widget.equipo.info)?.marca,
      modelo: (_info ?? widget.equipo.info)?.modelo,
      serial: (_info ?? widget.equipo.info)?.serial,
      odt: widget.odt,
    );

    if (!kIsWeb) {
      try {
        await DbHelper.instance.insertMedicion(medicion);
        await _fechaMedicion.registrarSiManual(
          servicio: 'vibración',
          localizacion: widget.equipo.localizacion,
          uuid: medicion.uuid,
        );
      } catch (e) {
        if (mounted) {
          avisar(context, 'No se pudo guardar localmente: $e', AppColors.error);
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalles del equipo',
                              style: AppText.titulo
                                  .copyWith(color: AppColors.textPrimary),
                            ),
                            Text(
                              'Información técnica descargada de la base de datos',
                              style: AppText.subtitulo
                                  .copyWith(color: AppColors.textSecondary),
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

  Future<void> _showSuccessDialog(MedicionLocal medicion) async {
    await avisarGuardado(
      context,
      titulo: 'Medición guardada',
      mensaje: 'Equipo: ${widget.equipo.equipo}\n'
          'Serial: ${_cleanInfoValue(_info?.serial)}\n'
          'Fecha: ${medicion.fecha}\n'
          'Hora: ${medicion.hora}\n\n'
          'Quedó guardada en la tablet para sincronizar.',
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          minimum: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              _buildHeader(),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.teal),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_steps.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          minimum: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              _buildHeader(),
              const Expanded(
                child: Center(
                  child: Text(
                    'No hay puntos configurados para este equipo.',
                    style: AppText.cuerpoFuerte,
                  ),
                ),
              ),
            ],
          ),
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

    return PopScope(
      // El gesto de atras pregunta antes de perder una medicion a medias,
      // igual que el boton Salir. PopScope y no WillPopScope, que quedo
      // deprecado y ademas rompia el gesto predictivo de Android.
      canPop: !_hasMeasurementProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // El navegador se captura antes del await: es la forma canonica de
        // no usar el context a traves de un hueco asincrono.
        final navegador = Navigator.of(context);
        final salir = await _confirmExitIfNeeded();
        if (salir) navegador.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.bg,
        body: SafeArea(
          minimum: const EdgeInsets.only(top: 8),
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
                    marca:
                        _cleanInfoValue((_info ?? widget.equipo.info)?.marca),
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
      decoration: IndustrialHeaderStyle.decoration,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: _back,
            style: IndustrialHeaderStyle.actionStyle,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
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
                  style: IndustrialHeaderStyle.title
                      .copyWith(fontSize: compact ? 18 : 20),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${widget.equipo.qrDisplay}  ·  ${widget.equipo.sistema}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IndustrialHeaderStyle.subtitle,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Información del equipo',
            onPressed: _showEquipmentDetails,
            style: IndustrialHeaderStyle.actionStyle,
            icon: const Icon(Icons.info_outline_rounded, size: 20),
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
              style: AppText.micro.copyWith(color: Colors.white),
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
            style: AppText.etiqueta.copyWith(color: AppColors.textPrimary),
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
            style: AppText.mono.copyWith(color: AppColors.teal),
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
              style: AppText.micro.copyWith(color: color),
            ),
          ],
        ),
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
            child: Icon(iconoDeEje(current.eje),
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
                  style: AppText.seccion.copyWith(color: AppColors.textPrimary),
                ),
                Text(
                  current.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitulo
                      .copyWith(color: AppColors.textSecondary),
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
              style: AppText.mono.copyWith(color: ejeColor),
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
                style: AppText.etiqueta.copyWith(color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text(
                'mm/s',
                style: AppText.micro.copyWith(color: AppColors.textSecondary),
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
              MeasurementValidation.decimalFormatter(signed: false),
            ],
            // Fuera de la escala a proposito. Es el unico campo que el tecnico
            // teclea con guantes, y su tamano esta atado al alto que queda
            // libre en el panel: crece o encoge con `compact` para no
            // desbordar el Expanded cuando se abre el teclado. Ninguno de los
            // roles de AppText puede seguir esa medida variable.
            style: TextStyle(
              fontSize: compact ? 22 : 27,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              filled: true,
              fillColor: AppColors.surface2,
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
          // Solo esta franja escucha el campo de texto. Antes habia un
          // addListener con setState que reconstruia la pantalla entera
          // —incluido el visor CustomPaint del equipo— en cada tecla, y en
          // la tablet se sentia como teclado a tirones. El unico widget que
          // depende del valor tecleado es este semaforo de calidad.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _valCtrl,
            builder: (context, _, __) {
              final quality = VibrationQuality.fromValue(_parseValue());
              final qualityColor = _qualityColor(quality.level);
              final qualityBg = _qualityBg(quality.level);
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: qualityBg,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: qualityColor.withValues(alpha: 0.28)),
                ),
                child: Row(
                  children: [
                    Icon(_qualityIcon(quality.level),
                        color: qualityColor, size: compact ? 14 : 16),
                    const SizedBox(width: 6),
                    Text(
                      quality.label,
                      style: AppText.etiqueta.copyWith(color: qualityColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        quality.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.micro
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              );
            },
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
            style: AppText.micro.copyWith(
              color: hasAnterior ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 1 : 3),
          Text(
            anteriorText == 'N/A' ? 'Sin dato' : '$anteriorText mm/s',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.datoGrande.copyWith(
              color: hasAnterior ? Colors.white : AppColors.textPrimary,
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
              style: AppText.micro.copyWith(
                color: hasAnterior ? Colors.white70 : AppColors.textHint,
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
              color: AppColors.teal,
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
          textStyle: AppText.cuerpoFuerte,
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
        textStyle: AppText.cuerpoFuerte,
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
        // tealLight (#E6F7F4) es casi blanco y el valor se pinta con
        // textPrimary (#F4F8FF): quedaba blanco sobre blanco. Se usa el mismo
        // teal translucido que _InfoChip, que si contrasta con el tema oscuro.
        color:
            important ? AppColors.teal.withValues(alpha: .14) : AppColors.bg2,
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
              style: AppText.etiqueta.copyWith(
                color: important ? AppColors.teal : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              noData ? 'Sin datos' : value.trim(),
              style:
                  (important ? AppText.seccion : AppText.cuerpoFuerte).copyWith(
                color: noData ? AppColors.textHint : AppColors.textPrimary,
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

class _MissingValueException implements Exception {
  const _MissingValueException();
}
