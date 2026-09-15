import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/operation_flow.dart';
import '../theme.dart';
import '../db/db_helper.dart';
import 'alignment_capture_screen.dart';
import 'capture_screen.dart';
import 'replacement_screen.dart';
import 'temperature_capture_screen.dart';
import 'lubrication_capture_screen.dart';
import 'belt_adjustment_screen.dart';
import 'limpieza_plato_screen.dart';
import 'coupling_change_screen.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/avisos.dart';

typedef OperationLauncher = Future<bool?> Function(
  BuildContext context,
  OperationType operation,
  Equipo equipo,
);
typedef WorkOrderCreator = Future<int> Function(
  Equipo equipo,
  Set<OperationType> services,
);

class OperationSelectionScreen extends StatefulWidget {
  const OperationSelectionScreen({
    super.key,
    required this.equipo,
    this.launcher,
    this.workOrderCreator,
  });

  final Equipo equipo;
  final OperationLauncher? launcher;
  final WorkOrderCreator? workOrderCreator;

  @override
  State<OperationSelectionScreen> createState() =>
      _OperationSelectionScreenState();
}

class _OperationSelectionScreenState extends State<OperationSelectionScreen> {
  final Set<OperationType> _selected = <OperationType>{};
  OperationType? _first;
  bool _opening = false;
  int? _activeOdt;
  late Equipo _flowEquipo;

  @override
  void initState() {
    super.initState();
    _flowEquipo = widget.equipo;
  }

  bool get _canStart =>
      !_opening &&
      (_selected.length == 1 ||
          _selected.contains(OperationType.replacement) ||
          (_selected.length > 1 && _first != null));

  void _toggle(OperationType operation) {
    setState(() {
      if (!_selected.add(operation)) {
        _selected.remove(operation);
      }
      if (_selected.length == 1) {
        _first = _selected.first;
      } else if (_selected.contains(OperationType.replacement)) {
        _first = OperationType.replacement;
      } else {
        _first = null;
      }
    });
  }

  Future<void> _start() async {
    if (!_canStart) return;
    if (widget.launcher == null) {
      try {
        final services = Set<OperationType>.from(_selected);
        _activeOdt = widget.workOrderCreator != null
            ? await widget.workOrderCreator!(widget.equipo, services)
            : await DbHelper.instance.createWorkOrder(
                equipo: widget.equipo,
                services: services,
              );
      } catch (error) {
        if (!mounted) return;
        avisar(context, 'No se pudo generar la ODT: ${mensajeDeError(error)}',
            AppColors.error);
        return;
      }
    }
    final first = _selected.contains(OperationType.replacement)
        ? OperationType.replacement
        : (_first ?? _selected.first);
    final flow = OperationFlow(selected: _selected.toList(), current: first);
    final ordered = <OperationType>[flow.current, ...flow.pending];
    setState(() => _opening = true);
    await _runOperations(ordered, 0);
  }

  Future<void> _runOperations(List<OperationType> operations, int index) async {
    final completed = await _launcher(
      context,
      operations[index],
      _flowEquipo,
    );
    if (!mounted) return;
    if (completed != true) {
      if (_activeOdt != null) {
        await DbHelper.instance.markWorkOrderServicesNotPerformed(
          _activeOdt!,
          operations.skip(index),
        );
      }
      setState(() => _opening = false);
      return;
    }
    if (operations[index] == OperationType.replacement &&
        widget.launcher == null) {
      final updatedInfo =
          await DbHelper.instance.getEquipoInfo(widget.equipo.localizacion);
      if (updatedInfo != null) {
        _flowEquipo = widget.equipo.copyWith(info: updatedInfo);
      }
    }
    final nextIndex = index + 1;
    // Se llega hasta aqui despues de varios await; sin esta comprobacion el
    // context puede estar muerto y tanto el pop como el dialogo fallan.
    if (!mounted) return;
    if (nextIndex >= operations.length) {
      setState(() => _opening = false);
      Navigator.pop(context);
      return;
    }
    final next = operations[nextIndex];
    final navegador = Navigator.of(context);
    final continueFlow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operación completada'),
        content: Text('¿Deseas continuar con ${_label(next)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Finalizar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Continuar con ${_label(next)}'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (continueFlow != true) {
      if (_activeOdt != null) {
        await DbHelper.instance.markWorkOrderServicesNotPerformed(
          _activeOdt!,
          operations.skip(nextIndex),
        );
      }
      if (!mounted) return;
      setState(() => _opening = false);
      navegador.pop();
      return;
    }
    await _runOperations(operations, nextIndex);
  }

  Future<bool?> _launcher(
    BuildContext context,
    OperationType operation,
    Equipo equipo,
  ) {
    if (widget.launcher != null) {
      return widget.launcher!(context, operation, equipo);
    }
    final Widget screen;
    switch (operation) {
      case OperationType.vibration:
        screen = CaptureScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.temperature:
        screen = TemperatureCaptureScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.lubrication:
        screen = LubricationCaptureScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.replacement:
        screen = ReplacementScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.alignment:
        screen = AlignmentCaptureScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.couplingChange:
        screen = CouplingChangeScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.beltAdjustment:
        screen = BeltAdjustmentScreen(equipo: equipo, odt: _activeOdt);
      case OperationType.plateCleaning:
        screen = LimpiezaPlatoScreen(equipo: equipo, odt: _activeOdt!);
    }
    return Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => screen),
    );
  }

  static String _label(OperationType operation) {
    switch (operation) {
      case OperationType.vibration:
        return 'Vibracion';
      case OperationType.temperature:
        return 'Medición de temperatura';
      case OperationType.lubrication:
        return 'Lubricación';
      case OperationType.replacement:
        return 'Reemplazo de equipo';
      case OperationType.alignment:
        return 'Alineación';
      case OperationType.couplingChange:
        return 'Cambio de coupling';
      case OperationType.beltAdjustment:
        return 'Ajuste de correa';
      case OperationType.plateCleaning:
        return 'Limpieza de plato';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(
        titulo: 'Iniciar medición',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _equipmentSummary(),
                  const SizedBox(height: 22),
                  Text(
                    'Que deseas realizar?',
                    style: AppText.titulo.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Puedes seleccionar una o varias operaciones.',
                    style: AppText.subtitulo.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _operationTile(
                    key: const Key('operation-vibration'),
                    operation: OperationType.vibration,
                    icon: Icons.graphic_eq_rounded,
                    title: 'Vibracion',
                    subtitle: 'Captura guiada de los puntos del equipo',
                  ),
                  const SizedBox(height: 12),
                  _operationTile(
                    key: const Key('operation-temperature'),
                    operation: OperationType.temperature,
                    icon: Icons.thermostat_rounded,
                    title: 'Medición de temperatura',
                    subtitle: 'Captura guiada de una lectura en °C por punto',
                  ),
                  const SizedBox(height: 12),
                  if (widget.equipo.puntos >= 1 &&
                      widget.equipo.puntos <= 10) ...[
                    _operationTile(
                      key: const Key('operation-lubrication'),
                      operation: OperationType.lubrication,
                      icon: Icons.oil_barrel_rounded,
                      title: 'Lubricación',
                      subtitle: 'Registrar los gramos aplicados por punto',
                    ),
                  ],
                  if (AlignmentPlanResolver.isEligible(
                    widget.equipo.puntos,
                  )) ...[
                    const SizedBox(height: 12),
                    _operationTile(
                      key: const Key('operation-alignment'),
                      operation: OperationType.alignment,
                      icon: Icons.straighten_rounded,
                      title: 'Alineación',
                      subtitle: 'Registrar la alineación del conjunto',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _operationTile(
                    key: const Key('operation-replacement'),
                    operation: OperationType.replacement,
                    icon: Icons.build_circle_outlined,
                    title: 'Reemplazo de equipo',
                    subtitle: 'Registrar cambio de componentes',
                  ),
                  if (CouplingChangeResolver.isEligible(
                    widget.equipo.ptEq,
                  )) ...[
                    const SizedBox(height: 12),
                    _operationTile(
                      key: const Key('operation-coupling-change'),
                      operation: OperationType.couplingChange,
                      icon: Icons.settings_input_component_rounded,
                      title: 'Cambio de coupling',
                      subtitle: 'Confirmar si se realizó el cambio (Sí o No)',
                    ),
                  ],
                  if (BeltAdjustmentResolver.isEligible(
                    widget.equipo.ptEq,
                  )) ...[
                    const SizedBox(height: 12),
                    _operationTile(
                      key: const Key('operation-belt-adjustment'),
                      operation: OperationType.beltAdjustment,
                      icon: Icons.settings_backup_restore_rounded,
                      title: 'Ajuste de correa',
                      subtitle: 'Registrar el ajuste y la tensión',
                    ),
                  ],
                  if (widget.equipo.ptEq == 10) ...[
                    const SizedBox(height: 12),
                    _operationTile(
                        key: const Key('operation-plate-cleaning'),
                        operation: OperationType.plateCleaning,
                        icon: Icons.cleaning_services_rounded,
                        title: 'Limpieza de plato',
                        subtitle: 'Registrar limpieza y horas del horómetro'),
                  ],
                  if (_selected.length > 1) ...[
                    const SizedBox(height: 24),
                    if (_selected.contains(OperationType.replacement))
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: AppColors.warning),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'El reemplazo se guardará primero. Las demás mediciones usarán los datos nuevos del equipo.',
                                style: AppText.cuerpoFuerte.copyWith(
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Text(
                        'Elige cual comienza',
                        style: AppText.seccion.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _selected
                            .map(
                              (operation) => _firstChoice(
                                operation,
                                'Primero ${_shortLabel(operation)}',
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Container(
              color: esterThemeController.isDark
                  ? AppColors.surface
                  : Colors.white,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('start-operations-button'),
                  onPressed: _canStart ? _start : null,
                  icon: _opening
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Comenzar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _equipmentSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esterThemeController.isDark ? AppColors.headerTop : Colors.white,
        border: esterThemeController.isDark
            ? null
            : Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.precision_manufacturing_outlined,
            color: AppColors.teal,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.equipo.equipo,
                  style: AppText.seccion.copyWith(
                    color: esterThemeController.isDark
                        ? Colors.white
                        : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.equipo.sistema}  |  LOC ${widget.equipo.localizacion}',
                  style: AppText.apoyo.copyWith(
                    color: esterThemeController.isDark
                        ? const Color(0xFFB8C7DE)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _operationTile({
    required Key key,
    required OperationType operation,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selected.contains(operation);
    return Material(
      key: key,
      color: selected
          ? AppColors.teal.withValues(alpha: .14)
          : esterThemeController.isDark
              ? AppColors.surface
              : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _toggle(operation),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 34,
                color: selected ? AppColors.teal : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.seccion.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppText.apoyo.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.teal : AppColors.borderDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _firstChoice(OperationType operation, String text) {
    final selected = _first == operation;
    return OutlinedButton(
      onPressed: () => setState(() => _first = operation),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : AppColors.textPrimary,
        backgroundColor: selected ? AppColors.tealDark : AppColors.surface2,
        side: BorderSide(
          color: selected ? AppColors.teal : AppColors.borderDark,
        ),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  static String _shortLabel(OperationType operation) {
    switch (operation) {
      case OperationType.plateCleaning:
        return 'Limpieza de plato';
      case OperationType.vibration:
        return 'Vibracion';
      case OperationType.temperature:
        return 'Temperatura';
      case OperationType.lubrication:
        return 'Lubricación';
      case OperationType.replacement:
        return 'Reemplazo';
      case OperationType.alignment:
        return 'Alineación';
      case OperationType.couplingChange:
        return 'Coupling';
      case OperationType.beltAdjustment:
        return 'Correa';
    }
  }
}
