import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/orden_reparacion.dart';
import '../models/pendientes_sync.dart';
import '../theme.dart';
import 'industrial_header_style.dart';
import 'filter_cartridge_icon.dart';

class IndustrialShell extends StatelessWidget {
  const IndustrialShell({
    super.key,
    required this.activeRoute,
    required this.child,
  });

  final String activeRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(children: [
        IndustrialSideRail(activeRoute: activeRoute),
        Expanded(child: child),
      ]);
}

class IndustrialSideRail extends StatefulWidget {
  const IndustrialSideRail({super.key, required this.activeRoute});

  final String activeRoute;

  @override
  State<IndustrialSideRail> createState() => _IndustrialSideRailState();
}

class _IndustrialSideRailState extends State<IndustrialSideRail> {
  String get activeRoute => widget.activeRoute;

  @override
  void initState() {
    super.initState();
    _contarAvisos();
  }

  @override
  void didUpdateWidget(covariant IndustrialSideRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // OJO: didUpdateWidget se dispara en CADA rebuild del padre, no solo al
    // navegar. IndustrialShell es stateless, asi que cualquier setState de la
    // pantalla —una tecla en el buscador del inventario, por ejemplo— llegaba
    // hasta aqui y lanzaba consultas a SQLite. Eran decenas de viajes al canal
    // de plataforma por pulsacion y los fps se caian.
    //
    // Contar solo cuando cambia la ruta. Lo demas ya lo cubren los
    // notificadores, que se refrescan al guardar.
    if (oldWidget.activeRoute != widget.activeRoute) _contarAvisos();
  }

  Future<void> _contarAvisos() async {
    try {
      // Refresca los valores compartidos; los avisos se pintan desde los
      // notificadores, no desde el estado de este widget.
      await DbHelper.instance.refrescarAvisos();
    } catch (_) {
      // Base aun sin crear en una instalacion nueva: sin contador y ya.
    }
  }

  void _go(BuildContext context, String route) {
    if (route == activeRoute) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: esterThemeController,
      builder: (context, _) {
        final dark = esterThemeController.isDark;
        final background = dark ? const Color(0xFF08152D) : Colors.white;
        final border = dark ? const Color(0xFF183151) : const Color(0xFFD7E3F1);
        return Material(
          color: background,
          child: SafeArea(
            right: false,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 54,
              decoration: BoxDecoration(
                color: background,
                border: Border(right: BorderSide(color: border)),
              ),
              child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                              child: Column(children: [
                            const SizedBox(height: 8),
                            _item(context, Icons.blur_on_rounded, ''),
                            const SizedBox(height: 24),
                            _item(context, Icons.home_rounded, '/home'),
                            _item(
                                context, Icons.qr_code_scanner_rounded, '/qr'),
                            // Lleva al menu de equipos, no directo a los generales: desde
                            // ahi se elige entre conjuntos e inventario de piezas.
                            // Escucha el valor compartido: al crear o cerrar una orden el
                            // globo cambia al instante, sin navegar ni sincronizar.
                            ValueListenableBuilder<int>(
                              valueListenable: ordenesAbiertasNotifier,
                              builder: (context, abiertas, _) => _item(
                                context,
                                Icons.precision_manufacturing_outlined,
                                '/equipos',
                                badge: abiertas,
                              ),
                            ),
                            // Punto rojo sin numero: no importa si son 2 o 30 trabajos, lo
                            // que importa es que hay algo guardado solo en esta tablet.
                            ValueListenableBuilder<int>(
                              valueListenable: pendientesSyncNotifier,
                              builder: (context, pendientes, _) => _item(
                                context,
                                Icons.sync_rounded,
                                '/sync',
                                punto: pendientes > 0,
                              ),
                            ),
                            _item(
                                context, Icons.history_rounded, '/mediciones'),
                            Tooltip(
                                message: 'Cambio de filtros',
                                child: _item(context, null, '/filtros',
                                    illustration: (color) => Center(
                                        child: FilterCartridgeIcon(color: color)))),
                            const Spacer(),
                            _themeToggle(dark),
                            _item(context, Icons.settings_outlined, '/ajustes'),
                            const SizedBox(height: 12),
                          ]))))),
            ),
          ),
        );
      },
    );
  }

  Widget _themeToggle(bool dark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Tooltip(
          message: dark ? 'Cambiar a modo día' : 'Cambiar a modo noche',
          child: InkWell(
            onTap: esterThemeController.toggle,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF152747) : const Color(0xFFEAF2FB),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color:
                      dark ? const Color(0xFF39557D) : const Color(0xFFB8CEE6),
                ),
              ),
              child: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 20,
                color: dark ? const Color(0xFFFFC857) : const Color(0xFF123A68),
              ),
            ),
          ),
        ),
      );

  Widget _item(
    BuildContext context,
    IconData? icon,
    String route, {
    int badge = 0,
    bool punto = false,
    Widget Function(Color)? illustration,
  }) {
    final active = route.isNotEmpty && activeRoute == route;
    final dark = esterThemeController.isDark;
    final iconColor = active
        ? AppColors.teal
        : dark ? const Color(0xFF43658D) : const Color(0xFF52749C);
    // El borde del globo usa el color de la barra para que se recorte limpio
    // sobre el icono.
    final fondoBarra = dark ? const Color(0xFF08152D) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: route.isEmpty ? null : () => _go(context, route),
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.teal.withValues(alpha: .16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: active
                    ? Border.all(color: AppColors.teal.withValues(alpha: .4))
                    : null,
              ),
              child: illustration?.call(iconColor) ?? Icon(
                icon,
                size: 21,
                color: iconColor,
              ),
            ),
          ),
          if (punto && badge <= 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: fondoBarra, width: 1.5),
                ),
              ),
            ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: fondoBarra, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: AppText.micro.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fondo de las barras de titulo.
///
/// Lo comparten IndustrialContentHeader y las AppBar de las pantallas de
/// detalle: sin esto, moverse por la app alternaba entre una barra plana y una
/// con degradado, y parecian dos aplicaciones distintas.
const industrialHeaderGradient = IndustrialHeaderStyle.gradient;

/// Fondo listo para poner en `flexibleSpace` de una AppBar.
const industrialHeaderBackground = SizedBox.expand(
  child: DecoratedBox(decoration: IndustrialHeaderStyle.decoration),
);

/// Encabezado de una pantalla del panel.
///
/// Usa el mismo degradado marino que las barras de las pantallas de detalle,
/// para que moverse por la app no cambie de aspecto a cada paso.
///
/// Siempre lleva flecha de volver. Las pantallas de la barra lateral se abren
/// con pushReplacement y no tienen ruta que cerrar, asi que en ese caso la
/// flecha lleva al inicio en vez de desaparecer: un boton que a veces esta y a
/// veces no se siente roto, y dejar al tecnico sin salida visible peor.
class IndustrialContentHeader extends StatelessWidget {
  const IndustrialContentHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    this.icon,
    this.showBack = true,
    this.safeTop = true,
  });

  /// El inicio no la lleva: es la raiz y no hay a donde volver. Una flecha que
  /// no lleva a ningun lado confunde mas que ayudar.
  final bool showBack;
  final bool safeTop;

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// A donde va la flecha. Por defecto cierra la pantalla, y si no hay nada
  /// que cerrar vuelve al inicio.
  final VoidCallback? onBack;

  /// Icono opcional junto al titulo, para ubicar la pantalla de un vistazo.
  final IconData? icon;

  void _volver(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: IndustrialHeaderStyle.decoration,
      // Solo el margen de arriba: la barra lateral ya cubre el borde izquierdo
      // y el contenido sigue debajo, asi que anadir esos dos lados abriria un
      // hueco donde no hace falta.
      child: SafeArea(
        top: safeTop,
        left: false,
        right: false,
        bottom: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          final compact = MediaQuery.sizeOf(context).height < 500;
          final actionWidgets = IconButtonTheme(
            data: IconButtonThemeData(style: IndustrialHeaderStyle.actionStyle),
            child: IconTheme.merge(
              data:
                  const IconThemeData(color: IndustrialHeaderStyle.foreground),
              child: Wrap(spacing: 8, runSpacing: 8, children: actions),
            ),
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, compact ? 10 : 16, 16, compact ? 12 : 18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STER / PTBG', style: IndustrialHeaderStyle.brand),
              const SizedBox(height: 10),
              Row(children: [
                if (showBack) ...[
                  _BotonVolver(onTap: () => _volver(context)),
                  const SizedBox(width: 12),
                ],
                if (icon != null && !showBack) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF163C4E),
                      border: Border.all(color: const Color(0xFF306271)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 22, color: const Color(0xFF6BE3CE)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: IndustrialHeaderTitle(
                      title: title,
                      subtitle: subtitle,
                      compact: compact || narrow),
                ),
                // Los iconos de accion heredan el blanco de la barra: antes se
                // pintaban del color de texto del tema y desaparecian sobre el
                // degradado oscuro.
                if (!narrow && actions.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: constraints.maxWidth * .38),
                    child: actionWidgets,
                  ),
                ],
              ]),
              if (narrow && actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actionWidgets),
              ],
            ]),
          );
        }),
      ),
    );
  }
}

class _BotonVolver extends StatelessWidget {
  const _BotonVolver({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Volver',
        onPressed: onTap,
        style: IndustrialHeaderStyle.actionStyle,
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
      );
}

/// La AppBar estandar de las pantallas de flujo.
///
/// Doce pantallas repetian el mismo bloque de cuatro lineas (fondo
/// headerTop, texto blanco, industrialHeaderBackground); dos mas se habian
/// inventado cabeceras propias y se veian de otro programa. Esta es la
/// unica.
class IndustrialAppBar extends StatelessWidget implements PreferredSizeWidget {
  const IndustrialAppBar({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.actions = const [],
    this.bottom,
    this.leading,
    this.panel = false,
  });

  final String titulo;

  /// Linea secundaria bajo el titulo, para el TAG o el equipo.
  final String? subtitulo;

  final List<Widget> actions;

  /// Para las pantallas con pestañas (inventario, ordenes).
  final PreferredSizeWidget? bottom;

  final Widget? leading;
  final bool panel;

  double get _toolbarHeight => panel ? 100 : 76;

  @override
  Size get preferredSize => Size.fromHeight(
        _toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) => IconButtonTheme(
      data: IconButtonThemeData(style: IndustrialHeaderStyle.actionStyle),
      child: AppBar(
        toolbarHeight: _toolbarHeight,
        leadingWidth: 64,
        titleSpacing: 12,
        centerTitle: false,
        backgroundColor: IndustrialHeaderStyle.background,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: industrialHeaderBackground,
        leading: leading != null || Navigator.of(context).canPop()
            ? Center(
                child: SizedBox.square(
                    dimension: 44,
                    child: leading ??
                        BackButton(style: IndustrialHeaderStyle.actionStyle)))
            : null,
        title: IndustrialHeaderTitle(
            title: titulo,
            subtitle: subtitulo,
            panel: panel,
            compact: MediaQuery.sizeOf(context).width < 480),
        actions: [
          for (final action in actions)
            Padding(padding: const EdgeInsets.only(right: 8), child: action)
        ],
        bottom: bottom,
      ));
}
