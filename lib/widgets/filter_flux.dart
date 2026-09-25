import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/filter_catalog.dart';

/// Bundled reference illustrations, not manufacturer/model identification.
/// Resolving an image never changes a catalog key or a persisted record.
abstract final class FilterFluxAssets {
  static const root = 'assets/images/filters_flux/';
  static const turbine = '${root}turbine.png';
  static const water = '${root}water.png';
  static const fuel = '${root}fuel.png';
  static const airPanel = '${root}air-panel.png';
  static const airBlanket = '${root}air-blanket.png';
  static const airPrefilter = '${root}air-prefilter.png';
  static const metalCartridge = '${root}metal-cartridge.png';
  static const oilCartridge = '${root}oil-cartridge.png';
  static const all = [
    turbine,
    water,
    fuel,
    airPanel,
    airBlanket,
    airPrefilter,
    metalCartridge,
    oilCartridge
  ];

  static String _name(String value) => value
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U');

  static String system(FilterRow row) {
    final name = _name(filterText(row['SISTEMA']));
    if (name.contains('TURBOGENERADOR')) return turbine;
    if (name.contains('COMBUSTIBLE')) return fuel;
    if (name == 'AGUA') return water;
    return metalCartridge;
  }

  static String subsystem(FilterRow row) {
    final name = _name(filterText(row['NAME_SUB_SYS']));
    if (name.contains('VENTILACION') || name.contains('COMBUSTION')) {
      return airPanel;
    }
    if (name.contains('LUBRICACION') || name.contains('COMBUSTIBLE')) {
      return oilCartridge;
    }
    return metalCartridge;
  }

  static String element(FilterRow row) {
    final name = _name(filterText(row['ELEMENTO'] ?? row['elemento']));
    if (name.contains('MANTA')) return airBlanket;
    if (name.contains('PREFILTRO')) return airPrefilter;
    if (name.contains('AIRE') && name.contains('CASA')) return airPanel;
    if (name.contains('ACEITE') ||
        name.contains('LUBRICACION') ||
        name.contains('COMBUSTIBLE') ||
        name.contains('SCAVENGE') ||
        name.contains('SUPPLY')) {
      return oilCartridge;
    }
    return metalCartridge;
  }
}

class FilterFluxImage extends StatelessWidget {
  const FilterFluxImage(this.asset,
      {super.key, this.fit = BoxFit.cover, this.alignment = Alignment.center});
  final String asset;
  final BoxFit fit;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: Image.asset(asset,
          fit: fit,
          alignment: alignment,
          cacheWidth: 960,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF071226),
              child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Color(0xFF9EB0CA), size: 36)))));
}

/// Static native waves: no animation/ticker, no network, no large backdrop image.
class FilterFluxWaves extends StatelessWidget {
  const FilterFluxWaves({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: IgnorePointer(
          child: RepaintBoundary(
              child: CustomPaint(
                  painter: _FluxWaves(
                      Theme.of(context).brightness == Brightness.dark)))));
}

class _FluxWaves extends CustomPainter {
  const _FluxWaves(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final color = dark ? const Color(0xFF32DECF) : const Color(0xFF006D68);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (var i = 0; i < 52; i++) {
      final t = i / 51;
      pen.color =
          color.withValues(alpha: (dark ? .28 : .13) * (1 - (t - .5).abs()));
      final path = Path()..moveTo(size.width * .12, -40 + t * 95);
      path.cubicTo(
          size.width * .5,
          size.height * (.9 - t * .85),
          size.width * .68,
          size.height * (-.32 + t * .68),
          size.width * 1.15,
          size.height * (.4 + t * .65));
      canvas.drawPath(path, pen);
    }
    for (var i = 0; i < 16; i++) {
      final x = size.width * ((i * .137 + .07) % 1);
      final y = size.height * (.25 + .65 * (math.sin(i * 7) + 1) / 2);
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 1.4 : .7,
          Paint()..color = color.withValues(alpha: dark ? .3 : .15));
    }
  }

  @override
  bool shouldRepaint(_FluxWaves oldDelegate) => oldDelegate.dark != dark;
}

/// Two columns on portrait tablets, one on small screens/large system text.
/// Intrinsic rows allow long catalog names without fixed-height clipping.
class FilterFluxGrid extends StatelessWidget {
  const FilterFluxGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= 440 &&
            MediaQuery.textScalerOf(context).scale(16) <= 22;
        return Column(children: [
          for (var i = 0; i < children.length; i += two ? 2 : 1)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: two
                    ? IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            Expanded(child: children[i]),
                            const SizedBox(width: 12),
                            Expanded(
                                child: i + 1 < children.length
                                    ? children[i + 1]
                                    : const SizedBox()),
                          ]))
                    : children[i]),
        ]);
      });
}

class FilterFluxNavigationCard extends StatelessWidget {
  const FilterFluxNavigationCard(
      {super.key,
      required this.title,
      required this.asset,
      required this.onTap,
      required this.label,
      this.detail,
      this.wide = false});
  final String title, asset, label;
  final String? detail;
  final bool wide;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      child: Card(
          color: const Color(0xFF071226),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(
                child: FilterFluxImage(asset,
                    alignment:
                        wide ? Alignment.centerRight : Alignment.bottomRight)),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                  const Color(0xFF031226).withValues(alpha: .97),
                  const Color(0xFF031226).withValues(alpha: .78),
                  const Color(0xFF031226).withValues(alpha: .12),
                  Colors.transparent
                ],
                            stops: const [
                  0,
                  .38,
                  .75,
                  1
                ])))),
            Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: onTap,
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700)),
                              if (detail != null) ...[
                                const SizedBox(height: 8),
                                Text(detail!,
                                    style: const TextStyle(
                                        color: Color(0xFFD3E5F5),
                                        fontSize: 13,
                                        height: 1.4))
                              ],
                              const SizedBox(height: 14),
                              Row(children: [
                                Expanded(
                                    child: Text(label,
                                        style: const TextStyle(
                                            color: Color(0xFF64FFED),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600))),
                                const SizedBox(width: 6),
                                const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Color(0xFF204662),
                                    child: Icon(Icons.chevron_right,
                                        color: Colors.white, size: 22))
                              ]),
                              SizedBox(height: wide ? 14 : 90),
                            ])))),
          ])));
}

class FilterFluxProduct extends StatelessWidget {
  const FilterFluxProduct(
      {super.key,
      required this.asset,
      required this.child,
      this.compact = false});
  final String asset;
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        final stacked =
            c.maxWidth < 390 || MediaQuery.textScalerOf(context).scale(16) > 24;
        final content =
            Padding(padding: const EdgeInsets.all(18), child: child);
        if (stacked) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                    height: compact ? 125 : 190,
                    child: ColoredBox(
                        color: const Color(0xFF071226),
                        child: FilterFluxImage(asset, fit: BoxFit.contain))),
                content
              ]);
        }
        return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              flex: 4,
              child: ColoredBox(
                  color: const Color(0xFF071226),
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: compact ? 130 : 240),
                      child: Stack(children: [
                        Positioned.fill(
                            child: FilterFluxImage(asset, fit: BoxFit.cover)),
                      ])))),
          Expanded(flex: 6, child: content)
        ]));
      }));
}

class FilterFluxAction extends StatelessWidget {
  const FilterFluxAction(
      {super.key,
      required this.title,
      required this.icon,
      required this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right)
              ]))));
}

class FilterFluxEmpty extends StatelessWidget {
  const FilterFluxEmpty({super.key, required this.title, required this.detail});
  final String title, detail;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned.fill(child: FilterFluxWaves()),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.description_outlined,
                      size: 80, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.5)),
                ])),
      ]));
}
