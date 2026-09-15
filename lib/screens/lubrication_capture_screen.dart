import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/lubrication_measurement.dart';
import '../models/measurement_validation.dart';
import '../models/lubrication_plan.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/capture_summary.dart';
import '../widgets/fecha_medicion.dart';
import '../widgets/measurement_advisory_banner.dart';
import '../widgets/decode_imagen.dart';
import '../widgets/industrial_navigation.dart';

class LubricationCaptureScreen extends StatefulWidget {
  const LubricationCaptureScreen({super.key, required this.equipo, this.odt});

  final Equipo equipo;
  final int? odt;

  @override
  State<LubricationCaptureScreen> createState() =>
      _LubricationCaptureScreenState();
}

class _LubricationCaptureScreenState extends State<LubricationCaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _observations = TextEditingController();
  final _fechaMedicion = FechaHoraMedicion();
  late final List<LubricationStep> _steps;
  late final Map<String, TextEditingController> _controllers;
  EquipoInfo? _info;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _steps = LubricationPlanResolver.fromPuntos(widget.equipo.puntos);
    _controllers = {
      for (final step in _steps) step.dbColumn: TextEditingController(),
    };
    // El resumen junto a las observaciones tiene que ir reflejando lo que se
    // escribe en cada punto.
    for (final controller in _controllers.values) {
      controller.addListener(_refrescarResumen);
    }
    _load();
  }

  void _refrescarResumen() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_refrescarResumen);
      controller.dispose();
    }
    _observations.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var info = widget.equipo.info;
    if (info == null || info.isEmpty) {
      try {
        info = await DbHelper.instance.getEquipoInfo(
          widget.equipo.localizacion,
        );
      } catch (_) {}
    }
    for (final step in _steps) {
      final suggestion = _suggestionFor(step, info);
      if (suggestion != null && suggestion > 0) {
        _controllers[step.dbColumn]!.text = _format(suggestion);
      }
    }
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  String _format(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  double? _suggestionFor(LubricationStep step, [EquipoInfo? info]) {
    final equipmentInfo = info ?? _info;
    if (!_hasRecommendationForPoint(step, equipmentInfo)) return null;
    if (_usesPumpCountInsteadOfGrams(step, equipmentInfo)) return null;
    return step.motor ? equipmentInfo?.cantMotLub : equipmentInfo?.cantElemLub;
  }

  bool _usesPumpCountInsteadOfGrams(
    LubricationStep step, [
    EquipoInfo? info,
  ]) {
    final equipmentInfo = info ?? _info;
    final element = (equipmentInfo?.elementoLub ?? '').toLowerCase();
    return !step.motor &&
        {7, 8, 9}.contains(step.dbPointNumber) &&
        element.contains('ventilador');
  }

  bool _hasRecommendationForPoint(
    LubricationStep step, [
    EquipoInfo? info,
  ]) {
    final equipmentInfo = info ?? _info;
    if (step.motor) return true;

    final element = (equipmentInfo?.elementoLub ?? '').toLowerCase();
    if (element.trim().isEmpty || element.trim() == 'null') return false;

    switch (step.dbPointNumber) {
      case 3:
      case 4:
        return element.contains('acopl') ||
            element.contains('caja') ||
            element.contains('reductor');
      case 5:
      case 6:
        return element.contains('bomba') || element.contains('compresor');
      case 7:
      case 8:
        return element.contains('ventilador');
      case 9:
        return element.contains('fin fan') ||
            element.contains('finfan') ||
            element.contains('chumacera') ||
            element.contains('ventilador');
      default:
        return false;
    }
  }

  String _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty || text.toUpperCase() == 'NULL' ? 'Sin datos' : text;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    final measurement = LubricationMeasurement(
      uuid: const Uuid().v4(),
      localizacion: widget.equipo.localizacion,
      sistema: widget.equipo.sistema,
      fecha: _fechaMedicion.fecha,
      hora: _fechaMedicion.hora,
      valores: {
        for (final step in _steps)
          step.dbColumn: parseLubricationValue(
            _controllers[step.dbColumn]!.text,
          ),
      },
      observaciones: _observations.text.trim(),
      responsable:
          prefs.getString('responsable') ?? prefs.getString('username'),
      cargo: prefs.getString('cargo') ?? prefs.getString('rol'),
      marca: _info?.marca,
      modelo: _info?.modelo,
      serial: _info?.serial,
      odt: widget.odt,
    );
    try {
      await DbHelper.instance.insertLubrication(measurement);
      await _fechaMedicion.registrarSiManual(
        servicio: 'lubricación',
        localizacion: widget.equipo.localizacion,
        uuid: measurement.uuid,
      );
      if (!mounted) return;
      await avisarGuardado(
        context,
        titulo: 'Lubricación guardada',
        mensaje: 'El trabajo quedó guardado en la tablet y aparecerá en '
            'Sincronizar hasta que sea enviado.',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      avisar(context, 'No se pudo guardar: $error', AppColors.error);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(titulo: 'Lubricación'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _header(),
            const SizedBox(height: 14),
            _referenceCard(),
            const SizedBox(height: 18),
            _visualLubricationMap(),
            const SizedBox(height: 18),
            // Lo capturado queda a la vista mientras escribe la observacion.
            CaptureSummary(
              headers: const ['Gramos'],
              rows: [
                for (var i = 0; i < _steps.length; i++)
                  CaptureSummaryRow(
                    numero: '${i + 1}',
                    nombre: _steps[i].label,
                    valores: [
                      CaptureSummary.formatear(
                        _controllers[_steps[i].dbColumn]?.text,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _observations,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Para la medicion hecha antes sin la tablet a mano.
            SelectorFechaMedicion(valor: _fechaMedicion),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              key: const Key('save-lubrication-button'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Guardar lubricación'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Card(
        color: AppColors.headerTop,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.equipo.equipo,
                style: AppText.titulo.copyWith(color: Colors.white),
              ),
              Text(
                '${widget.equipo.sistema} · LOC ${widget.equipo.localizacion}',
                style: const TextStyle(color: Color(0xFFB8C7DE)),
              ),
              Text(
                '${_clean(_info?.marca)} · ${_clean(_info?.modelo)} · ${_clean(_info?.serial)}',
                style: const TextStyle(color: Color(0xFFB8C7DE)),
              ),
            ],
          ),
        ),
      );

  Widget _referenceCard() => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: const Key('lubrication-info-expansion'),
          initiallyExpanded: false,
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text(
            'Ficha de lubricación',
            style: AppText.seccion,
          ),
          subtitle: Text(
            '${_clean(_info?.lubricacion)} · Toque para mostrar u ocultar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reference('Rodamiento acople', _info?.brgsDrive),
                _reference('Rodamiento libre', _info?.brgsOpp),
                _reference('Tipo de lubricación', _info?.lubricacion),
                _reference('Motores', _info?.motoresLub),
                _reference('Elementos', _info?.elementoLub),
                _reference(
                  'Grasera eléctrica motores',
                  _pumpText(_info?.elecMotLub, 2),
                ),
                _reference(
                  'Grasera manual motores',
                  _pumpText(_info?.manMotLub, 2.4),
                ),
                _reference(
                  'Grasera eléctrica elementos',
                  _pumpText(_info?.elecElemLub, 2),
                ),
                _reference(
                  'Grasera manual elementos',
                  _pumpText(_info?.manElemLub, 2.4),
                ),
              ],
            ),
          ],
        ),
      );

  String? _pumpText(double? pumps, double grams) =>
      pumps == null ? null : '${_format(pumps)} emboladas · $grams g/embolada';

  Widget _visualLubricationMap() {
    return Card(
      key: const Key('lubrication-visual-map'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.headerTop, AppColors.headerBottom],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.oil_barrel_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guía visual de lubricación',
                        style: AppText.titulo.copyWith(color: Colors.white),
                      ),
                      const Text(
                        'Revise la imagen y complete todos los puntos.',
                        style: TextStyle(color: Color(0xFFCFD9E8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  height: _lubricationImageHeight(),
                  width: double.infinity,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Image.asset(
                    _lubricationAsset(),
                    fit: BoxFit.contain,
                    cacheWidth: anchoDecode(context),
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.precision_manufacturing_outlined,
                        size: 70,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final step in _steps) ...[
                  _locationIndicator(step, _componentName(step)),
                  const SizedBox(height: 8),
                  _lubricationPoint(step),
                  const SizedBox(height: 14),
                ],
                Text(
                  'Ajuste cada valor a los gramos realmente aplicados.',
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

  Widget _locationIndicator(
    LubricationStep step,
    String component,
  ) =>
      Container(
        key: Key('lubrication-location-${step.dbColumn}'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF7A4A00),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.arrow_downward_rounded,
              color: Color(0xFFFFD166),
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COLOCAR AQUÍ · $component',
                    style: AppText.cuerpoFuerte.copyWith(
                      color: const Color(0xFFFFD166),
                    ),
                  ),
                  Text(
                    _locationName(step),
                    style: AppText.seccion.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.water_drop_rounded,
              color: Color(0xFFFFD166),
              size: 30,
            ),
          ],
        ),
      );

  Widget _lubricationPoint(LubricationStep step) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6C96B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9A6500),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    step.dbColumn,
                    style: AppText.micro.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aplicación de grasa',
                    style:
                        AppText.seccion.copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(spacing: 8, runSpacing: 8, children: _pumpBadges(step)),
            const SizedBox(height: 10),
            _valueField(step),
          ],
        ),
      );

  List<Widget> _pumpBadges(LubricationStep step) {
    final applies = _hasRecommendationForPoint(step);
    final electric =
        applies ? (step.motor ? _info?.elecMotLub : _info?.elecElemLub) : null;
    final manual =
        applies ? (step.motor ? _info?.manMotLub : _info?.manElemLub) : null;
    final badges = <Widget>[];
    if (applies && _usesPumpCountInsteadOfGrams(step)) {
      final generalPumps = _info?.cantElemLub;
      if (generalPumps != null && generalPumps > 0) {
        badges.add(
          _pumpBadge(
            icon: Icons.oil_barrel_rounded,
            label: 'Cantidad indicada',
            detail: '${_format(generalPumps)} emboladas',
            color: const Color(0xFF9A6500),
          ),
        );
      }
    }
    if (electric != null && electric > 0) {
      badges.add(
        _pumpBadge(
          icon: Icons.electrical_services_rounded,
          label: 'Pistola eléctrica',
          detail: '${_format(electric)} emboladas · 2 g c/u',
          color: const Color(0xFF1769AA),
        ),
      );
    }
    if (manual != null && manual > 0) {
      badges.add(
        _pumpBadge(
          icon: Icons.pan_tool_alt_rounded,
          label: 'Pistola manual',
          detail: '${_format(manual)} emboladas · 2,4 g c/u',
          color: const Color(0xFF2E7D32),
        ),
      );
    }
    if (badges.isEmpty) {
      badges.add(
        _pumpBadge(
          icon: Icons.help_outline_rounded,
          label: 'Sin cantidad predefinida',
          detail: 'Registre solamente lo aplicado',
          color: AppColors.textSecondary,
        ),
      );
    }
    return badges;
  }

  Widget _pumpBadge({
    required IconData icon,
    required String label,
    required String detail,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.etiqueta.copyWith(color: color),
                ),
                Text(
                  detail,
                  style: AppText.apoyo.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  String _locationName(LubricationStep step) {
    final label = step.label.toLowerCase();
    final element = (_info?.elementoLub ?? '').toLowerCase();
    if (element.contains('acopl') && step.dbPointNumber == 3) {
      return 'Acoplamiento · Punto 1';
    }
    if (element.contains('acopl') && step.dbPointNumber == 4) {
      return 'Acoplamiento · Punto 2';
    }
    if (label.contains('lado libre')) return 'Rodamiento del lado libre';
    if (label.contains('lado acople')) return 'Rodamiento del lado acople';
    if (label.contains('lado baja')) return 'Apoyo de baja · Caja–Motor';
    if (label.contains('lado alta')) return 'Apoyo de alta · Caja–Bomba';
    if (label.contains('punto 1')) return 'Ventilador · Punto 1';
    if (label.contains('punto 2')) return 'Ventilador · Punto 2';
    return step.label;
  }

  /// El esquema de cada tipo de equipo, con sus puntos numerados. Son los
  /// mismos dibujos del formato SF-OP-FOR-020 que el mecanico firma en papel:
  /// asi el numero de punto que ve en la tablet es el mismo de la planilla.
  ///
  /// Los tipos 7 y 8 —bombas verticales SPRINT y WATER WASH— caian antes en
  /// el esquema de motor-bomba horizontal, que es otro equipo. Su dibujo se
  /// saco de la plantilla Motor-Bomba(B).pdf.
  static const _esquemasPorPuntos = <int, String>{
    10: 'assets/images/visual_separador_motor.jpg',
    4: 'assets/images/tipo_fin_fan.png',
    5: 'assets/images/tipo_ventilador.png',
    6: 'assets/images/tipo_caja_bomba.png',
    7: 'assets/images/tipo_motor_bomba_vertical.png',
    8: 'assets/images/tipo_motor_bomba_vertical.png',
  };

  String _lubricationAsset() =>
      _esquemasPorPuntos[widget.equipo.puntos] ??
      'assets/images/tipo_motor_bomba.png';

  double _lubricationImageHeight() {
    switch (widget.equipo.puntos) {
      case 6:
        return 360;
      case 4:
      case 5:
        return 390;
      case 7:
      case 8:
        // El dibujo es vertical: con 250 px la bomba se veia aplastada.
        return 360;
      default:
        return 250;
    }
  }

  String _componentName(LubricationStep step) {
    final label = step.label.toLowerCase();
    if (step.motor) return 'Motor';
    if ((_info?.elementoLub ?? '').toLowerCase().contains('acopl') &&
        {3, 4}.contains(step.dbPointNumber)) {
      return 'Acoplamiento';
    }
    if (label.contains('caja')) return 'Caja multiplicadora';
    if (label.contains('ventilador')) return 'Ventilador';
    return 'Bomba / compresor';
  }

  Widget _reference(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$label: ${_clean(value)}'),
      );

  Widget _valueField(LubricationStep step) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MeasurementAdvisoryBanner(
              advisory: MeasurementAdvisory.lubrication(
                MeasurementValidation.parseDecimal(
                  _controllers[step.dbColumn]?.text,
                ),
                _suggestionFor(step),
              ),
            ),
            const SizedBox(height: 5),
            TextFormField(
              key: Key('lubrication-${step.dbColumn}'),
              controller: _controllers[step.dbColumn],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                MeasurementValidation.decimalFormatter(signed: false),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '${step.dbColumn} · ${step.label}',
                suffixText: 'g',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  final suggestion = _suggestionFor(step);
                  return suggestion != null && suggestion > 0
                      ? 'Ingrese los gramos aplicados'
                      : null;
                }
                final parsed = parseLubricationValue(value);
                if (parsed == null) return 'Ingrese un valor válido';
                return null;
              },
            ),
          ],
        ),
      );
}
