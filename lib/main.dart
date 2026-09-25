import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/filters_screen.dart';
import 'screens/qr_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/ruta_screen.dart';
import 'screens/todos_equipos_screen.dart';
import 'screens/mediciones_screen.dart';
import 'screens/ajustes_screen.dart';
import 'screens/capture_screen.dart';
import 'models/models.dart';
import 'models/compatibilidad_equipos.dart';
import 'db/db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await esterThemeController.load();
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: AppColors.headerTop,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.headerTop,
      systemNavigationBarIconBrightness: Brightness.light));

  // Familias de compatibilidad de los equipos que no estan en la lista fija
  // del codigo. Se cargan antes de arrancar para que el primer reemplazo del
  // dia ya ofrezca las piezas correctas, sin esperar a una sincronizacion.
  if (!kIsWeb) {
    try {
      CompatibilidadEquipos.cargarAsignadas(
        await DbHelper.instance.familiasAsignadas(),
      );
    } catch (_) {
      // Instalacion nueva sin base todavia: manda la lista fija.
    }
  }

  runApp(const ScvApp());
}

class ScvApp extends StatelessWidget {
  const ScvApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: esterThemeController,
      builder: (context, _) => MaterialApp(
            title: 'STER',
            debugShowCheckedModeBanner: false,
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildDayTheme(),
            darkTheme: buildTheme(),
            themeMode:
                esterThemeController.isDark ? ThemeMode.dark : ThemeMode.light,
            home: const _Splash(),
            onGenerateRoute: (s) {
              switch (s.name) {
                case '/login':
                  return _fade(const LoginScreen());
                case '/home':
                  return _tab(const HomeScreen());
                case '/filtros':
                  return _tab(const FiltersScreen());
                case '/qr':
                  return _tab(const QrScreen());
                case '/sync':
                  return _tab(const SyncScreen());
                case '/equipos':
                  return _tab(const TodosEquiposScreen());
                case '/mapa':
                  // Desactivado temporalmente en todos los dispositivos.
                  // Un enlace antiguo vuelve al inicio sin abrir el plano.
                  return _tab(const HomeScreen());
                case '/ruta':
                  return _tab(const RutaScreen());
                case '/mediciones':
                  return _tab(const MedicionesScreen());
                case '/ajustes':
                  return _tab(const AjustesScreen());
                case '/capture':
                  final eq = s.arguments as Equipo;
                  return _flow(CaptureScreen(equipo: eq));
                default:
                  return null;
              }
            },
          ));

  static PageRoute _fade(Widget p) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => p,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 300));

  static PageRoute _tab(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, __, ___, child) => child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero);

  static PageRoute _flow(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 190),
      reverseTransitionDuration: const Duration(milliseconds: 140));
}

// ── Splash ──────────────────────────────────────────────────────────────
class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeIn);
    _ac.forward();
    _route();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    // El navegador se toma antes del segundo await. La comprobacion de
    // arriba solo cubre el primero: si la pantalla muere mientras se abren
    // las preferencias, usar el context de nuevo revienta.
    final navegador = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    navegador.pushReplacementNamed(
        prefs.getString('username') != null ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final secondaryColor =
        dark ? AppColors.textSecondary : const Color(0xFF64748B);
    return Scaffold(
        backgroundColor: dark ? AppColors.bg : Colors.white,
        body: Container(
            decoration: BoxDecoration(
                gradient: dark ? AppColors.gradPrimary : null,
                color: dark ? null : Colors.white),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _SplashBg(dark))),
              FadeTransition(
                opacity: _fade,
                child: Center(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                            color: dark
                                ? AppColors.teal.withValues(alpha: 0.14)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                                color: AppColors.teal.withValues(alpha: .65),
                                width: 1.5),
                            boxShadow: dark
                                ? AppColors.shadowTeal
                                : AppColors.shadowMd),
                        child: const Icon(Icons.precision_manufacturing_rounded,
                            color: AppColors.teal, size: 43)),
                    const SizedBox(height: 26),
                    // El logotipo queda fuera de la escala a proposito: es
                    // marca, no contenido, y su tamano y espaciado son parte
                    // de como se dibuja el nombre.
                    Text('STER',
                        style: TextStyle(
                            color: titleColor,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3)),
                    const SizedBox(height: 9),
                    Text('Sistema de Trazabilidad de Equipos Rotativos',
                        style: AppText.cuerpo.copyWith(color: secondaryColor),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 48),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        width: 156,
                        height: 4,
                        child: LinearProgressIndicator(
                          color: AppColors.teal,
                          backgroundColor: dark
                              ? Colors.white.withValues(alpha: .10)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text('Preparando el sistema',
                        style: AppText.apoyo.copyWith(
                            color: secondaryColor, letterSpacing: .25)),
                  ]),
                )),
              ),
            ])));
  }
}

class _SplashBg extends CustomPainter {
  final bool dark;
  const _SplashBg(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color =
          dark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF1F5F9)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 25) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 25) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final cp = Paint()
      ..color = AppColors.teal.withValues(alpha: dark ? 0.06 : 0.035);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2), 120, cp);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8), 80, cp);
  }

  @override
  bool shouldRepaint(_) => false;
}
