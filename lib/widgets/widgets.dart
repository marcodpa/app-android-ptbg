import 'package:flutter/material.dart';
import '../theme.dart';

// ── Header industrial (con fondo de refinería) ──────────────────────────
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final String? subtitle;
  final bool showBack;
  final List<Widget>? actions;
  final Widget? leading;
  final double expandedHeight;
  const AppHeader({super.key, this.title, this.subtitle,
      this.showBack = true, this.actions, this.leading,
      this.expandedHeight = 72});

  @override Size get preferredSize => Size.fromHeight(expandedHeight);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradPrimary),
      child: Stack(children: [
        // Fondo industrial
        Positioned.fill(child: CustomPaint(painter: _RefineryPainter())),
        // Contenido
        SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(children: [
            if (showBack)
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2))),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20)))
            else if (leading != null)
              leading!
            else
              Container(width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.5))),
                child: const Icon(Icons.graphic_eq_rounded,
                    color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: title != null
              ? Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title!, style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(
                      color: AppColors.teal.withValues(alpha: 0.9),
                      fontSize: 12)),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('SCV-PTBG', style: TextStyle(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  Text('Sistema de Captura de Vibraciones',
                      style: TextStyle(
                          color: AppColors.teal.withValues(alpha: 0.9),
                          fontSize: 11)),
                ])),
            if (actions != null) ...actions!,
          ]),
        )),
      ]),
    );
  }
}

// Pintor del fondo industrial tipo refinería
class _RefineryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Líneas horizontales sutiles tipo tuberías
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double y = 8; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // Torres verticales abstractas (lado derecho)
    final tp = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 2;
    for (double x = size.width * 0.65; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tp);
    }
    // Círculos decorativos
    final cp = Paint()
      ..color = AppColors.teal.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.85, -10), 50, cp);
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.7), 30, cp);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Stat Card ────────────────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bgColor;
  const StatCard({super.key, required this.label, required this.value,
      required this.icon, required this.color, required this.bgColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: AppColors.shadowSm),
    child: Column(children: [
      Container(width: 46, height: 46,
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
          color: color, fontFamily: 'monospace')),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary,
            height: 1.3)),
    ]));
}

// ── Status Badge ─────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String label; final Color color, bgColor; final IconData? icon;
  const StatusBadge({super.key, required this.label, required this.color,
      required this.bgColor, this.icon});
  factory StatusBadge.normal() => const StatusBadge(label: 'Normal',
      color: AppColors.teal, bgColor: AppColors.tealLight,
      icon: Icons.check_circle_rounded);
  factory StatusBadge.alerta() => const StatusBadge(label: 'Alerta',
      color: AppColors.warning, bgColor: AppColors.warningBg,
      icon: Icons.warning_amber_rounded);
  factory StatusBadge.critico() => const StatusBadge(label: 'Crítico',
      color: AppColors.error, bgColor: AppColors.errorBg,
      icon: Icons.error_outline_rounded);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: bgColor,
        borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, color: color, size: 16),
          const SizedBox(width: 6)],
      Text(label, style: TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: color)),
    ]));
}

// ── Section Label ─────────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text; final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(text, style: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary))),
    if (trailing != null) trailing!,
  ]);
}

// ── Connection Banner ─────────────────────────────────────────────────────
class ConnectionBanner extends StatelessWidget {
  final bool online, checking; final String subtitle;
  final VoidCallback onTap;
  const ConnectionBanner({super.key, required this.online,
      required this.checking, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.shadowSm),
      child: Row(children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(
            color: checking ? AppColors.textHint
                : online ? AppColors.teal : AppColors.error,
            shape: BoxShape.circle,
            boxShadow: checking ? [] : [BoxShadow(
              color: (online ? AppColors.teal : AppColors.error)
                  .withValues(alpha: 0.5), blurRadius: 6)])),
        const SizedBox(width: 10),
        checking
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textSecondary))
          : Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: online ? AppColors.teal : AppColors.error, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            checking ? 'Verificando…'
              : online ? 'Conectado' : 'Sin conexión',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: checking ? AppColors.textSecondary
                  : online ? AppColors.teal : AppColors.error)),
          Text(subtitle, style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis),
        ])),
        Icon(Icons.refresh_rounded, size: 16,
            color: online && !checking ? AppColors.teal : AppColors.textHint),
      ])));
}

// ── Gradient Button ───────────────────────────────────────────────────────
class GradBtn extends StatelessWidget {
  final String label; final VoidCallback? onTap; final IconData? icon;
  final Gradient gradient; final List<BoxShadow> shadows;
  final bool loading; final double height;
  const GradBtn({super.key, required this.label, this.onTap, this.icon,
      required this.gradient, required this.shadows,
      this.loading = false, this.height = 54});

  GradBtn.teal({super.key, required this.label, this.onTap, this.icon,
      this.loading = false, this.height = 54})
      : gradient = AppColors.gradTeal, shadows = AppColors.shadowTeal;
  GradBtn.primary({super.key, required this.label, this.onTap, this.icon,
      this.loading = false, this.height = 54})
      : gradient = AppColors.gradPrimary, shadows = AppColors.shadowPrimary;
  GradBtn.orange({super.key, required this.label, this.onTap, this.icon,
      this.loading = false, this.height = 54})
      : gradient = AppColors.gradTeal, shadows = AppColors.shadowTeal;
  GradBtn.cyan({super.key, required this.label, this.onTap, this.icon,
      this.loading = false, this.height = 54})
      : gradient = AppColors.gradTeal, shadows = AppColors.shadowTeal;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity, height: height,
        decoration: BoxDecoration(
          gradient: disabled ? null : gradient,
          color: disabled ? AppColors.borderDark : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? [] : shadows),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (loading)
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
          else if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: disabled
              ? Colors.white54 : Colors.white,
              fontSize: 15, fontWeight: FontWeight.w700)),
        ])));
  }
}
