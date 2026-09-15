import 'package:flutter/material.dart';

import '../theme.dart';

/// Selector de hora con ruedas, como el de un cronometro.
///
/// Se escribia a mano y salia de todo: '8', '8:5', '08.30', 'ocho y media'.
/// Con las ruedas la hora siempre queda en HH:mm y el mecanico no tiene que
/// pelear con el teclado usando guantes: se desliza y listo.
Future<String?> elegirHoraConRuedas(
  BuildContext context, {
  String? inicial,
  required String titulo,
}) {
  final partes = _partesDe(inicial);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (hoja) => _HojaHora(
      titulo: titulo,
      horaInicial: partes.$1,
      minutoInicial: partes.$2,
    ),
  );
}

/// Lee 'HH:mm' o 'HH:mm:ss'; si no se entiende, arranca en la hora actual.
(int, int) _partesDe(String? texto) {
  final limpio = (texto ?? '').trim();
  final match = RegExp(r'^(\d{1,2})[:.](\d{1,2})').firstMatch(limpio);
  if (match != null) {
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    if (h < 24 && m < 60) return (h, m);
  }
  final ahora = TimeOfDay.now();
  return (ahora.hour, ahora.minute);
}

class _HojaHora extends StatefulWidget {
  const _HojaHora({
    required this.titulo,
    required this.horaInicial,
    required this.minutoInicial,
  });

  final String titulo;
  final int horaInicial;
  final int minutoInicial;

  @override
  State<_HojaHora> createState() => _HojaHoraState();
}

class _HojaHoraState extends State<_HojaHora> {
  late int _hora = widget.horaInicial;
  late int _minuto = widget.minutoInicial;
  late final FixedExtentScrollController _ctrlHora =
      FixedExtentScrollController(initialItem: widget.horaInicial);
  late final FixedExtentScrollController _ctrlMinuto =
      FixedExtentScrollController(initialItem: widget.minutoInicial);

  @override
  void dispose() {
    _ctrlHora.dispose();
    _ctrlMinuto.dispose();
    super.dispose();
  }

  String get _texto =>
      '${_hora.toString().padLeft(2, '0')}:${_minuto.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.shadowLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.teal),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.titulo,
                      style: AppText.titulo
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  // La hora elegida, grande: se lee de un vistazo sin tener
                  // que interpretar donde quedaron las ruedas.
                  Text(
                    _texto,
                    key: const Key('hora-rueda-valor'),
                    style: AppText.display.copyWith(color: AppColors.teal),
                  ),
                ]),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // La banda del centro marca cual es el numero elegido.
                    IgnorePointer(
                      child: Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.teal.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _rueda(
                          clave: 'hora-rueda-horas',
                          control: _ctrlHora,
                          cantidad: 24,
                          alCambiar: (v) => setState(() => _hora = v),
                        ),
                        Text(
                          ':',
                          style: AppText.display
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        _rueda(
                          clave: 'hora-rueda-minutos',
                          control: _ctrlMinuto,
                          cantidad: 60,
                          alCambiar: (v) => setState(() => _minuto = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('hora-rueda-aceptar'),
                      onPressed: () => Navigator.pop(context, _texto),
                      child: const Text('LISTO'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rueda({
    required String clave,
    required FixedExtentScrollController control,
    required int cantidad,
    required ValueChanged<int> alCambiar,
  }) =>
      SizedBox(
        width: 92,
        child: ListWheelScrollView.useDelegate(
          key: Key(clave),
          controller: control,
          itemExtent: 42,
          perspective: 0.003,
          diameterRatio: 1.6,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: alCambiar,
          childDelegate: ListWheelChildLoopingListDelegate(
            children: [
              for (var i = 0; i < cantidad; i++)
                Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: AppText.titulo.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
