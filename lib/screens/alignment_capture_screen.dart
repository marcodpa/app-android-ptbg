import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/models.dart';
import '../theme.dart';

typedef AlignmentSaveCallback = Future<void> Function(
  AlignmentMeasurement measurement,
);

String _formatAlignmentValue(double value) {
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text.replaceAll('.', ',');
}

class AlignmentCaptureScreen extends StatefulWidget {
  const AlignmentCaptureScreen({
    super.key,
    required this.equipo,
    this.measurementToEdit,
    this.onSave,
  });

  final Equipo equipo;
  final AlignmentMeasurement? measurementToEdit;
  final AlignmentSaveCallback? onSave;

  @override
  State<AlignmentCaptureScreen> createState() => _AlignmentCaptureScreenState();
}

class _AlignmentCaptureScreenState extends State<AlignmentCaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _observationController = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  late final List<AlignmentSection> _sections;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sections = AlignmentPlanResolver.fromPuntos(widget.equipo.puntos);
    for (final field in _sections.expand((section) => section.fields)) {
      final previous = widget.measurementToEdit?.valores[field.column];
      _controllers[field.column] = TextEditingController(
        text: previous == null ? '' : _formatAlignmentValue(previous),
      );
    }
    _observationController.text = widget.measurementToEdit?.observaciones ?? '';
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _observationController.dispose();
    super.dispose();
  }

  String? _validateValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Valor obligatorio';
    if (parseAlignmentValue(value) == null) {
      return 'Use coma y máximo 2 decimales';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final existing = widget.measurementToEdit;
    final now = DateTime.now();
    var responsable = existing?.responsable ?? '';
    var cargo = existing?.cargo ?? '';
    try {
      final prefs = await SharedPreferences.getInstance();
      responsable = (prefs.getString('responsable') ??
              prefs.getString('username') ??
              responsable)
          .trim();
      cargo =
          (prefs.getString('cargo') ?? prefs.getString('rol') ?? cargo).trim();
    } catch (_) {}

    EquipoInfo? info = widget.equipo.info;
    if (info == null || info.isEmpty) {
      try {
        info =
            await DbHelper.instance.getEquipoInfo(widget.equipo.localizacion);
      } catch (_) {}
    }

    final measurement = AlignmentMeasurement(
      uuid: existing?.uuid ?? const Uuid().v4(),
      localizacion: widget.equipo.localizacion,
      sistema: widget.equipo.sistema,
      puntos: widget.equipo.puntos,
      fecha: existing?.fecha ?? DateFormat('yyyy-MM-dd').format(now),
      hora: existing?.hora ?? DateFormat('HH:mm:ss').format(now),
      valores: {
        for (final entry in _controllers.entries)
          entry.key: parseAlignmentValue(entry.value.text),
      },
      observaciones: _observationController.text.trim().isEmpty
          ? null
          : _observationController.text.trim(),
      responsable: responsable,
      cargo: cargo,
      marca: info?.marca ?? existing?.marca,
      modelo: info?.modelo ?? existing?.modelo,
      serial: info?.serial ?? existing?.serial,
      odt: null,
    );

    try {
      if (widget.onSave != null) {
        await widget.onSave!(measurement);
      } else if (existing == null) {
        await DbHelper.instance.insertAlignment(measurement);
      } else {
        await DbHelper.instance.updateAlignment(measurement);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar localmente'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alineación guardada'),
        content: const Text(
          'Alineación guardada en la tablet para subirla por USB',
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.headerTop,
        foregroundColor: Colors.white,
        title: Text(
          widget.measurementToEdit == null
              ? 'Medición de alineación'
              : 'Revisar alineación',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EquipmentHeader(equipo: widget.equipo),
                const SizedBox(height: 14),
                for (final section in _sections) ...[
                  _AlignmentCard(
                    section: section,
                    controllers: _controllers,
                    validator: _validateValue,
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  key: const Key('alignment-observations'),
                  controller: _observationController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  key: const Key('alignment-save-button'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Guardando…' : 'Guardar alineación'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EquipmentHeader extends StatelessWidget {
  const _EquipmentHeader({required this.equipo});

  final Equipo equipo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              equipo.equipo,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text('${equipo.sistema} · Localización ${equipo.localizacion}'),
          ],
        ),
      ),
    );
  }
}

class _AlignmentCard extends StatelessWidget {
  const _AlignmentCard({
    required this.section,
    required this.controllers,
    required this.validator,
  });

  final AlignmentSection section;
  final Map<String, TextEditingController> controllers;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.headerTop,
                  ),
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < section.fields.length; index++) ...[
              _AlignmentFieldInput(
                field: section.fields[index],
                controller: controllers[section.fields[index].column]!,
                validator: validator,
              ),
              if (index < section.fields.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlignmentFieldInput extends StatelessWidget {
  const _AlignmentFieldInput({
    required this.field,
    required this.controller,
    required this.validator,
  });

  final AlignmentField field;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: Key('alignment-${field.column}'),
      controller: controller,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: field.label,
        suffixText: field.unit,
      ),
    );
  }
}
