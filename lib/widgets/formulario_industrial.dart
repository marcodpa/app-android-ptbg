import 'package:flutter/material.dart';

import '../theme.dart';

/// Piezas compartidas de los formularios de captura.
///
/// El acordeon, la opcion binaria y el pie de "faltan N datos" estaban
/// duplicados —y hasta triplicados— entre el registro de equipo nuevo, el
/// check list de compresor y el de black start. Viven aqui para que las tres
/// pantallas se vean y se comporten igual con una sola copia que mantener.

/// Una seccion plegable del formulario. Existia clonada casi byte a byte en
/// nuevo_equipo_screen y checklist_compresor_screen.
///
/// El contenido solo se construye cuando esta abierta: con todas abiertas
/// serian decenas de cajas de texto vivas a la vez y la pantalla se arrastra
/// al escribir. Los controladores viven en el State del formulario, asi que
/// plegar no pierde lo escrito.
class SeccionPlegable extends StatelessWidget {
  const SeccionPlegable({
    super.key,
    required this.indice,
    required this.abierta,
    required this.icono,
    required this.titulo,
    required this.resumen,
    required this.explicacion,
    required this.faltantes,
    required this.onTap,
    required this.hijo,
  });

  final int indice;
  final bool abierta;
  final IconData icono;
  final String titulo;
  final String resumen;
  final String explicacion;

  /// Cuantos campos faltan por seccion. Es un ValueNotifier a proposito:
  /// escribir una letra solo repinta el icono y la pastilla, no el formulario.
  final ValueNotifier<Map<int, int>> faltantes;
  final void Function(int) onTap;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: abierta
                ? AppColors.teal.withValues(alpha: .5)
                : AppColors.border,
            width: abierta ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => onTap(indice),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Row(children: [
                  // Solo el estado de la seccion escucha los faltantes: al
                  // escribir se repinta este icono, no las cajas de texto.
                  ValueListenableBuilder<Map<int, int>>(
                    valueListenable: faltantes,
                    builder: (context, mapa, _) {
                      final completo = (mapa[indice] ?? 0) == 0;
                      final color =
                          completo ? AppColors.success : AppColors.warning;
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: color.withValues(alpha: .40)),
                        ),
                        child: Icon(
                          completo ? Icons.check_rounded : icono,
                          size: 19,
                          color: color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: AppText.seccion.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          resumen,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.apoyo.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<Map<int, int>>(
                    valueListenable: faltantes,
                    builder: (context, mapa, _) {
                      final falta = mapa[indice] ?? 0;
                      if (falta == 0) {
                        return const PastillaConteo(
                          texto: 'LISTO',
                          color: AppColors.success,
                        );
                      }
                      return PastillaConteo(
                        texto: falta == 1 ? 'FALTA 1' : 'FALTAN $falta',
                        color: AppColors.warning,
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: abierta ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more_rounded,
                        color: AppColors.textSecondary),
                  ),
                ]),
              ),
            ),
            // AnimatedSize da el plegado suave sin dejar vivo lo cerrado.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: abierta
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 13),
                            decoration: BoxDecoration(
                              color: AppColors.bg2,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 15, color: AppColors.textSecondary),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    explicacion,
                                    style: AppText.apoyo.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          hijo,
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastilla corta de estado (LISTO / FALTAN N). Existia como widget privado
/// en nuevo_equipo_screen y como Container inline en checklist_compresor.
class PastillaConteo extends StatelessWidget {
  const PastillaConteo({super.key, required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .40)),
        ),
        child: Text(
          texto,
          style: AppText.micro.copyWith(
            color: color,
            letterSpacing: .3,
          ),
        ),
      );
}

/// Un boton de respuesta binaria (SI/NO, APTO/NO APTO). Estaba duplicado byte
/// a byte entre checklist_compresor_screen y black_start_screen.
class OpcionBinaria extends StatelessWidget {
  const OpcionBinaria({
    super.key,
    required this.texto,
    required this.elegido,
    required this.color,
    required this.onTap,
  });

  final String texto;
  final bool elegido;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: elegido ? color.withValues(alpha: .18) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: elegido ? color : AppColors.border,
              width: elegido ? 1.4 : 1,
            ),
          ),
          child: Text(
            texto,
            style: AppText.cuerpoFuerte.copyWith(
              color: elegido ? color : AppColors.textSecondary,
            ),
          ),
        ),
      );
}

/// Pie fijo del formulario: "Faltan N datos por llenar" mas el boton de
/// guardar. Estaba triplicado en nuevo_equipo, checklist_compresor y
/// black_start.
///
/// Solo se repinta el pie, no el formulario, cuando cambia lo que falta:
/// [faltantes] es un ValueNotifier y este widget es su unico oyente completo.
class PieFormulario extends StatelessWidget {
  const PieFormulario({
    super.key,
    required this.faltantes,
    required this.textoBoton,
    required this.onGuardar,
    required this.guardando,
    this.textoBotonGuardando = 'GUARDANDO...',
    this.extra,
  });

  /// Campos que faltan por seccion; el total decide si el boton se habilita.
  final ValueNotifier<Map<int, int>> faltantes;

  /// Texto del boton en reposo, en MAYUSCULAS ('GUARDAR CHECK LIST').
  final String textoBoton;

  /// Texto mientras guarda ('GUARDANDO...', 'REGISTRANDO...').
  final String textoBotonGuardando;

  final VoidCallback onGuardar;
  final bool guardando;

  /// Bloque opcional sobre el boton cuando ya no falta nada: el aviso de
  /// hallazgos del check list, por ejemplo.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<Map<int, int>>(
          valueListenable: faltantes,
          builder: (context, mapa, _) {
            final total = mapa.values.fold(0, (a, b) => a + b);
            final listo = total == 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!listo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(children: [
                      const Icon(Icons.edit_note_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          total == 1
                              ? 'Falta 1 dato por llenar'
                              : 'Faltan $total datos por llenar',
                          style: AppText.cuerpoFuerte.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (listo && extra != null) extra!,
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (listo && !guardando) ? onGuardar : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: Icon(
                      listo ? Icons.check_circle_rounded : Icons.lock_outline,
                      size: 19,
                    ),
                    label: Text(
                      guardando ? textoBotonGuardando : textoBoton,
                      style: AppText.cuerpoFuerte,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
