import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/models.dart';
import '../models/measurement_validation.dart';
import '../models/sesion.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/capture_summary.dart';
import '../widgets/fecha_medicion.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/measurement_advisory_banner.dart';
import '../widgets/widgets.dart';

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
    this.odt,
  });

  final Equipo equipo;
  final AlignmentMeasurement? measurementToEdit;
  final AlignmentSaveCallback? onSave;
  final int? odt;

  @override
  State<AlignmentCaptureScreen> createState() => _AlignmentCaptureScreenState();
}

class _AlignmentCaptureScreenState extends State<AlignmentCaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _observationController = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  final _fechaMedicion = FechaHoraMedicion();
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
      // El resumen junto a las observaciones refleja lo que se va escribiendo.
      _controllers[field.column]!.addListener(_refrescarResumen);
    }
    _observationController.text = widget.measurementToEdit?.observaciones ?? '';
    // Al editar, la fecha original de la medicion se conserva y el selector
    // parte de ella; en una captura nueva queda en "ahora".
    final existente = widget.measurementToEdit;
    if (existente != null) {
      _fechaMedicion.elegida =
          DateTime.tryParse('${existente.fecha} ${existente.hora}');
    }
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
    _observationController.dispose();
    super.dispose();
  }

  String? _validateValue(String? raw) {
    return MeasurementValidation.requiredNumber(raw);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final existing = widget.measurementToEdit;
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
      fecha: _fechaMedicion.fecha,
      hora: _fechaMedicion.hora,
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
      odt: existing?.odt ?? widget.odt,
    );

    try {
      if (widget.onSave != null) {
        await widget.onSave!(measurement);
      } else if (existing == null) {
        await DbHelper.instance.insertAlignment(measurement);
      } else {
        await DbHelper.instance.updateAlignment(measurement);
      }
      if (existing == null) {
        await _fechaMedicion.registrarSiManual(
          servicio: 'alineación',
          localizacion: widget.equipo.localizacion,
          uuid: measurement.uuid,
        );
      } else {
        // Corregir una alineacion existente es cosa del administrador y
        // queda en la bitacora con lo que cambio, valor por valor.
        final cambios = resumenCambios(
          {
            ...existing.valores,
            'fecha': '${existing.fecha} ${existing.hora}',
            'obs': existing.observaciones,
            'odt': existing.odt,
          },
          {
            ...measurement.valores,
            'fecha': '${measurement.fecha} ${measurement.hora}',
            'obs': measurement.observaciones,
            'odt': measurement.odt,
          },
        );
        if (cambios.isNotEmpty) {
          try {
            await DbHelper.instance.registrarEventoAdmin(
              usuario: await Sesion.usuarioActual(),
              cargo: await Sesion.cargoActual(),
              accion: 'EDICIÓN',
              servicio: 'alineación',
              localizacion: measurement.localizacion,
              uuidMedicion: measurement.uuid,
              detalle: cambios,
            );
          } catch (_) {}
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      avisar(context, 'No se pudo guardar localmente', AppColors.error);
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    await avisarGuardado(
      context,
      titulo: 'Alineación guardada',
      mensaje: 'Alineación guardada en la tablet para subirla por USB',
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sections.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: const IndustrialAppBar(
          titulo: 'Medición de alineación',
          subtitulo: 'Operación no disponible',
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.shadowMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.warningBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        color: AppColors.warning,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Alineación no disponible para este equipo',
                      textAlign: TextAlign.center,
                      style:
                          AppText.titulo.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esta operación solo aplica a equipos MOTOR–BOMBA '
                      'y MOTOR–CAJA–BOMBA.',
                      textAlign: TextAlign.center,
                      style: AppText.cuerpo.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Volver'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: IndustrialAppBar(
        titulo: widget.measurementToEdit == null
            ? 'Medición de alineación'
            : 'Revisar alineación',
        subtitulo: 'Ejes y acoples',
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
                const SizedBox(height: 16),
                AlignmentReferenceCard(puntos: widget.equipo.puntos),
                const SizedBox(height: 16),
                for (final section in _sections) ...[
                  _AlignmentCard(
                    section: section,
                    controllers: _controllers,
                    validator: _validateValue,
                  ),
                  const SizedBox(height: 14),
                ],
                // Lo capturado queda a la vista mientras escribe la
                // observacion: cada acople con sus cuatro valores.
                CaptureSummary(
                  headers: const ['Ang. V', 'Ang. H', 'Comp. V', 'Comp. H'],
                  rows: [
                    for (var i = 0; i < _sections.length; i++)
                      CaptureSummaryRow(
                        numero: '${i + 1}',
                        nombre: _sections[i]
                            .title
                            .replaceFirst('ALINEACIÓN ', '')
                            .replaceFirst('ALINEACION ', ''),
                        valores: [
                          for (final field in _sections[i].fields)
                            CaptureSummary.formatear(
                              _controllers[field.column]?.text,
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 12),
                // Para la medicion hecha antes sin la tablet a mano.
                SelectorFechaMedicion(valor: _fechaMedicion),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.headerTop, AppColors.headerBottom],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.shadowMd,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              color: AppColors.teal,
              size: 26,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipo.equipo,
                  style: AppText.seccion.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  children: [
                    _EquipmentMeta(
                      icon: Icons.account_tree_outlined,
                      label: equipo.sistema,
                    ),
                    _EquipmentMeta(
                      icon: Icons.location_on_outlined,
                      label: 'Localización ${equipo.localizacion}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentMeta extends StatelessWidget {
  const _EquipmentMeta({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.apoyo.copyWith(color: Colors.white70),
        ),
      ],
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
              style: AppText.seccion.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Registre los valores verticales y horizontales del acople',
              style: AppText.apoyo.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _AlignmentMetricGroup(
              title: 'Ángulo',
              icon: Icons.rotate_90_degrees_ccw_rounded,
              fields: section.fields.take(2).toList(),
              controllers: controllers,
              validator: validator,
            ),
            const SizedBox(height: 14),
            _AlignmentMetricGroup(
              title: 'Compensación',
              icon: Icons.open_with_rounded,
              fields: section.fields.skip(2).toList(),
              controllers: controllers,
              validator: validator,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlignmentMetricGroup extends StatelessWidget {
  const _AlignmentMetricGroup({
    required this.title,
    required this.icon,
    required this.fields,
    required this.controllers,
    required this.validator,
  });

  final String title;
  final IconData icon;
  final List<AlignmentField> fields;
  final Map<String, TextEditingController> controllers;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: AppColors.tealDark, size: 17),
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: AppText.seccion.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < fields.length; index++) ...[
            _AlignmentFieldInput(
              field: fields[index],
              controller: controllers[fields[index].column]!,
              validator: validator,
            ),
            if (index < fields.length - 1) const SizedBox(height: 12),
          ],
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MeasurementAdvisoryBanner(
          advisory: MeasurementAdvisory.alignment(
            MeasurementValidation.parseDecimal(controller.text),
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          key: Key('alignment-${field.column}'),
          controller: controller,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            MeasurementValidation.decimalFormatter(
              signed: true,
              decimalPlaces: 2,
            ),
          ],
          onChanged: (_) => (context as Element).markNeedsBuild(),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: '0,05',
            prefixIcon: Padding(
              padding: const EdgeInsets.all(11),
              child: Container(
                alignment: Alignment.center,
                width: 30,
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  field.column.endsWith('_V') ? 'V' : 'H',
                  style: AppText.micro.copyWith(color: AppColors.tealDark),
                ),
              ),
            ),
            suffixText: field.unit,
          ),
        ),
      ],
    );
  }
}
