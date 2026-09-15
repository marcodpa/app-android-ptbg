import 'package:flutter/material.dart';

import '../models/equipo_visual_config.dart';
import '../models/models.dart';
import '../theme.dart';
import 'decode_imagen.dart';

// Las vistas limpias de los equipos usan este gris en sus bordes. Mantener el
// mismo tono en el panel superior elimina el corte visual alrededor de la foto.
const Color _equipmentImageBackground = Color(0xFFC0C0C0);

class IndustrialEquipmentCard extends StatelessWidget {
  const IndustrialEquipmentCard({
    super.key,
    required this.equipo,
    required this.ultima,
    required this.pendingCount,
    required this.onTap,
  });

  final Equipo equipo;
  final UltimaLectura? ultima;
  final int pendingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    final visual = EquipoVisualResolver.catalogFromEquipo(equipo);
    final preview = visual.cleanAsset;
    // Los renders de equipo son dibujos recortados sobre fondo claro: van
    // contenidos y con aire, o se ven cortados. Una fotografia real, en
    // cambio, tiene que llenar la tarjeta; contenida dejaria franjas grises a
    // los lados. Lo decide la configuracion del equipo, no la tarjeta.
    final llenar = visual.fit == BoxFit.cover;
    final accent = pendingCount > 0 ? AppColors.warning : AppColors.teal;
    final cardColor = dark ? AppColors.surface : Colors.white;
    final borderColor = dark ? AppColors.border : const Color(0xFFE2E8F0);
    final titleColor = dark ? AppColors.textPrimary : const Color(0xFF111827);
    final secondaryColor =
        dark ? AppColors.textSecondary : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: .8),
            boxShadow: [
              BoxShadow(
                color: dark
                    ? AppColors.bg.withValues(alpha: .38)
                    : const Color(0xFF0F172A).withValues(alpha: .08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(fit: StackFit.expand, children: [
                    if (!llenar)
                      Container(
                          color: visual.backgroundColor ??
                              _equipmentImageBackground),
                    Padding(
                      padding: EdgeInsets.all(llenar ? 0 : 7),
                      child: Image.asset(preview,
                          fit: visual.fit,
                          semanticLabel: visual.nombre,
                          // Una rejilla de tarjetas: si cada una descomprime su
                          // foto a tamano completo se juntan varios MB de
                          // bitmap y el scroll se traba.
                          cacheWidth: anchoDecode(context, anchoLogico: 240),
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.precision_manufacturing_outlined,
                              color: AppColors.teal,
                              size: 48)),
                    ),
                    Positioned(
                        top: 7,
                        left: 7,
                        child: _StatusBadge(
                          hasReading: ultima != null,
                          accent: accent,
                        )),
                  ]),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(equipo.equipo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.seccion.copyWith(color: titleColor)),
                        const SizedBox(height: 2),
                        Text('ID: ${equipo.qrDisplay}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.apoyo.copyWith(color: secondaryColor)),
                        Text('${equipo.sistema} · LOC-${equipo.localizacion}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.apoyo.copyWith(color: secondaryColor)),
                        const Spacer(),
                        if (pendingCount > 0)
                          Text(
                              '$pendingCount pendiente${pendingCount == 1 ? '' : 's'}',
                              style: AppText.micro
                                  .copyWith(color: AppColors.warning)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.touch_app_rounded,
                              color: AppColors.teal, size: 16),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text('Tocar para ver opciones',
                                style: AppText.micro
                                    .copyWith(color: secondaryColor)),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.teal, size: 18),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.hasReading, required this.accent});
  final bool hasReading;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
          color: dark
              ? AppColors.bg.withValues(alpha: .9)
              : Colors.white.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: .55))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: hasReading ? AppColors.success : AppColors.textHint,
                shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(hasReading ? 'CON REGISTROS' : 'SIN REGISTROS',
            style: AppText.micro.copyWith(
                color: dark ? AppColors.textPrimary : const Color(0xFF334155))),
      ]),
    );
  }
}
