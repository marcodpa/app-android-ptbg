import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/ajuste_correa.dart';
import '../models/measurement_validation.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/fecha_medicion.dart';
import '../widgets/formulario_industrial.dart';
import '../widgets/industrial_navigation.dart';

/// Ajuste de correa de un ventilador o un fin-fan (MOT_AJC_REG).
///
/// Solo los equipos de tipo 4 y 5 llevan correa. El formato oficial ya traia
/// su linea —"AJUSTE DE CORREAS: SI / NO ; TENSION"— pero no habia donde
/// llenarla desde la tablet y salia siempre en blanco.
class BeltAdjustmentScreen extends StatefulWidget {
  const BeltAdjustmentScreen({
    super.key,
    required this.equipo,
    this.odt,
  });

  final Equipo equipo;
  final int? odt;

  @override
  State<BeltAdjustmentScreen> createState() => _BeltAdjustmentScreenState();
}

class _BeltAdjustmentScreenState extends State<BeltAdjustmentScreen> {
  /// null = sin responder. Obliga a tocar una de las dos: un formulario que
  /// llega con "NO" puesto se guarda sin que nadie mire la correa.
  bool? _ajustada;
  final _tension = TextEditingController();
  final _observaciones = TextEditingController();
  final _fechaMedicion = FechaHoraMedicion();
  final _faltantes = ValueNotifier<Map<int, int>>(const {});
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _tension.addListener(_recontar);
    _recontar();
  }

  @override
  void dispose() {
    _tension.dispose();
    _observaciones.dispose();
    _faltantes.dispose();
    super.dispose();
  }

  void _recontar() {
    var faltan = 0;
    if (_ajustada == null) faltan++;
    // La tension solo se exige cuando se ajusto: si no se toco la correa, no
    // hay tension nueva que anotar.
    if (_ajustada == true && _tension.text.trim().isEmpty) faltan++;
    _faltantes.value = {0: faltan};
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ajuste = AjusteCorrea(
        uuid: const Uuid().v4(),
        localizacion: widget.equipo.localizacion,
        sistema: widget.equipo.sistema,
        fecha: _fechaMedicion.fecha,
        hora: _fechaMedicion.hora,
        ajustada: _ajustada ?? false,
        tension: MeasurementValidation.parseDecimal(_tension.text),
        observaciones: _observaciones.text.trim(),
        responsable:
            prefs.getString('responsable') ?? prefs.getString('username') ?? '',
        cargo: prefs.getString('cargo') ?? prefs.getString('rol') ?? '',
        marca: widget.equipo.info?.marca ?? '',
        modelo: widget.equipo.info?.modelo ?? '',
        serial: widget.equipo.info?.serial ?? '',
        odt: widget.odt,
      );
      await DbHelper.instance.insertAjusteCorrea(ajuste);
      await _fechaMedicion.registrarSiManual(
        servicio: 'ajuste de correa',
        localizacion: widget.equipo.localizacion,
        uuid: ajuste.uuid,
      );
      if (!mounted) return;
      await avisarGuardado(
        context,
        titulo: 'Ajuste de correa guardado',
        mensaje: 'Quedó guardado en la tablet y aparecerá en Sincronización '
            'hasta que se envíe a la planta.',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      avisar(context, 'No se pudo guardar: $error', AppColors.error);
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(titulo: 'Ajuste de correa'),
      body: Column(
        children: [
          _cabecera(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                const Text('¿Se ajustó la correa?', style: AppText.seccion),
                const SizedBox(height: 4),
                Text(
                  'Un NO también se registra: deja constancia de que se revisó '
                  'y no hizo falta tocarla.',
                  style: AppText.apoyo
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OpcionBinaria(
                      texto: 'SÍ',
                      elegido: _ajustada == true,
                      color: AppColors.success,
                      onTap: () {
                        setState(() => _ajustada = true);
                        _recontar();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OpcionBinaria(
                      texto: 'NO',
                      elegido: _ajustada == false,
                      color: AppColors.textSecondary,
                      onTap: () {
                        setState(() => _ajustada = false);
                        _recontar();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('correa-tension'),
                  controller: _tension,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MeasurementValidation.decimalFormatter(signed: false)],
                  decoration: InputDecoration(
                    labelText: _ajustada == true
                        ? 'Tensión de la correa'
                        : 'Tensión de la correa (opcional)',
                    helperText: 'Lectura del tensiómetro',
                    prefixIcon: const Icon(Icons.speed_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('correa-observaciones'),
                  controller: _observaciones,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SelectorFechaMedicion(valor: _fechaMedicion),
              ],
            ),
          ),
          PieFormulario(
            faltantes: _faltantes,
            textoBoton: 'GUARDAR AJUSTE',
            guardando: _guardando,
            onGuardar: _guardar,
          ),
        ],
      ),
    );
  }

  Widget _cabecera() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.teal.withValues(alpha: .20),
              AppColors.teal.withValues(alpha: .06),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.teal.withValues(alpha: .40)),
        ),
        child: Row(children: [
          const Icon(Icons.settings_backup_restore_rounded,
              size: 22, color: AppColors.teal),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.equipo.equipo,
                    style: AppText.seccion.copyWith(color: AppColors.teal)),
                Text(
                  '${widget.equipo.qrDisplay} · LOC '
                  '${widget.equipo.localizacion}',
                  maxLines: 2,
                  style: AppText.apoyo
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ]),
      );
}
