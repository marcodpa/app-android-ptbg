import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/equipo_visual_config.dart';

class EquipoPuntoViewer extends StatelessWidget {
  final EquipoVisualConfig config;

  /// Punto gráfico usado para escoger imagen y posición.
  final int punto;

  /// Número lógico mostrado al operador.
  final int? puntoEtiqueta;

  /// Columna real que se escribirá en MDB_VIBR_MUES, por ejemplo H5.
  final String? dbColumn;

  final String eje;
  final double? lecturaAnterior;
  final String? fechaAnterior;
  final bool showFooter;
  final bool showOrientationLegend;
  final bool showDirectionalMarker;
  final String unit;
  final String? marca;
  final String? modelo;
  final String? serial;
  final VoidCallback? onLegendTap;

  const EquipoPuntoViewer({
    super.key,
    required this.config,
    required this.punto,
    this.puntoEtiqueta,
    this.dbColumn,
    required this.eje,
    this.lecturaAnterior,
    this.fechaAnterior,
    this.showFooter = false,
    this.showOrientationLegend = true,
    this.showDirectionalMarker = true,
    this.unit = 'mm/s',
    this.marca,
    this.modelo,
    this.serial,
    this.onLegendTap,
  });

  @override
  Widget build(BuildContext context) {
    final puntoVisual = config.punto(punto);
    final puntoMostrado = puntoEtiqueta ?? punto;
    final ejeUpper = eje.toUpperCase();
    final ejeUiColor = colorOrientacionUi(ejeUpper);
    final orientacionMostrada = ejeCorto(ejeUpper);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDark, width: 1.3),
        boxShadow: AppColors.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.headerTop, AppColors.headerBottom],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.30)),
                  ),
                  child: Icon(_iconForEje(ejeUpper),
                      color: Colors.white, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Punto $puntoMostrado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ejeUiColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.28)),
                  ),
                  child: Text(
                    orientacionMostrada,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFC9C9C9),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final imageRect = _containedRect(size, config.aspectRatio);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: SizedBox(
                          width: imageRect.width,
                          height: imageRect.height,
                          child: Image.asset(
                            puntoVisual.asset,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.precision_manufacturing_outlined,
                                    size: 70,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    puntoVisual.asset,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _PuntoMedicionPainter(
                          imageRect: imageRect,
                          punto: puntoVisual,
                          eje: ejeUpper,
                          lecturaAnterior: lecturaAnterior,
                          showDirection: showDirectionalMarker,
                          unit: unit,
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: _EquipoImageInfo(
                          marca: marca,
                          modelo: modelo,
                          serial: serial,
                        ),
                      ),
                      if (showOrientationLegend)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: _AxisBadge(
                            eje: ejeUpper,
                            onTap: onLegendTap,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (showFooter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _MiniInfo(
                      label: 'Anterior',
                      value: lecturaAnterior == null
                          ? 'Sin registro'
                          : '${lecturaAnterior!.toStringAsFixed(2)} mm/s',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniInfo(
                      label: 'Fecha',
                      value:
                          fechaAnterior == null || fechaAnterior!.trim().isEmpty
                              ? 'Sin fecha'
                              : fechaAnterior!,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Rect _containedRect(Size outer, double aspectRatio) {
    if (outer.width <= 0 || outer.height <= 0 || aspectRatio <= 0) {
      return Offset.zero & outer;
    }

    final outerRatio = outer.width / outer.height;
    double w;
    double h;

    if (outerRatio > aspectRatio) {
      h = outer.height;
      w = h * aspectRatio;
    } else {
      w = outer.width;
      h = w / aspectRatio;
    }

    return Rect.fromLTWH(
      (outer.width - w) / 2,
      (outer.height - h) / 2,
      w,
      h,
    );
  }

  IconData _iconForEje(String eje) {
    switch (eje.toUpperCase()) {
      case 'H':
        return Icons.swap_horiz_rounded;
      case 'V':
        return Icons.swap_vert_rounded;
      case 'A':
        return Icons.keyboard_double_arrow_right_rounded;
      default:
        return Icons.location_on_outlined;
    }
  }
}

class _EquipoImageInfo extends StatelessWidget {
  final String? marca;
  final String? modelo;
  final String? serial;

  const _EquipoImageInfo({
    this.marca,
    this.modelo,
    this.serial,
  });

  String _clean(String? value) {
    if (value == null) return 'Sin datos';
    final v = value.trim();
    if (v.isEmpty || v.toUpperCase() == 'NULL' || v == '-') return 'Sin datos';
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 255),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.70)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoLine('Modelo', _clean(modelo)),
            const SizedBox(height: 4),
            _infoLine('Serial', _clean(serial)),
            const SizedBox(height: 4),
            _infoLine('Marca', _clean(marca)),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _AxisBadge extends StatelessWidget {
  final String eje;
  final VoidCallback? onTap;

  const _AxisBadge({required this.eje, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.60)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _legendDot('Horizontal', Colors.black, active: eje == 'H'),
              const SizedBox(width: 10),
              _legendDot('Vertical', const Color(0xFF9CA3AF),
                  active: eje == 'V'),
              const SizedBox(width: 10),
              _legendDot('Axial', const Color(0xFFD50000), active: eje == 'A'),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color, {required bool active}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: active ? 12 : 9,
          height: active ? 12 : 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppColors.headerTop : Colors.white,
              width: active ? 1.4 : 1,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: active ? AppColors.headerTop : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;

  const _MiniInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PuntoMedicionPainter extends CustomPainter {
  final Rect imageRect;
  final PuntoVisual punto;
  final String eje;
  final double? lecturaAnterior;
  final bool showDirection;
  final String unit;

  const _PuntoMedicionPainter({
    required this.imageRect,
    required this.punto,
    required this.eje,
    required this.lecturaAnterior,
    required this.showDirection,
    required this.unit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return;

    final p = Offset(
      imageRect.left + imageRect.width * punto.x,
      imageRect.top + imageRect.height * punto.y,
    );

    final color = colorOrientacionUi(eje);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = eje == 'V' ? 4.2 : 4.6
      ..strokeCap = StrokeCap.round;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final lineEnd = showDirection
        ? _lineEndForAxis(p, imageRect, eje)
        : Offset(p.dx, (p.dy - 38).clamp(imageRect.top + 18, imageRect.bottom));

    if (showDirection) {
      canvas.drawLine(p.translate(2, 2), lineEnd.translate(2, 2), shadowPaint);
      canvas.drawLine(p, lineEnd, linePaint);
      _drawArrowHead(canvas, p, lineEnd, linePaint, shadowPaint);
    }

    // El punto negro ya viene dibujado exactamente en la imagen del PDF.
    // Aqui solo se dibuja una guia muy ligera para no tapar el numero del punto.
    final haloPaint = Paint()
      ..color = color.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(p, 18, haloPaint);

    final axisName = ejeCorto(eje);
    final labelText = lecturaAnterior == null
        ? '$axisName - Sin anterior'
        : '$axisName - Ant: ${lecturaAnterior!.toStringAsFixed(2)} $unit';

    _drawLabel(
      canvas,
      size,
      lineEnd,
      labelText,
      color,
      forceLeft: showDirection && (eje == 'H' || eje == 'A'),
    );
  }

  Offset _lineEndForAxis(Offset p, Rect r, String eje) {
    const margin = 18.0;
    final axis = eje.toUpperCase();

    switch (axis) {
      case 'V':
        // Plano 3D: eje Y = vertical. La linea sale verticalmente.
        final dy = p.dy - r.height * 0.28;
        if (dy < r.top + margin) {
          return Offset(
            p.dx,
            (p.dy + r.height * 0.25).clamp(r.top + margin, r.bottom - margin),
          );
        }
        return Offset(
          p.dx,
          dy.clamp(r.top + margin, r.bottom - margin),
        );

      case 'H':
        // Horizontal: en esta vista 3D se representa con la linea diagonal.
        return Offset(
          (p.dx - r.width * 0.25).clamp(r.left + margin, r.right - margin),
          (p.dy + r.height * 0.15).clamp(r.top + margin, r.bottom - margin),
        );

      case 'A':
      default:
        // Axial: en esta vista 3D se representa con la linea horizontal.
        return Offset(
          (p.dx - r.width * 0.28).clamp(r.left + margin, r.right - margin),
          p.dy,
        );
    }
  }

  String _axis3dTag(String eje) {
    switch (eje.toUpperCase()) {
      case 'H':
        return 'H';
      case 'V':
        return 'V';
      case 'A':
        return 'A';
      default:
        return eje.toUpperCase();
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint linePaint,
    Paint shadowPaint,
  ) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const arrowLength = 13.0;
    const arrowAngle = math.pi / 7;

    final p1 = Offset(
      to.dx - arrowLength * math.cos(angle - arrowAngle),
      to.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      to.dx - arrowLength * math.cos(angle + arrowAngle),
      to.dy - arrowLength * math.sin(angle + arrowAngle),
    );

    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(p1.dx, p1.dy)
      ..moveTo(to.dx, to.dy)
      ..lineTo(p2.dx, p2.dy);

    canvas.drawPath(path.shift(const Offset(2, 2)), shadowPaint);
    canvas.drawPath(path, linePaint);
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    Offset anchor,
    String text,
    Color color, {
    bool forceLeft = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 210);

    const padX = 9.0;
    const padY = 6.0;
    final w = tp.width + padX * 2;
    final h = tp.height + padY * 2;

    double left;
    if (forceLeft) {
      // Para H y A, el cuadro siempre queda a la izquierda de la linea.
      left = anchor.dx - w - 10;
    } else {
      left = anchor.dx + 10;
      if (left + w > size.width - 8) left = anchor.dx - w - 10;
    }

    double top = anchor.dy - h - 8;

    if (left < 8) left = 8;
    if (left + w > size.width - 8) left = size.width - w - 8;
    if (top < 8) top = anchor.dy + 8;
    if (top + h > size.height - 8) top = size.height - h - 8;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(8),
    );

    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(rect.shift(const Offset(2, 2)), shadow);

    final bg = Paint()..color = color;
    canvas.drawRRect(rect, bg);

    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  @override
  bool shouldRepaint(covariant _PuntoMedicionPainter oldDelegate) {
    return oldDelegate.imageRect != imageRect ||
        oldDelegate.punto != punto ||
        oldDelegate.eje != eje ||
        oldDelegate.lecturaAnterior != lecturaAnterior;
  }
}
