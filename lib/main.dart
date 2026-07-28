import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qr_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/ruta_screen.dart';
import 'screens/mediciones_screen.dart';
import 'screens/ajustes_screen.dart';
import 'screens/capture_screen.dart';
import 'models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.headerTop,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.headerTop,
    systemNavigationBarIconBrightness: Brightness.light));
  runApp(const ScvApp());
}

class ScvApp extends StatelessWidget {
  const ScvApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SCV-PTBG',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const _Splash(),
    onGenerateRoute: (s) {
      switch (s.name) {
        case '/login':   return _fade(const LoginScreen());
        case '/home':    return _fade(const HomeScreen());
        case '/qr':      return _slide(const QrScreen());
        case '/sync':    return _slide(const SyncScreen());
        case '/ruta':    return _slide(const RutaScreen());
        case '/mediciones': return _slide(const MedicionesScreen());
        case '/ajustes': return _slide(const AjustesScreen());
        case '/capture':
          final eq = s.arguments as Equipo;
          return _slide(CaptureScreen(equipo: eq));
        default: return null;
      }
    },
  );

  static PageRoute _fade(Widget p) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => p,
    transitionsBuilder: (_, a, __, child) =>
        FadeTransition(opacity: a, child: child),
    transitionDuration: const Duration(milliseconds: 300));

  static PageRoute _slide(Widget p) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => p,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child),
    transitionDuration: const Duration(milliseconds: 280));
}

// ── Splash ──────────────────────────────────────────────────────────────
class _Splash extends StatefulWidget {
  const _Splash();
  @override State<_Splash> createState() => _SplashState();
}
class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeIn);
    _ac.forward();
    _route();
  }
  @override void dispose() { _ac.dispose(); super.dispose(); }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    Navigator.pushReplacementNamed(
        context, prefs.getString('username') != null ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AppColors.gradPrimary),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(
            painter: _SplashBg())),
        FadeTransition(opacity: _fade,
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
            Container(width: 90, height: 90,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.teal, width: 2)),
              child: const Icon(Icons.graphic_eq_rounded,
                  color: Colors.white, size: 48)),
            const SizedBox(height: 24),
            const Text('SCV-PTBG', style: TextStyle(
                color: Colors.white, fontSize: 34,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 6),
            Text('Sistema de Captura de Vibraciones',
              style: TextStyle(color: AppColors.teal.withValues(alpha: 0.9),
                  fontSize: 13)),
            const SizedBox(height: 48),
            SizedBox(width: 28, height: 28,
              child: CircularProgressIndicator(
                color: AppColors.teal.withValues(alpha: 0.7),
                strokeWidth: 2)),
          ])),
        ),
      ])));
}

class _SplashBg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.03)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 25) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 25) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final cp = Paint()..color = AppColors.teal.withValues(alpha: 0.06);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2), 120, cp);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8), 80, cp);
  }
  @override bool shouldRepaint(_) => false;
}
