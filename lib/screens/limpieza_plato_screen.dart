import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../models/limpieza_plato.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/avisos.dart';

class LimpiezaPlatoScreen extends StatefulWidget {
  const LimpiezaPlatoScreen(
      {super.key,
      required this.equipo,
      required this.odt,
      this.onSave,
      this.reloj});
  final Equipo equipo;
  final int odt;
  final Future<void> Function(LimpiezaPlato)? onSave;
  final DateTime Function()? reloj;

  @override
  State<LimpiezaPlatoScreen> createState() => _LimpiezaPlatoScreenState();
}

class _LimpiezaPlatoScreenState extends State<LimpiezaPlatoScreen> {
  final _form = GlobalKey<FormState>();
  final _horas = TextEditingController();
  final _observaciones = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _horas.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando ||
        widget.equipo.ptEq != 10 ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final instante = (widget.reloj ?? DateTime.now)().toIso8601String();
      final limpieza = LimpiezaPlato(
        uuid: const Uuid().v4(),
        localizacion: widget.equipo.localizacion,
        fecha: instante.substring(0, 10),
        hora: instante.substring(11, 19),
        horasFuncionamiento: LimpiezaPlato.leerHorometro(_horas.text)!,
        odt: widget.odt,
        observaciones: _observaciones.text.trim(),
        responsable:
            prefs.getString('responsable') ?? prefs.getString('username') ?? '',
        cargo: prefs.getString('cargo') ?? prefs.getString('rol') ?? '',
        marca: widget.equipo.info?.marca ?? '',
        modelo: widget.equipo.info?.modelo ?? '',
        serial: widget.equipo.info?.serial ?? '',
      );
      await (widget.onSave ?? DbHelper.instance.insertLimpiezaPlato)(limpieza);
      if (!mounted) return;
      await avisarGuardado(context,
          titulo: 'Limpieza de plato guardada',
          mensaje:
              'Guardada en la tablet. Se enviará a la planta con el uploader seguro.');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      avisar(context, 'No se pudo guardar: ${mensajeDeError(error)}',
          AppColors.error);
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: const IndustrialAppBar(titulo: 'Limpieza de plato'),
        body: widget.equipo.ptEq != 10
            ? const Center(
                child: Text(
                    'Este servicio es exclusivo de los separadores tipo 10.'))
            : SafeArea(
                child: Form(
                    key: _form,
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      Text(widget.equipo.qrDisplay, style: AppText.titulo),
                      Text('ODT ${widget.odt} · Motor del separador',
                          style: AppText.apoyo),
                      const SizedBox(height: 16),
                      const Text('Registrar limpieza realizada',
                          style: AppText.seccion),
                      const SizedBox(height: 8),
                      const Text(
                          'La fecha y hora se guardan automáticamente al confirmar. '
                          'Las horas corresponden al total acumulado del horómetro.'),
                      const SizedBox(height: 20),
                      TextFormField(
                          key: const Key('plato-horometro'),
                          controller: _horas,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Horas del horómetro',
                              suffixText: 'h',
                              border: OutlineInputBorder()),
                          validator: (value) => LimpiezaPlato.leerHorometro(
                                      value ?? '') ==
                                  null
                              ? 'Ingrese horas enteras entre 0 y 2147483647.'
                              : null),
                      const SizedBox(height: 16),
                      TextFormField(
                          key: const Key('plato-observaciones'),
                          controller: _observaciones,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              labelText: 'Observaciones (opcional)',
                              border: OutlineInputBorder())),
                      const SizedBox(height: 16),
                      Text(
                          'Datos del motor: ${widget.equipo.info?.marca ?? "—"} · '
                          '${widget.equipo.info?.modelo ?? "—"} · ${widget.equipo.info?.serial ?? "—"}'),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                          key: const Key('plato-guardar'),
                          onPressed: _guardando ? null : _guardar,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                              _guardando ? 'Guardando…' : 'GUARDAR LIMPIEZA')),
                    ]))),
      );
}

class HistorialLimpiezaPlatoScreen extends StatefulWidget {
  const HistorialLimpiezaPlatoScreen({super.key, required this.equipo});
  final Equipo equipo;
  @override
  State<HistorialLimpiezaPlatoScreen> createState() =>
      _HistorialLimpiezaPlatoScreenState();
}

class _HistorialLimpiezaPlatoScreenState
    extends State<HistorialLimpiezaPlatoScreen> {
  late final _datos = DbHelper.instance
      .getLimpiezasPlato(localizacion: widget.equipo.localizacion);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar:
            const IndustrialAppBar(titulo: 'Historial de limpieza de plato'),
        body: FutureBuilder<List<LimpiezaPlato>>(
            future: _datos,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                    child: Text(
                        'No se pudo cargar el historial. Vuelva a intentarlo.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final filas = snapshot.data!;
              if (filas.isEmpty) {
                return const Center(
                    child: Text(
                        'Todavía no hay limpiezas registradas para este equipo.'));
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text(widget.equipo.qrDisplay, style: AppText.titulo),
                for (final fila in filas)
                  Card(
                      child: ListTile(
                    leading: const Icon(Icons.cleaning_services_rounded),
                    title: Text(
                        '${fila.fecha} ${fila.hora} · ${fila.horasFuncionamiento} h'),
                    subtitle: Text(
                        'ODT ${fila.odt} · ${fila.sincronizado ? "Sincronizado" : "Pendiente de envío"}\n'
                        '${fila.responsable} · ${fila.cargo}\n${fila.marca} · ${fila.modelo} · ${fila.serial}\n${fila.observaciones}'),
                  )),
              ]);
            }),
      );
}
