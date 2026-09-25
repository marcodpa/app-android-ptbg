import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/filter_catalog.dart';
import '../theme.dart';
import 'filter_cartridge_icon.dart';
import 'filter_flux.dart';
import 'industrial_navigation.dart';

/// Visual-only components for filters. Catalog keys and stored names stay intact.
abstract final class FilterVisualTheme {
  static const cyan = Color(0xFF32DECF);
  static const dayAccent = Color(0xFF006D68);
  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cyan : dayAccent;

  static ThemeData from(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final accent = dark ? cyan : dayAccent;
    final surface = dark ? const Color(0xFF0C2038) : Colors.white;
    final border = dark ? const Color(0xFF335371) : const Color(0xFF8CAFB5);
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dark ? const Color(0xFF2D506A) : border));
    return base.copyWith(
      scaffoldBackgroundColor: dark ? AppColors.bg : const Color(0xFFF1F6FA),
      colorScheme: base.colorScheme.copyWith(
          primary: accent,
          onPrimary: dark ? AppColors.bg : Colors.white,
          surface: surface),
      cardTheme: CardThemeData(
          color: surface, elevation: 0, margin: EdgeInsets.zero, shape: shape),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: dark ? const Color(0xFF0C2038) : Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accent, width: 2))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: dark ? AppColors.bg : Colors.white,
              minimumSize: const Size(48, 50),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent),
              minimumSize: const Size(48, 50),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
    );
  }
}

/// Flux shell scoped to filters; existing rail, routes and global theme remain.
class FilterPage extends StatelessWidget {
  const FilterPage(
      {super.key,
      required this.title,
      required this.body,
      this.subtitle,
      this.leading,
      this.actions = const []});
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? leading;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Theme(
      data: FilterVisualTheme.from(Theme.of(context)),
      child: Builder(
          builder: (context) => IndustrialShell(
              activeRoute: '/filtros',
              child: Scaffold(
                  body: Stack(children: [
                const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 280,
                    child: FilterFluxWaves()),
                SafeArea(
                    child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (leading != null ||
                                Navigator.canPop(context)) ...[
                              leading ??
                                  IconButton.outlined(
                                      tooltip: 'Volver',
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      icon: const Icon(Icons.arrow_back)),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(title,
                                      style: TextStyle(
                                          fontSize:
                                              MediaQuery.textScalerOf(context)
                                                          .scale(16) >
                                                      24
                                                  ? 21
                                                  : 28,
                                          height: 1.15,
                                          fontWeight: FontWeight.w700)),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 8),
                                    Text(subtitle!,
                                        style: TextStyle(
                                            fontSize: 14,
                                            height: 1.35,
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? const Color(0xFFBED2E8)
                                                    : const Color(0xFF35506A))),
                                  ],
                                ])),
                            ...actions,
                          ])),
                  const SizedBox(height: 8),
                  Expanded(child: body),
                ])),
              ])))));
}

/// Display labels only: never used for persistence or catalog relationships.
String filterSystemTitle(FilterRow row) {
  final name = filterText(row['SISTEMA']);
  if (name == 'TURBOGENERADOR_CT_GTG_001') return 'Turbogenerador 1';
  if (name == 'TURBOGENERADOR_CT_GTG_002') return 'Turbogenerador 2';
  if (name == 'COMBUSTIBLE DIESEL') return 'Combustible diésel';
  if (name == 'AGUA') return 'Agua';
  return filterDisplayName(name);
}

String filterDisplayName(String value) {
  // Preserve mixed-case names and technical abbreviations; only soften all caps.
  if (value != value.toUpperCase()) return value;
  return value.split(' ').asMap().entries.map((entry) {
    final word = entry.value;
    if (word.isEmpty ||
        RegExp(r'\d').hasMatch(word) ||
        const ['BG1', 'BG2', 'N/A', 'SPRINT', 'NOX', 'TAG'].contains(word) ||
        const ['A', 'B'].contains(word)) {
      return word;
    }
    final lower = word.toLowerCase();
    return entry.key == 0 ? lower[0].toUpperCase() + lower.substring(1) : lower;
  }).join(' ');
}

enum FilterArt { turbine, water, fuel, gears, cartridge, folder, history }

FilterArt filterSystemArt(FilterRow row) {
  final name = filterText(row['SISTEMA']).toUpperCase();
  if (name.contains('TURBOGENERADOR')) return FilterArt.turbine;
  if (name == 'AGUA') return FilterArt.water;
  if (name.contains('COMBUSTIBLE')) return FilterArt.fuel;
  return FilterArt.gears;
}

/// Crisp vector illustrations, matching the cyan line drawings in the mockups.
/// They accompany full text, so are decorative to screen readers.
class FilterIllustration extends StatelessWidget {
  const FilterIllustration({super.key, required this.kind, this.size = 88});
  final FilterArt kind;
  final double size;
  @override
  Widget build(BuildContext context) => kind == FilterArt.cartridge
      ? FilterCartridgeIcon(
          color: FilterVisualTheme.accent(context), size: size)
      : ExcludeSemantics(
          child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                  painter: _FilterArtPainter(
                      kind, FilterVisualTheme.accent(context)))));
}

class _FilterArtPainter extends CustomPainter {
  const _FilterArtPainter(this.kind, this.color);
  final FilterArt kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double a, double b) =>
        canvas.drawLine(Offset(x, y), Offset(a, b), pen);
    void rect(double x, double y, double w, double h) => canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h), const Radius.circular(2)),
        pen);
    void gear(double x, double y, double radius) {
      final p = Path();
      for (var i = 0; i < 48; i++) {
        final r = i % 6 < 3 ? radius : radius * .8;
        final angle = i * math.pi / 24;
        final point = Offset(x + math.cos(angle) * r, y + math.sin(angle) * r);
        if (i == 0) {
          p.moveTo(point.dx, point.dy);
        } else {
          p.lineTo(point.dx, point.dy);
        }
      }
      p.close();
      canvas.drawPath(p, pen);
      canvas.drawCircle(Offset(x, y), radius * .38, pen);
    }

    switch (kind) {
      case FilterArt.turbine:
        rect(7, 41, 10, 19);
        rect(18, 36, 12, 29);
        rect(63, 36, 23, 29);
        rect(87, 42, 7, 17);
        canvas.drawArc(const Rect.fromLTWH(22, 12, 76, 76), math.pi / 2,
            math.pi, false, pen);
        rect(58, 11, 6, 78);
        for (var i = 0; i <= 8; i++) {
          final a = math.pi / 2 + i * math.pi / 8;
          line(58, 50, 60 + math.cos(a) * 38, 50 + math.sin(a) * 38);
        }
        line(34, 65, 34, 78);
        line(76, 65, 76, 78);
        line(27, 79, 83, 79);
      case FilterArt.water:
        final p = Path()
          ..moveTo(50, 9)
          ..cubicTo(43, 23, 28, 41, 28, 53)
          ..cubicTo(28, 81, 72, 81, 72, 53)
          ..cubicTo(72, 41, 57, 23, 50, 9);
        canvas.drawPath(p, pen);
        canvas.drawPath(
            Path()
              ..moveTo(37, 52)
              ..quadraticBezierTo(35, 61, 44, 65),
            pen);
        for (final y in [83.0, 93.0]) {
          final w = Path()..moveTo(13, y);
          for (var x = 13.0; x < 85; x += 24) {
            w.cubicTo(x + 8, y - 8, x + 16, y + 8, x + 24, y);
          }
          canvas.drawPath(w, pen);
        }
      case FilterArt.fuel:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(13, 29, 71, 48), const Radius.circular(16)),
            pen);
        rect(27, 22, 31, 7);
        rect(37, 15, 14, 7);
        line(24, 77, 24, 86);
        line(32, 77, 32, 86);
        line(66, 77, 66, 86);
        line(74, 77, 74, 86);
        line(71, 33, 71, 76);
        line(80, 33, 80, 76);
        for (var y = 39.0; y < 75; y += 10) {
          line(71, y, 80, y);
        }
        canvas.drawPath(
            Path()
              ..moveTo(43, 38)
              ..cubicTo(38, 47, 33, 52, 34, 58)
              ..cubicTo(35, 71, 53, 71, 53, 58)
              ..cubicTo(53, 52, 47, 44, 43, 38),
            pen);
      case FilterArt.gears:
        gear(36, 55, 25);
        gear(75, 25, 14);
        gear(77, 79, 12);
      case FilterArt.cartridge:
        // Rendered by the shared FilterCartridgeIcon above.
        break;
      case FilterArt.folder:
        canvas.drawPath(
            Path()
              ..moveTo(12, 29)
              ..lineTo(12, 80)
              ..lineTo(88, 80)
              ..lineTo(88, 35)
              ..lineTo(48, 35)
              ..lineTo(40, 24)
              ..lineTo(12, 24)
              ..close(),
            pen);
        line(24, 50, 73, 50);
        line(24, 62, 62, 62);
      case FilterArt.history:
        canvas.drawPath(
            Path()
              ..moveTo(25, 12)
              ..lineTo(61, 12)
              ..lineTo(78, 30)
              ..lineTo(78, 88)
              ..lineTo(25, 88)
              ..close(),
            pen);
        line(61, 12, 61, 30);
        line(61, 30, 78, 30);
        for (final y in [43.0, 57.0, 71.0]) {
          line(36, y, 41, y);
          line(48, y, 65, y);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FilterArtPainter old) =>
      old.kind != kind || old.color != color;
}

class FilterVisualCard extends StatelessWidget {
  const FilterVisualCard(
      {super.key,
      required this.title,
      required this.kind,
      this.detail,
      this.label,
      this.imageAsset,
      this.flux = false,
      this.onTap});
  final String title;
  final String? detail, label;
  final FilterArt kind;
  final String? imageAsset;
  final bool flux;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => imageAsset != null
      ? FilterFluxProduct(
          asset: imageAsset!,
          compact: true,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18, height: 1.3, fontWeight: FontWeight.w700)),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(detail!, style: const TextStyle(height: 1.5))
            ],
          ]))
      : Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            if (flux) ...[
              const Positioned.fill(child: FilterFluxWaves()),
              const Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 150,
                  child: IgnorePointer(
                      child: Opacity(
                          opacity: .15,
                          child: FilterFluxImage(
                              FilterFluxAssets.metalCartridge)))),
            ],
            InkWell(
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilterIdentity(
                              title: title, detail: detail, kind: kind),
                          if (label != null) ...[
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(
                                  child: Text(label!,
                                      style: TextStyle(
                                          color:
                                              FilterVisualTheme.accent(context),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600))),
                              Icon(Icons.chevron_right,
                                  color: FilterVisualTheme.accent(context))
                            ]),
                          ],
                        ]))),
          ]));
}

class FilterIdentity extends StatelessWidget {
  const FilterIdentity(
      {super.key, required this.title, required this.kind, this.detail});
  final String title;
  final String? detail;
  final FilterArt kind;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        final text =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.45))
          ],
        ]);
        final art = FilterIllustration(kind: kind, size: stacked ? 64 : 88);
        if (stacked) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [art, const SizedBox(height: 12), text]);
        }
        return Row(children: [
          art,
          Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 76,
              width: 1,
              color: Theme.of(context).dividerColor),
          Expanded(child: text)
        ]);
      });
}

class FilterSectionTitle extends StatelessWidget {
  const FilterSectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)));
}

class FilterMessage extends StatelessWidget {
  const FilterMessage(this.text,
      {super.key, this.icon = Icons.info_outline, this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                  child: Icon(icon,
                      color: FilterVisualTheme.accent(context), size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
            ]),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ])));
}
