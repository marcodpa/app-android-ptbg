import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/operation_flow.dart';
import '../theme.dart';
import 'alignment_capture_screen.dart';
import 'capture_screen.dart';
import 'replacement_screen.dart';
import 'temperature_capture_screen.dart';

typedef OperationLauncher = Future<bool?> Function(
  BuildContext context,
  OperationType operation,
  Equipo equipo,
);

class OperationSelectionScreen extends StatefulWidget {
  const OperationSelectionScreen({
    super.key,
    required this.equipo,
    this.launcher,
  });

  final Equipo equipo;
  final OperationLauncher? launcher;

  @override
  State<OperationSelectionScreen> createState() =>
      _OperationSelectionScreenState();
}

class _OperationSelectionScreenState extends State<OperationSelectionScreen> {
  final Set<OperationType> _selected = <OperationType>{};
  OperationType? _first;
  bool _opening = false;

  bool get _canStart =>
      !_opening &&
      (_selected.length == 1 || (_selected.length > 1 && _first != null));

  void _toggle(OperationType operation) {
    setState(() {
      if (!_selected.add(operation)) {
        _selected.remove(operation);
      }
      if (_selected.length == 1) {
        _first = _selected.first;
      } else {
        _first = null;
      }
    });
  }

  Future<void> _start() async {
    if (!_canStart) return;
    final first = _first ?? _selected.first;
    final flow = OperationFlow(selected: _selected.toList(), current: first);
    final ordered = <OperationType>[flow.current, ...flow.pending];
    setState(() => _opening = true);
    await _runOperations(ordered, 0);
  }

  Future<void> _runOperations(
    List<OperationType> operations,
    int index,
  ) async {
    final completed = await _launcher(
      context,
      operations[index],
      widget.equipo,
    );
    if (!mounted) return;
    if (completed != true) {
      setState(() => _opening = false);
      return;
    }
    final nextIndex = index + 1;
    if (nextIndex >= operations.length) {
      setState(() => _opening = false);
      Navigator.pop(context);
      return;
    }
    final next = operations[nextIndex];
    final continueFlow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operacion completada'),
        content: Text('Deseas continuar con ${_label(next)}?'),
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
      setState(() => _opening = false);
      Navigator.pop(context);
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
        screen = CaptureScreen(equipo: equipo);
      case OperationType.temperature:
        screen = TemperatureCaptureScreen(equipo: equipo);
      case OperationType.replacement:
        screen = ReplacementScreen(equipo: equipo);
      case OperationType.alignment:
        screen = AlignmentCaptureScreen(equipo: equipo);
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
      case OperationType.replacement:
        return 'Reemplazo de equipo';
      case OperationType.alignment:
        return 'Alineación';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.headerTop,
        foregroundColor: Colors.white,
        title: const Text('Iniciar medicion'),
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
                  const Text(
                    'Que deseas realizar?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Puedes seleccionar una o varias operaciones.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
                  if (_selected.length > 1) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Elige cual comienza',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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
              ),
            ),
            Container(
              color: AppColors.surface,
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
        color: AppColors.headerTop,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing_outlined,
              color: AppColors.teal, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.equipo.equipo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.equipo.sistema}  |  LOC ${widget.equipo.localizacion}',
                  style:
                      const TextStyle(color: Color(0xFFB8C7DE), fontSize: 12),
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
      color: selected ? AppColors.tealLight : AppColors.surface,
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
              Icon(icon,
                  size: 34,
                  color: selected ? AppColors.tealDark : AppColors.headerTop),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
        foregroundColor: selected ? Colors.white : AppColors.headerTop,
        backgroundColor: selected ? AppColors.headerTop : AppColors.surface,
        side: BorderSide(
          color: selected ? AppColors.headerTop : AppColors.borderDark,
        ),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  static String _shortLabel(OperationType operation) {
    switch (operation) {
      case OperationType.vibration:
        return 'Vibracion';
      case OperationType.temperature:
        return 'Temperatura';
      case OperationType.replacement:
        return 'Reemplazo';
      case OperationType.alignment:
        return 'Alineación';
    }
  }
}
