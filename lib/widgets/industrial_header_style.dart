import 'package:flutter/material.dart';

/// Familia A: colores propios del encabezado, legibles en ambos temas.
abstract final class IndustrialHeaderStyle {
  static const background = Color(0xFF0B2037);
  static const foreground = Color(0xFFF4F9FF);
  static const secondary = Color(0xFFBDD0E0);
  static const accent = Color(0xFF20BBA0);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [background, Color(0xFF123853)],
  );
  static const decoration = BoxDecoration(
    gradient: gradient,
    border: Border(bottom: BorderSide(color: accent, width: 3)),
  );
  static const title = TextStyle(
    color: foreground,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: -.4,
    height: 1.2,
  );
  static const subtitle = TextStyle(
    color: secondary,
    fontSize: 12,
    height: 1.35,
  );
  static const brand = TextStyle(
    color: secondary,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.4,
  );

  static ButtonStyle get actionStyle => IconButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: secondary.withValues(alpha: .5),
        backgroundColor: Colors.white.withValues(alpha: .04),
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(10),
        side: const BorderSide(color: Color(0xFF38536B)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// Conserva el texto completo en accesibilidad y tooltip cuando no cabe.
class IndustrialHeaderTitle extends StatelessWidget {
  const IndustrialHeaderTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.compact = false,
    this.panel = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;
  final bool panel;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (panel) ...[
            const Text('STER / PTBG', style: IndustrialHeaderStyle.brand),
            const SizedBox(height: 6),
          ],
          Tooltip(
            message: title,
            excludeFromSemantics: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IndustrialHeaderStyle.title.copyWith(
                fontSize: compact ? 18 : 22,
              ),
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Tooltip(
              message: subtitle!,
              excludeFromSemantics: true,
              child: Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IndustrialHeaderStyle.subtitle),
            ),
          ],
        ],
      );
}
