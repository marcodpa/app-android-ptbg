import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/equipo_visual_config.dart';
import '../models/measurement_validation.dart';
import '../models/models.dart';
import '../models/temperature_measurement.dart';
import '../models/temperature_plan.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/capture_summary.dart';
import '../widgets/fecha_medicion.dart';
import '../widgets/equipo_punto_viewer.dart';
import '../widgets/measurement_advisory_banner.dart';
import '../widgets/industrial_navigation.dart';

class TemperatureCaptureScreen extends StatefulWidget {
  final Equipo equipo;
  final bool enableRemote;
  final int? odt;

  const TemperatureCaptureScreen({
    super.key,
    required this.equipo,
    this.enableRemote = true,
    this.odt,
  });

  @override
  State<TemperatureCaptureScreen> createState() =>
      _TemperatureCaptureScreenState();
}

class _TemperatureCaptureScreenState extends State<TemperatureCaptureScreen> {
  final _valueController = TextEditingController();
  final _focusNode = FocusNode();
  final _fechaMedicion = FechaHoraMedicion();
  late final EquipoVisualConfig _visualConfig;
  late final List<TemperatureStep> _steps;
  TemperatureReading? _latest;
  EquipoInfo? _info;
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;
  String? _valueError;

  TemperatureStep get _current => _steps[_index];

  @override
  void initState() {
    super.initState();
    _visualConfig = EquipoVisualResolver.fromEquipo(widget.equipo);
    _steps = TemperaturePlanResolver.fromPuntos(widget.equipo.ptEq);
    _load();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Abre la pantalla con lo que ya esta en la tablet y consulta al servidor
  /// despues, sin bloquear.
  ///
  /// Antes se esperaba la respuesta del API ANTES de dibujar: en una tablet
  /// que trabaja por USB —sin ruta hacia el servidor de la planta— esa
  /// llamada agota sus diez segundos siempre, y el mecanico se los comia
  /// mirando el circulito en cada equipo que media.
  Future<void> _load() async {
    TemperatureReading? latest;
    EquipoInfo? info = widget.equipo.info;
    try {
      latest = await DbHelper.instance
          .getLatestTemperature(widget.equipo.localizacion);
    } catch (_) {}
    if (info == null || info.isEmpty) {
      try {
        info =
            await DbHelper.instance.getEquipoInfo(widget.equipo.localizacion);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _latest = latest;
      _info = info;
      _loading = false;
    });
    _focusLater();
    _refrescarDesdeServidor();
  }

  /// Si hay red, trae la ultima lectura del servidor y actualiza la tarjeta
  /// de "anterior" cuando llegue. Si no hay, no se entera nadie.
  Future<void> _refrescarDesdeServidor() async {
    if (!widget.enableRemote) return;
    try {
      final remote = await ApiService.instance
          .fetchLatestTemperature(widget.equipo.localizacion);
      if (remote == null) return;
      final actual = _latest;
      if (actual != null && !remote.fechaHora.isAfter(actual.fechaHora)) return;
      try {
        await DbHelper.instance.upsertLatestTemperature(remote);
      } catch (_) {}
      if (mounted) setState(() => _latest = remote);
    } catch (_) {}
  }

  void _focusLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  bool _saveCurrent({required bool requiredValue}) {
    final error = requiredValue
        ? MeasurementValidation.requiredNumber(_valueController.text)
        : null;
    if (error != null) {
      setState(() => _valueError = error);
      avisar(context, error, AppColors.warning);
      return false;
    }
    final value = MeasurementValidation.parseDecimal(_valueController.text);
    if (_valueError != null) setState(() => _valueError = null);
    _current.value = value;
    return true;
  }

  Future<void> _next() async {
    if (_saving || !_saveCurrent(requiredValue: true)) return;
    if (_index == _steps.length - 1) {
      await _askObservation();
      return;
    }
    setState(() {
      _index++;
      _valueController.text = _current.value?.toString() ?? '';
    });
    _focusLater();
  }

  Future<void> _back() async {
    if (_saving) return;
    _saveCurrent(requiredValue: false);
    if (_index == 0) {
      if (await _confirmExit()) {
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    setState(() {
      _index--;
      _valueController.text = _current.value?.toString() ?? '';
    });
    _focusLater();
  }

  bool get _hasProgress =>
      _valueController.text.trim().isNotEmpty ||
      _steps.any((step) => step.value != null);

  Future<bool> _confirmExit() async {
    if (!_hasProgress) return true;
    return confirmar(
      context,
      titulo: 'Salir de la medición',
      mensaje:
          'La medición no está terminada. Se perderán los valores capturados.',
      textoConfirmar: 'SALIR',
      destructivo: true,
    );
  }

  Future<void> _askObservation() async {
    var observation = '';
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Observación general'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ver la temperatura de cada punto mientras escribe es lo que
                // le hace recordar que encontro en cada uno.
                CaptureSummary(
                  headers: const ['Temperatura'],
                  rows: [
                    for (final step in _steps)
                      CaptureSummaryRow(
                        numero: '${step.pointNumber}',
                        nombre: step.label,
                        valores: [CaptureSummary.formatear(step.value)],
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  autofocus: true,
                  maxLines: 4,
                  onChanged: (value) => observation = value.trim(),
                  decoration: const InputDecoration(
                    hintText: 'Observación de la muestra de temperatura',
                  ),
                ),
                const SizedBox(height: 12),
                // Para la medicion hecha antes sin la tablet a mano.
                SelectorFechaMedicion(valor: _fechaMedicion),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Atrás'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Sin observación'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, observation),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) {
      _focusLater();
      return;
    }
    await _finish(result);
  }

  Future<void> _finish(String observation) async {
    if (_saving) return;
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();
    var responsable = '';
    var cargo = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      responsable =
          (prefs.getString('responsable') ?? prefs.getString('username') ?? '')
              .trim();
      cargo = (prefs.getString('cargo') ?? prefs.getString('rol') ?? '').trim();
    } catch (_) {}
    final values = <String, double?>{
      for (final step in _steps) step.dbColumn: step.value,
    };
    final measurement = TemperatureMeasurement(
      uuid: const Uuid().v4(),
      localizacion: widget.equipo.localizacion,
      sistema: widget.equipo.sistema,
      fecha: _fechaMedicion.fecha,
      hora: _fechaMedicion.hora,
      valores: values,
      observaciones: observation.trim(),
      responsable: responsable,
      cargo: cargo,
      marca: (_info ?? widget.equipo.info)?.marca,
      modelo: (_info ?? widget.equipo.info)?.modelo,
      serial: (_info ?? widget.equipo.info)?.serial,
      odt: widget.odt,
    );
    try {
      await DbHelper.instance.insertTemperature(measurement);
      await _fechaMedicion.registrarSiManual(
        servicio: 'temperatura',
        localizacion: widget.equipo.localizacion,
        uuid: measurement.uuid,
      );
    } catch (error) {
      if (mounted) {
        avisar(context, 'No se pudo guardar localmente: $error',
            AppColors.error);
        setState(() => _saving = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await avisarGuardado(
      context,
      titulo: 'Temperatura guardada',
      mensaje:
          'La medición quedó guardada en la tablet para sincronizarla después '
          'desde el apartado Sincronización.',
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final previous = _latest?.valores[_current.dbColumn];
    final progress = (_index + 1) / _steps.length;
    return PopScope<Object?>(
      canPop: _allowPop || !_hasProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _confirmExit();
        if (!context.mounted || !shouldExit) return;
        setState(() => _allowPop = true);
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: IndustrialAppBar(
          titulo: 'Medición de temperatura',
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      'Paso ${_index + 1}/${_steps.length}',
                      style: AppText.cuerpoFuerte,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: LinearProgressIndicator(value: progress)),
                    const SizedBox(width: 12),
                    Text(_current.dbColumn),
                  ],
                ),
              ),
              SizedBox(
                height: 285,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: EquipoPuntoViewer(
                    config: _visualConfig,
                    punto: _current.visualPointNumber,
                    puntoEtiqueta: _current.pointNumber,
                    dbColumn: _current.dbColumn,
                    eje: 'T',
                    showOrientationLegend: false,
                    showDirectionalMarker: false,
                    unit: '°C',
                    lecturaAnterior: previous,
                    fechaAnterior: _latest == null
                        ? null
                        : '${_latest!.fecha} ${_latest!.hora}',
                    marca: (_info ?? widget.equipo.info)?.marca,
                    modelo: (_info ?? widget.equipo.info)?.modelo,
                    serial: (_info ?? widget.equipo.info)?.serial,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _current.label,
                        style: AppText.titulo,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previous == null
                            ? 'Sin temperatura anterior'
                            : 'Anterior: ${previous.toStringAsFixed(2)} °C',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      MeasurementAdvisoryBanner(
                        advisory: MeasurementAdvisory.temperature(
                          MeasurementValidation.parseDecimal(
                            _valueController.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        key: const Key('temperature-value-field'),
                        controller: _valueController,
                        focusNode: _focusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        inputFormatters: [
                          MeasurementValidation.decimalFormatter(signed: true),
                        ],
                        onChanged: (_) {
                          setState(() => _valueError = null);
                        },
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _next(),
                        decoration: InputDecoration(
                          labelText: 'Temperatura',
                          suffixText: '°C',
                          prefixIcon: const Icon(Icons.thermostat_rounded),
                          errorText: _valueError,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _back,
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Anterior'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              key: const Key('temperature-next-button'),
                              onPressed: _saving ? null : _next,
                              icon: Icon(
                                _index == _steps.length - 1
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                              ),
                              label: Text(
                                _index == _steps.length - 1
                                    ? 'Finalizar'
                                    : 'Siguiente',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
