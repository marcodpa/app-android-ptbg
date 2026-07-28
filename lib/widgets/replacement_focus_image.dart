import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/operation_flow.dart';
import '../models/replacement_visual_layout.dart';
import '../theme.dart';

class ReplacementFocusImage extends StatelessWidget {
  const ReplacementFocusImage({
    super.key,
    required this.equipo,
    required this.selected,
  });

  final Equipo equipo;
  final Set<ReplacementComponent> selected;

  @override
  Widget build(BuildContext context) {
    final layout = ReplacementVisualResolver.fromEquipo(equipo);
    if (layout == null) return _fallback();

    final active = selected.intersection(layout.components);
    final showFull =
        active.isEmpty || active.length == layout.components.length;
    final regions = layout.regionsFor(active);
    final selectionLabel = active.isEmpty
        ? 'Sin seleccionar'
        : active.length == 1
            ? '1 seleccionado'
            : '${active.length} seleccionados';

    return Container(
      key: const Key('replacement-viewer-frame'),
      width: double.infinity,
      height: 232,
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
            key: const Key('replacement-viewer-header'),
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
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                    ),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing_outlined,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Componentes del equipo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  key: const Key('replacement-selection-badge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    selectionLabel,
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
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  var imageWidth = constraints.maxWidth;
                  var imageHeight = imageWidth / layout.aspectRatio;
                  if (imageHeight > constraints.maxHeight) {
                    imageHeight = constraints.maxHeight;
                    imageWidth = imageHeight * layout.aspectRatio;
                  }

                  return Center(
                    child: SizedBox(
                      width: imageWidth,
                      height: imageHeight,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: showFull
                            ? _assetImage(
                                layout.asset,
                                key: const Key('replacement-image-full'),
                              )
                            : Stack(
                                key: ValueKey<String>(
                                  active.map((item) => item.name).join('-'),
                                ),
                                fit: StackFit.expand,
                                children: [
                                  Opacity(
                                    key: const Key('replacement-image-faded'),
                                    opacity: 0.22,
                                    child: _assetImage(layout.asset),
                                  ),
                                  ClipPath(
                                    key: const Key('replacement-image-focused'),
                                    clipper: _ReplacementRegionClipper(regions),
                                    child: _assetImage(layout.asset),
                                  ),
                                  CustomPaint(
                                    painter: _ReplacementRegionPainter(regions),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetImage(String asset, {Key? key}) {
    return Image.asset(
      asset,
      key: key,
      fit: BoxFit.fill,
      semanticLabel: 'Componentes del equipo ${equipo.equipo}',
      errorBuilder: (_, __, ___) => _fallback(compact: true),
    );
  }

  Widget _fallback({bool compact = false}) {
    return Container(
      key: const Key('replacement-image-fallback'),
      constraints: BoxConstraints(minHeight: compact ? 80 : 180),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.precision_manufacturing_outlined,
              size: 38, color: AppColors.textSecondary),
          SizedBox(height: 6),
          Text(
            'Imagen no disponible',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplacementRegionClipper extends CustomClipper<Path> {
  const _ReplacementRegionClipper(this.regions);

  final List<Rect> regions;

  @override
  Path getClip(Size size) {
    return buildReplacementRegionPath(regions, size);
  }

  @override
  bool shouldReclip(covariant _ReplacementRegionClipper oldClipper) {
    return oldClipper.regions != regions;
  }
}

class _ReplacementRegionPainter extends CustomPainter {
  const _ReplacementRegionPainter(this.regions);

  final List<Rect> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(buildReplacementRegionPath(regions, size), paint);
  }

  @override
  bool shouldRepaint(covariant _ReplacementRegionPainter oldDelegate) {
    return oldDelegate.regions != regions;
  }
}

Path buildReplacementRegionPath(List<Rect> regions, Size size) {
  Path? combined;
  for (final region in regions) {
    final regionPath = Path()..addRect(_scale(region, size));
    combined = combined == null
        ? regionPath
        : Path.combine(PathOperation.union, combined, regionPath);
  }
  return combined ?? Path();
}

Rect _scale(Rect normalized, Size size) {
  return Rect.fromLTRB(
    normalized.left * size.width,
    normalized.top * size.height,
    normalized.right * size.width,
    normalized.bottom * size.height,
  );
}
