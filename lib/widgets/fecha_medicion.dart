import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/sesion.dart';
import '../theme.dart';
import 'avisos.dart';

/// Fecha y hora reales en que se hizo la medicion.
///
/// Por defecto queda vacia y la medicion se estampa con la hora del guardado,
/// como siempre. Retro-fechar es potestad exclusiva del administrador (el
/// mecanico ni siquiera ve el selector: si pudiera elegir la fecha, las
/// rondas podrian "hacerse" desde la oficina). Cada retro-fechado queda en
/// la bitacora EVENTOS_ADMIN via [registrarSiManual].
class FechaHoraMedicion {
  DateTime? elegida;

  bool get manual => elegida != null;
  DateTime get efectiva => elegida ?? DateTime.now();
  String get fecha => DateFormat('yyyy-MM-dd').format(efectiva);
  String get hora => DateFormat('HH:mm:ss').format(efectiva);

  /// Deja constancia en la bitacora si la medicion se guardo retro-fechada.
  /// Llamar despues de un guardado exitoso; con la fecha automatica no anota
  /// nada. Nunca lanza: la medicion ya esta guardada y un tropiezo anotando
  /// el evento no debe romperle la pantalla al usuario.
  Future<void> registrarSiManual({
    required String servicio,
    required int localizacion,
    required String uuid,
  }) async {
    if (!manual) return;
    try {
      await DbHelper.instance.registrarEventoAdmin(
        usuario: await Sesion.usuarioActual(),
        cargo: await Sesion.cargoActual(),
        accion: 'FECHA MANUAL',
        servicio: servicio,
        localizacion: localizacion,
        uuidMedicion: uuid,
        detalle: 'Guardada con fecha $fecha $hora en lugar de la actual',
      );
    } catch (_) {}
  }
}

/// Fila discreta junto a la observacion. Solo el administrador la ve;
/// normalmente informa que la medicion se guardara con la hora actual y
/// ofrece cambiarla para el caso excepcional del trabajo hecho antes.
class SelectorFechaMedicion extends StatefulWidget {
  const SelectorFechaMedicion({super.key, required this.valor});

  final FechaHoraMedicion valor;

  @override
  State<SelectorFechaMedicion> createState() => _SelectorFechaMedicionState();
}

class _SelectorFechaMedicionState extends State<SelectorFechaMedicion> {
  bool _esAdmin = false;

  @override
  void initState() {
    super.initState();
    Sesion.esAdmin().then((admin) {
      if (mounted && admin) setState(() => _esAdmin = true);
    });
  }

  Future<void> _elegir() async {
    final ahora = DateTime.now();
    final base = widget.valor.elegida ?? ahora;
    final dia = await showDatePicker(
      context: context,
      initialDate: base,
      // Un retraso de dias es lo normal; mas de dos meses ya no es "se me
      // quedo la tablet", y las fechas futuras no existen para una medicion.
      firstDate: ahora.subtract(const Duration(days: 60)),
      lastDate: ahora,
      helpText: 'Fecha en que se hizo la medición',
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Hora en que se hizo la medición',
    );
    if (hora == null || !mounted) return;
    final elegida =
        DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    if (elegida.isAfter(DateTime.now())) {
      avisar(context, 'La hora de la medición no puede ser futura',
          AppColors.warning);
      return;
    }
    setState(() => widget.valor.elegida = elegida);
  }

  @override
  Widget build(BuildContext context) {
    if (!_esAdmin) return const SizedBox.shrink();
    final manual = widget.valor.manual;
    final color = manual ? AppColors.teal : AppColors.textSecondary;
    final texto = manual
        ? 'Hecha el '
            '${DateFormat('dd/MM/yyyy').format(widget.valor.elegida!)} a las '
            '${DateFormat('HH:mm').format(widget.valor.elegida!)}'
        : 'Se guardará con la fecha y hora actual';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: manual
              ? AppColors.teal.withValues(alpha: 0.55)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
          if (manual)
            IconButton(
              key: const Key('fecha-medicion-reset'),
              tooltip: 'Volver a la hora actual',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 17),
              onPressed: () => setState(() => widget.valor.elegida = null),
            ),
          TextButton(
            key: const Key('fecha-medicion-cambiar'),
            onPressed: _elegir,
            child: Text(manual ? 'Cambiar' : '¿Se hizo antes?'),
          ),
        ],
      ),
    );
  }
}
