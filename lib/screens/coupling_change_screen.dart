import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/coupling_change.dart';
import '../models/models.dart';
import '../models/operation_flow.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/avisos.dart';

class CouplingChangeScreen extends StatefulWidget {
  const CouplingChangeScreen({super.key, required this.equipo, this.odt});

  final Equipo equipo;
  final int? odt;

  @override
  State<CouplingChangeScreen> createState() => _CouplingChangeScreenState();
}

class _CouplingChangeScreenState extends State<CouplingChangeScreen> {
  final _observations = TextEditingController();
  final _modeloCoupling = TextEditingController();
  bool _cambioCoupling = false;
  bool _cambioInserto = false;
  bool _saving = false;

  @override
  void dispose() {
    _observations.dispose();
    _modeloCoupling.dispose();
    super.dispose();
  }

  Future<void> _answerNo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sin cambio de coupling'),
        content: const Text(
          'Se cerrará este módulo sin crear un registro de cambio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar No'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (widget.odt != null) {
        await DbHelper.instance.markWorkOrderServicesNotPerformed(
          widget.odt!,
          const [OperationType.couplingChange],
        );
      }
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _answerYes() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cambio de coupling'),
        content: Text(
          '¿Confirma que se realizó el cambio de coupling en '
          '${widget.equipo.equipo}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, registrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final odtText = prefs.getString('odt') ?? prefs.getString('ODT');
      final change = CouplingChange(
        uuid: const Uuid().v4(),
        localizacion: widget.equipo.localizacion,
        sistema: widget.equipo.sistema,
        fecha: DateFormat('yyyy-MM-dd').format(now),
        hora: DateFormat('HH:mm:ss').format(now),
        coupling: _cambioCoupling,
        inserto: _cambioInserto,
        modeloCoupling: _modeloCoupling.text,
        observaciones: _observations.text,
        responsable:
            prefs.getString('responsable') ?? prefs.getString('username') ?? '',
        cargo: prefs.getString('cargo') ?? prefs.getString('rol') ?? '',
        marca: widget.equipo.info?.marca ?? '',
        modelo: widget.equipo.info?.modelo ?? '',
        serial: widget.equipo.info?.serial ?? '',
        odt: widget.odt ?? prefs.getInt('odt') ?? int.tryParse(odtText ?? ''),
      );
      await DbHelper.instance.insertCouplingChange(change);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success),
              SizedBox(width: 10),
              Expanded(child: Text('Cambio guardado')),
            ],
          ),
          content: const Text(
            'Quedó pendiente en la tablet y se subirá a MOT_CPLG_REG '
            'mediante la conexión USB con la laptop.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      avisar(context, 'No se pudo guardar: ${mensajeDeError(error)}',
          AppColors.error);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type =
        widget.equipo.ptEq == 6 ? 'MOTOR – CAJA – BOMBA' : 'MOTOR – BOMBA';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(
        titulo: 'Cambio de coupling',
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.headerTop,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_input_component_rounded,
                      color: Colors.white, size: 38),
                  const SizedBox(height: 12),
                  Text(widget.equipo.equipo,
                      style: AppText.titulo.copyWith(color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('LOC-${widget.equipo.localizacion} · $type',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '¿Qué se cambió?',
              textAlign: TextAlign.center,
              style: AppText.titulo.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Puede cambiarse uno, el otro o los dos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _Interruptor(
              clave: const Key('coupling-switch'),
              titulo: 'Cambio de coupling',
              valor: _cambioCoupling,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _cambioCoupling = v),
            ),
            const SizedBox(height: 10),
            _Interruptor(
              clave: const Key('inserto-switch'),
              titulo: 'Cambio de inserto',
              valor: _cambioInserto,
              onChanged:
                  _saving ? null : (v) => setState(() => _cambioInserto = v),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('modelo-coupling'),
              controller: _modeloCoupling,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Modelo del coupling',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('coupling-yes'),
              // Sin ninguna de las dos marcadas no hay nada que registrar: para
              // eso esta el boton de abajo.
              onPressed: (_saving || !(_cambioCoupling || _cambioInserto))
                  ? null
                  : _answerYes,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('GUARDAR CAMBIO'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('coupling-no'),
              onPressed: _saving ? null : _answerNo,
              icon: const Icon(Icons.close_rounded),
              label: const Text('NO SE REALIZÓ NINGÚN CAMBIO'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 2),
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _observations,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                hintText: 'Detalle del coupling cambiado o trabajo realizado',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interruptor grande: se usa con guantes, encima de una tablet en planta.
class _Interruptor extends StatelessWidget {
  const _Interruptor({
    required this.clave,
    required this.titulo,
    required this.valor,
    required this.onChanged,
  });

  final Key clave;
  final String titulo;
  final bool valor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: valor
              ? AppColors.success.withValues(alpha: .14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: valor ? AppColors.success : AppColors.border,
            width: valor ? 1.6 : 1,
          ),
        ),
        child: SwitchListTile(
          key: clave,
          value: valor,
          onChanged: onChanged,
          activeThumbColor: AppColors.success,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            titulo,
            style: AppText.seccion.copyWith(color: AppColors.textPrimary),
          ),
        ),
      );
}
