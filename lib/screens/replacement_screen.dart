import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/operation_flow.dart';
import '../models/replacement_request.dart';
import '../db/db_helper.dart';
import '../theme.dart';
import '../widgets/replacement_focus_image.dart';

typedef ReplacementSaver = Future<ReplacementSaveResult> Function(
  ReplacementRequest request,
);

class ReplacementScreen extends StatefulWidget {
  const ReplacementScreen({
    super.key,
    required this.equipo,
    this.saveReplacement,
  });

  final Equipo equipo;
  final ReplacementSaver? saveReplacement;

  @override
  State<ReplacementScreen> createState() => _ReplacementScreenState();
}

class _ReplacementScreenState extends State<ReplacementScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<ReplacementComponent, _ReplacementFields> _fields = {
    for (final component in ReplacementComponent.values)
      component: _ReplacementFields(),
  };
  final Set<ReplacementComponent> _selected = <ReplacementComponent>{};

  late final List<ReplacementComponent> _available;
  bool _updateMotorTechnicalSpecs = false;
  bool _reviewing = false;
  bool _finishing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _available = ReplacementComponentResolver.fromPuntos(widget.equipo.ptEq);
  }

  @override
  void dispose() {
    for (final fields in _fields.values) {
      fields.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges => _selected.isNotEmpty;

  Future<bool> _confirmExit() async {
    if (!_hasChanges || _finishing) return true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salir del reemplazo'),
        content: const Text(
          'Los datos ingresados no se han terminado. Deseas salir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuar editando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return exit == true;
  }

  Future<void> _requestClose([Object? result]) async {
    if (!await _confirmExit() || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _toggleComponent(ReplacementComponent component) async {
    if (_selected.contains(component)) {
      setState(() => _selected.remove(component));
      return;
    }

    var updateTechnicalSpecs = false;
    if (component == ReplacementComponent.motor) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Especificaciones del motor'),
          content: const Text(
            'Quieres cambiar tambien las especificaciones tecnicas del motor? Si respondes no, se conservaran los datos tecnicos actuales.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No, conservarlas'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Si, cambiarlas'),
            ),
          ],
        ),
      );
      if (answer == null || !mounted) return;
      updateTechnicalSpecs = answer;
    }

    setState(() {
      _selected.add(component);
      if (component == ReplacementComponent.motor) {
        _updateMotorTechnicalSpecs = updateTechnicalSpecs;
      }
    });
  }

  void _review() {
    if (_selected.isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _reviewing = true);
  }

  Future<void> _complete() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final request = ReplacementRequest(
      equipo: widget.equipo,
      components: {
        for (final component in _selected)
          component: _fields[component]!.toData(
            updateTechnicalSpecs: component == ReplacementComponent.motor &&
                _updateMotorTechnicalSpecs,
          ),
      },
    );

    final saver = widget.saveReplacement ?? _saveLocally;
    final result = await saver(request);
    if (!mounted) return;

    if (!result.ok) {
      setState(() => _finishing = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.error),
              SizedBox(width: 10),
              Expanded(child: Text('No se pudo guardar localmente')),
            ],
          ),
          content: Text(
            result.error ?? 'SQLite rechazo el reemplazo.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Revisar'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.teal),
            SizedBox(width: 10),
            Expanded(child: Text('Reemplazo guardado')),
          ],
        ),
        content: const Text(
          'El reemplazo fue guardado en la tablet. Queda pendiente de sincronizacion y se subira a MariaDB mediante la conexion USB con la laptop.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _requestClose(result);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.headerTop,
          foregroundColor: Colors.white,
          title: Text(_reviewing ? 'Revisar reemplazo' : 'Reemplazo de equipo'),
          leading: IconButton(
            tooltip: 'Atras',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (_reviewing) {
                setState(() => _reviewing = false);
                return;
              }
              await _requestClose();
            },
          ),
        ),
        body: _available.isEmpty
            ? _unsupportedEquipment()
            : _reviewing
                ? _reviewBody()
                : _captureBody(),
      ),
    );
  }

  Widget _unsupportedEquipment() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 14),
            const Text(
              'Composicion no configurada',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'El tipo PUNTOS ${widget.equipo.ptEq} no tiene componentes definidos para reemplazo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureBody() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _equipmentHeader(),
                const SizedBox(height: 14),
                ReplacementFocusImage(
                  equipo: widget.equipo,
                  selected: _selected,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Que componente se reemplazo?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selecciona uno o varios componentes e ingresa sus datos nuevos.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                for (final component in _available) ...[
                  _componentSection(component),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('review-replacement-button'),
                onPressed: _selected.isEmpty ? null : _review,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar reemplazo'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _componentSection(ReplacementComponent component) {
    final selected = _selected.contains(component);
    final name = _componentLabel(component);
    final slug = component.name;
    final fields = _fields[component]!;

    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.tealLight : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('component-$slug'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _toggleComponent(component),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_componentIcon(component),
                        color: selected
                            ? AppColors.tealDark
                            : AppColors.headerTop),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                    Icon(
                      selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: selected ? AppColors.teal : AppColors.borderDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  TextFormField(
                    key: Key('brand-$slug'),
                    controller: fields.brand,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Marca'),
                    validator: (value) => _required(value, 'Ingresa la marca'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: Key('model-$slug'),
                    controller: fields.model,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                    validator: (value) => _required(value, 'Ingresa el modelo'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: Key('serial-$slug'),
                    controller: fields.serial,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Serial'),
                    validator: (value) => _required(value, 'Ingresa el serial'),
                  ),
                  if (component == ReplacementComponent.motor) ...[
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        key: const Key('update-motor-technical-specs'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Cambiar especificaciones tecnicas',
                          style: TextStyle(
                            color: AppColors.headerTop,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        value: _updateMotorTechnicalSpecs,
                        activeThumbColor: AppColors.teal,
                        onChanged: (value) => setState(
                          () => _updateMotorTechnicalSpecs = value,
                        ),
                      ),
                    ),
                    if (!_updateMotorTechnicalSpecs)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Se conservaran las especificaciones actuales',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_updateMotorTechnicalSpecs) ...[
                      const SizedBox(height: 10),
                      ..._motorTechnicalFields(fields, slug),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _equipmentHeader(),
              const SizedBox(height: 14),
              ReplacementFocusImage(
                equipo: widget.equipo,
                selected: _selected,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.storage_outlined, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verifica cuidadosamente los datos. Al completar se archivara el equipo anterior y se actualizara el equipo en servicio.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final component in _selected) ...[
                _reviewComponent(component),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _reviewing = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('complete-replacement-button'),
                  onPressed: _finishing ? null : _complete,
                  icon: _finishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_finishing ? 'Guardando...' : 'Completar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewComponent(ReplacementComponent component) {
    final fields = _fields[component]!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_componentIcon(component), color: AppColors.tealDark),
              const SizedBox(width: 10),
              Text(
                _componentLabel(component),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _reviewRow('Marca', fields.brand.text.trim()),
          _reviewRow('Modelo', fields.model.text.trim()),
          _reviewRow('Serial', fields.serial.text.trim()),
          if (component == ReplacementComponent.motor &&
              _updateMotorTechnicalSpecs) ...[
            const Divider(height: 20),
            _reviewRow('Voltaje', fields.voltage.text.trim()),
            _reviewRow('Corriente', fields.current.text.trim()),
            _reviewRow('RPM', fields.rpm.text.trim()),
            _reviewRow('SF', fields.serviceFactor.text.trim()),
            _reviewRow('HP', fields.horsepower.text.trim()),
            _reviewRow('Frame', fields.frame.text.trim()),
            _reviewRow('Rod. acople', fields.driveBearing.text.trim()),
            _reviewRow('Rod. libre', fields.oppositeBearing.text.trim()),
            _reviewRow('Ciclo / Hz', fields.cycle.text.trim()),
            _reviewRow('Arranque', fields.start.text.trim()),
            _reviewRow('Fases', fields.phases.text.trim()),
            _reviewRow('Tension', fields.tension.text.trim()),
            _reviewRow('Lubricacion', fields.lubrication.text.trim()),
          ] else if (component == ReplacementComponent.motor) ...[
            const Divider(height: 20),
            const Text(
              'Las especificaciones tecnicas actuales se conservaran.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _motorTechnicalFields(
    _ReplacementFields fields,
    String slug,
  ) {
    final specs = [
      _MotorFieldSpec('voltage', 'Voltaje nominal', fields.voltage),
      _MotorFieldSpec('current', 'Corriente / FLA', fields.current),
      _MotorFieldSpec('rpm', 'RPM', fields.rpm),
      _MotorFieldSpec(
          'service-factor', 'Factor de servicio (SF)', fields.serviceFactor),
      _MotorFieldSpec('horsepower', 'Potencia (HP)', fields.horsepower),
      _MotorFieldSpec('frame', 'Frame', fields.frame),
      _MotorFieldSpec(
          'drive-bearing', 'Rodamiento lado acople', fields.driveBearing),
      _MotorFieldSpec(
          'opposite-bearing', 'Rodamiento lado libre', fields.oppositeBearing),
      _MotorFieldSpec('cycle', 'Ciclo / Hz', fields.cycle),
      _MotorFieldSpec('start', 'Tipo de arranque', fields.start),
      _MotorFieldSpec('phases', 'Fases (PH)', fields.phases),
      _MotorFieldSpec('tension', 'Tension', fields.tension),
      _MotorFieldSpec('lubrication', 'Lubricacion', fields.lubrication),
    ];

    return [
      for (final spec in specs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            key: Key('${spec.key}-$slug'),
            controller: spec.controller,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(labelText: spec.label),
            validator: null,
          ),
        ),
    ];
  }

  Widget _equipmentHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.headerTop,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.equipo.equipo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            '${widget.equipo.sistema}  |  LOC ${widget.equipo.localizacion}',
            style: const TextStyle(color: Color(0xFFB8C7DE), fontSize: 12),
          ),
          if ((widget.equipo.qrCode ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'QR ${widget.equipo.qrCode}',
              style: const TextStyle(color: Color(0xFFB8C7DE), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  static String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  Future<ReplacementSaveResult> _saveLocally(
    ReplacementRequest request,
  ) async {
    try {
      await DbHelper.instance.insertReplacement(request);
      return ReplacementSaveResult.success(
        created: request.components.length,
        updated: 0,
        unchanged: 0,
      );
    } catch (error) {
      return ReplacementSaveResult.failure(error.toString());
    }
  }

  static String _componentLabel(ReplacementComponent component) {
    switch (component) {
      case ReplacementComponent.motor:
        return 'Motor';
      case ReplacementComponent.pump:
        return 'Bomba';
      case ReplacementComponent.gearbox:
        return 'Caja';
      case ReplacementComponent.fan:
        return 'Ventilador';
    }
  }

  static IconData _componentIcon(ReplacementComponent component) {
    switch (component) {
      case ReplacementComponent.motor:
        return Icons.electric_bolt_rounded;
      case ReplacementComponent.pump:
        return Icons.water_rounded;
      case ReplacementComponent.gearbox:
        return Icons.settings_rounded;
      case ReplacementComponent.fan:
        return Icons.air_rounded;
    }
  }
}

class _ReplacementFields {
  final brand = TextEditingController();
  final model = TextEditingController();
  final serial = TextEditingController();
  final voltage = TextEditingController();
  final current = TextEditingController();
  final rpm = TextEditingController();
  final serviceFactor = TextEditingController();
  final horsepower = TextEditingController();
  final frame = TextEditingController();
  final driveBearing = TextEditingController();
  final oppositeBearing = TextEditingController();
  final cycle = TextEditingController();
  final start = TextEditingController();
  final phases = TextEditingController();
  final tension = TextEditingController();
  final lubrication = TextEditingController();

  ReplacementData toData({required bool updateTechnicalSpecs}) =>
      ReplacementData(
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
      voltage,
      current,
      rpm,
      serviceFactor,
      horsepower,
      frame,
      driveBearing,
      oppositeBearing,
      cycle,
      start,
      phases,
      tension,
      lubrication,
    ]) {
      controller.dispose();
    }
  }
}

class _MotorFieldSpec {
  const _MotorFieldSpec(
    this.key,
    this.label,
    this.controller,
  );

  final String key;
  final String label;
  final TextEditingController controller;
}
