import 'package:flutter/material.dart';

class AppColors {
  // ── Colores exactos de las imágenes de referencia ─────────────
  static const headerTop    = Color(0xFF0A1C3E); // azul marino oscuro
  static const headerBottom = Color(0xFF0D3B6E); // azul marino medio
  static const teal         = Color(0xFF00B89C); // teal/verde principal
  static const tealDark     = Color(0xFF009B82);
  static const tealLight    = Color(0xFFE6F7F4);

  // ── Alias compatibilidad ──────────────────────────────────────
  static const primary      = headerTop;
  static const primaryLight = headerBottom;
  static const primaryMid   = Color(0xFF1A3A6E);
  static const navy         = headerTop;
  static const navyDark     = Color(0xFF060F22);
  static const navyLight    = headerBottom;
  static const orange       = teal;       // usamos teal donde antes había orange
  static const orangeLight  = tealLight;
  static const orangeDark   = tealDark;
  static const cyan         = teal;
  static const cyanLight    = tealLight;
  static const cyanDark     = tealDark;
  static const accent       = teal;
  static const accentLight  = tealLight;
  static const accentDark   = tealDark;

  // ── Fondos ────────────────────────────────────────────────────
  static const bg       = Color(0xFFF2F5FA);
  static const bg2      = Color(0xFFE8EDF5);
  static const surface  = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF8FAFD);

  // ── Bordes ───────────────────────────────────────────────────
  static const border     = Color(0xFFE2E8F0);
  static const borderDark = Color(0xFFCBD5E1);

  // ── Texto ─────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF1A2B4A);
  static const textSecondary = Color(0xFF6B7C9A);
  static const textHint      = Color(0xFFCBD5E1);

  // ── Semánticos ────────────────────────────────────────────────
  static const success    = Color(0xFF00B89C); // teal = success en esta app
  static const successBg  = Color(0xFFE6F7F4);
  static const warning    = Color(0xFFF59E0B);
  static const warningBg  = Color(0xFFFFFBEB);
  static const error      = Color(0xFFEF4444);
  static const errorBg    = Color(0xFFFEF2F2);
  static const info       = Color(0xFF3B82F6);
  static const infoBg     = Color(0xFFEFF6FF);

  // ── Gradientes ────────────────────────────────────────────────
  static const gradPrimary = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [headerTop, headerBottom]);
  static const gradTeal = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF00B89C), Color(0xFF009B82)]);
  static const gradAccent  = gradTeal;
  static const gradOrange  = gradTeal;
  static const gradSuccess = gradTeal;
  static const gradError   = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)]);
  static const gradWarning = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)]);
  static const gradCyan = gradTeal;

  // ── Sombras ───────────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
    BoxShadow(color: const Color(0xFF0A1C3E).withValues(alpha: 0.07),
        blurRadius: 8, offset: const Offset(0, 2))];
  static List<BoxShadow> get shadowMd => [
    BoxShadow(color: const Color(0xFF0A1C3E).withValues(alpha: 0.1),
        blurRadius: 16, offset: const Offset(0, 4))];
  static List<BoxShadow> get shadowLg => [
    BoxShadow(color: const Color(0xFF0A1C3E).withValues(alpha: 0.15),
        blurRadius: 28, offset: const Offset(0, 8))];
  static List<BoxShadow> get shadowTeal => [
    BoxShadow(color: teal.withValues(alpha: 0.4),
        blurRadius: 20, offset: const Offset(0, 6))];
  static List<BoxShadow> get shadowAccent => shadowTeal;
  static List<BoxShadow> get shadowOrange => shadowTeal;
  static List<BoxShadow> get shadowPrimary => [
    BoxShadow(color: primary.withValues(alpha: 0.3),
        blurRadius: 20, offset: const Offset(0, 6))];
  static List<BoxShadow> get shadowCyan => shadowTeal;
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.headerTop,
      secondary: AppColors.teal,
      surface: AppColors.surface,
      error: AppColors.error),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.teal, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0)),
  );
}
