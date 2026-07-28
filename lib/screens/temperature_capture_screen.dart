import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/equipo_visual_config.dart';
import '../models/models.dart';
import '../models/temperature_measurement.dart';
import '../models/temperature_plan.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/equipo_punto_viewer.dart';

class TemperatureCaptureScreen extends StatefulWidget {
  final Equipo equipo;
  final bool enableRemote;

  const TemperatureCaptureScreen({
    super.key,
    required this.equipo,
    this.enableRemote = true,
  });

  @override
  State<TemperatureCaptureScreen> createState() =>
      _TemperatureCaptureScreenState();
}

class _TemperatureCaptureScreenState extends State<TemperatureCaptureScreen> {
  final _valueController = TextEditingController();
  final _focusNode = FocusNode();
  late final EquipoVisualConfig _visualConfig;
  late final List<TemperatureStep> _steps;
  TemperatureReading? _latest;
  EquipoInfo? _info;
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;

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

  Future<void> _load() async {
    TemperatureReading? latest;
    EquipoInfo? info = widget.equipo.info;
    try {
      latest = await DbHelper.instance
          .getLatestTemperature(widget.equipo.localizacion);
    } catch (_) {}
    if (widget.enableRemote) {
      try {
        final remote = await ApiService.instance
            .fetchLatestTemperature(widget.equipo.localizacion);
        if (remote != null &&
            (latest == null || remote.fechaHora.isAfter(latest.fechaHora))) {
          latest = remote;
          try {
            await DbHelper.instance.upsertLatestTemperature(remote);
          } catch (_) {}
        }
      } catch (_) {}
    }
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
  }

  void _focusLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  bool _saveCurrent({required bool requiredValue}) {
    final value = parseTemperature(_valueController.text);
    if (requiredValue && value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese la temperatura en °C antes de continuar.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return false;
    }
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
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Salir de la medición'),
            content: const Text(
              'La medición no está terminada. Se perderán los valores capturados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Salir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _askObservation() async {
    var observation = '';
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Observación general'),
        content: TextField(
          autofocus: true,
          maxLines: 4,
          onChanged: (value) => observation = value.trim(),
          decoration: const InputDecoration(
            hintText: 'Observación de la muestra de temperatura',
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
    final now = DateTime.now();
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
      fecha: DateFormat('yyyy-MM-dd').format(now),
      hora: DateFormat('HH:mm:ss').format(now),
      valores: values,
      observaciones: observation.trim(),
      responsable: responsable,
      cargo: cargo,
      marca: (_info ?? widget.equipo.info)?.marca,
      modelo: (_info ?? widget.equipo.info)?.modelo,
      serial: (_info ?? widget.equipo.info)?.serial,
    );
    try {
      await DbHelper.instance.insertTemperature(measurement);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar localmente: $error'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _saving = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Temperatura guardada'),
        content: const Text(
          'La medición quedó guardada en la tablet para sincronizarla después '
          'desde el apartado Sincronización.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
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
        appBar: AppBar(
          backgroundColor: AppColors.headerTop,
          foregroundColor: Colors.white,
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Medición de temperatura'),
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previous == null
                            ? 'Sin temperatura anterior'
                            : 'Anterior: ${previous.toStringAsFixed(2)} °C',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('temperature-value-field'),
                        controller: _valueController,
                        focusNode: _focusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _next(),
                        decoration: const InputDecoration(
                          labelText: 'Temperatura',
                          suffixText: '°C',
                          prefixIcon: Icon(Icons.thermostat_rounded),
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
