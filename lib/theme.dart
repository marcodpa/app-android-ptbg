import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EsterThemeController extends ChangeNotifier {
  static const _key = 'ester_dark_mode';
  bool _dark = true;
  bool get isDark => _dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _dark = prefs.getBool(_key) ?? true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _dark = !_dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _dark);
  }
}

final esterThemeController = EsterThemeController();

class AppColors {
  // ── Colores exactos de las imágenes de referencia ─────────────
  static const headerTop = Color(0xFF0A1C3E); // azul marino oscuro
  static const headerBottom = Color(0xFF0D3B6E); // azul marino medio
  static const teal = Color(0xFF00B89C); // teal/verde principal
  static const tealDark = Color(0xFF009B82);
  static const tealLight = Color(0xFFE6F7F4);

  // ── Alias compatibilidad ──────────────────────────────────────
  static const primary = headerTop;
  static const orange = teal; // usamos teal donde antes había orange
  static const cyan = teal;
  static const accent = teal;
  static const accentLight = tealLight;

  // ── Fondos ────────────────────────────────────────────────────
  static const bg = Color(0xFF071226);
  static const bg2 = Color(0xFF0A1830);
  static const surface = Color(0xFF111D35);
  static const surface2 = Color(0xFF17243D);

  // ── Bordes ───────────────────────────────────────────────────
  static const border = Color(0xFF263957);
  static const borderDark = Color(0xFF385173);

  // ── Texto ─────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF4F8FF);
  static const textSecondary = Color(0xFF9EB0CA);
  static const textHint = Color(0xFF61738F);

  // ── Semánticos ────────────────────────────────────────────────
  static const success = Color(0xFF00B89C); // teal = success en esta app
  static const successBg = Color(0xFFE6F7F4);
  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFFFBEB);
  static const error = Color(0xFFEF4444);
  static const errorBg = Color(0xFFFEF2F2);
  static const info = Color(0xFF3B82F6);

  // ── Gradientes ────────────────────────────────────────────────
  static const gradPrimary = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [headerTop, headerBottom]);
  static const gradTeal = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF00B89C), Color(0xFF009B82)]);
  static const gradAccent = gradTeal;
  static const gradError = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEF4444), Color(0xFFDC2626)]);

  // ── Sombras ───────────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
            color: const Color(0xFF0A1C3E).withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(
            color: const Color(0xFF0A1C3E).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4))
      ];
  static List<BoxShadow> get shadowLg => [
        BoxShadow(
            color: const Color(0xFF0A1C3E).withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 8))
      ];
  static List<BoxShadow> get shadowTeal => [
        BoxShadow(
            color: teal.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6))
      ];
  static List<BoxShadow> get shadowAccent => shadowTeal;
  static List<BoxShadow> get shadowOrange => shadowTeal;
  static List<BoxShadow> get shadowPrimary => [
        BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6))
      ];
  static List<BoxShadow> get shadowCyan => shadowTeal;
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
        // El azul marino queda para fondos; los controles activos necesitan
        // contraste luminoso en modo noche.
        primary: AppColors.teal,
        secondary: AppColors.teal,
        surface: AppColors.surface,
        error: AppColors.error),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    textTheme: AppText.textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      // El titulo de una AppBar tiene que pesar lo mismo que el de
      // IndustrialContentHeader: son el encabezado de una pantalla los dos y
      // el usuario pasa de uno a otro navegando. Sin esto, la AppBar caia en
      // titleLarge, que en esta escala es `seccion` (15), y las pantallas de
      // detalle se veian con el titulo mas chico que las del panel.
      //
      // Va sin color a proposito: asi lo toma de foregroundColor y sigue
      // funcionando en los dos temas y sobre el degradado.
      titleTextStyle: AppText.titulo,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: AppColors.border,
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border, width: 1)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.teal, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 1)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0)),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.teal),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.teal),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

ThemeData buildDayTheme() {
  const ink = Color(0xFF111827);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.tealDark,
      secondary: AppColors.teal,
      surface: Colors.white,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: Colors.white,
    fontFamily: 'Roboto',
    textTheme: AppText.textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      elevation: 0,
      // El titulo de una AppBar tiene que pesar lo mismo que el de
      // IndustrialContentHeader: son el encabezado de una pantalla los dos y
      // el usuario pasa de uno a otro navegando. Sin esto, la AppBar caia en
      // titleLarge, que en esta escala es `seccion` (15), y las pantallas de
      // detalle se veian con el titulo mas chico que las del panel.
      //
      // Va sin color a proposito: asi lo toma de foregroundColor y sigue
      // funcionando en los dos temas y sobre el degradado.
      titleTextStyle: AppText.titulo,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.tealDark, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: AppColors.tealDark),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Escala tipografica de la app.
///
/// Antes habia 29 tamanos distintos repartidos en 375 estilos escritos a mano,
/// con medios puntos (7.5, 8.5, 10.5, 11.5, 12.5, 13.5, 14.5) que no venian de
/// ninguna regla, y `w900` en 118 sitios: casi todo el texto iba en el peso
/// maximo, asi que nada destacaba sobre nada. Se veia improvisado porque lo era.
///
/// Estos son los unicos estilos que deberia usar la app. Si hace falta uno
/// nuevo, se agrega aqui y no dentro de una pantalla: es lo que evita que la
/// escala vuelva a desarmarse.
///
/// Los tamanos estan pensados para una tablet que se lee a un brazo de
/// distancia, con guantes y a veces con sol de frente: nada baja de 10, y el
/// cuerpo se queda en 13.5 en vez de los 11 y 12 que dominaban antes.
class AppText {
  const AppText._();

  /// Cifras grandes de las tarjetas de estado: lo que se quiere leer de un
  /// vistazo cruzando la sala.
  ///
  /// Lleva cifras de ancho fijo porque casi siempre son tres tarjetas en fila
  /// —pendientes, hoy, errores— y con cifras proporcionales los numeros no
  /// quedan centrados igual entre ellas.
  static const display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Cifra destacada dentro de una tarjeta pequena.
  ///
  /// Existe porque [display] a 26 no cabe en las fichas compactas del inicio y
  /// [dato] a 13.5 no se distingue del texto que la rodea. Es el escalon del
  /// medio, y hace falta: sin el, las cifras del inicio quedaban del mismo
  /// tamano que su propia etiqueta.
  static const datoGrande = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Titulo de pantalla, en el encabezado.
  static const titulo = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -.2,
  );

  /// La linea de apoyo bajo el titulo. Va ligera a proposito: si compitiera en
  /// peso con el titulo, el encabezado no tendria jerarquia.
  static const subtitulo = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  /// Titulo de una tarjeta o de un bloque dentro de la pantalla.
  static const seccion = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  /// Texto corrido.
  static const cuerpo = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  /// Texto corrido cuando hay que destacarlo dentro de su propio parrafo.
  static const cuerpoFuerte = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  /// Texto secundario: ayudas, notas al pie de una tarjeta.
  static const apoyo = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Valores numericos.
  ///
  /// Lleva cifras de ancho fijo para que una columna de mediciones quede
  /// alineada: con cifras proporcionales, un 1 y un 8 corren el punto decimal
  /// y la lista se lee torcida.
  static const dato = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Etiqueta de un campo o de un dato.
  static const etiqueta = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: .2,
  );

  /// Texto de pastillas y distintivos, en mayusculas.
  ///
  /// Es el unico sitio donde se usa un peso alto en tamano pequeno: en una
  /// pastilla de dos palabras el peso es lo que la separa del fondo.
  static const micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: .5,
  );

  /// Seriales, codigos QR y ODT.
  ///
  /// Monoespaciada a proposito: son cadenas que el tecnico compara caracter a
  /// caracter contra una placa, y ahi el ancho fijo evita confundir 0 con O.
  static const mono = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
    height: 1.25,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Los estilos de Material, atados a la escala de arriba.
  ///
  /// Sirve para que los widgets que no reciben estilo explicito —ListTile,
  /// AlertDialog, SnackBar, botones— caigan tambien dentro de la escala en vez
  /// de traer los tamanos por defecto de Flutter.
  static const textTheme = TextTheme(
    displaySmall: display,
    headlineMedium: titulo,
    headlineSmall: seccion,
    titleLarge: seccion,
    titleMedium: cuerpoFuerte,
    titleSmall: etiqueta,
    bodyLarge: cuerpo,
    bodyMedium: cuerpo,
    bodySmall: apoyo,
    labelLarge: cuerpoFuerte,
    labelMedium: etiqueta,
    labelSmall: micro,
  );
}
