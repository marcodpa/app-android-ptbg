import 'package:flutter/material.dart';
import '../theme.dart';

export 'alignment_reference_card.dart';

// ── Gradient Button ───────────────────────────────────────────────────────
class GradBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Gradient gradient;
  final List<BoxShadow> shadows;
  final bool loading;
  final double height;
  const GradBtn(
      {super.key,
      required this.label,
      this.onTap,
      this.icon,
      required this.gradient,
      required this.shadows,
      this.loading = false,
      this.height = 54});

  GradBtn.teal(
      {super.key,
      required this.label,
      this.onTap,
      this.icon,
      this.loading = false,
      this.height = 54})
      : gradient = AppColors.gradTeal,
        shadows = AppColors.shadowTeal;
  GradBtn.primary(
      {super.key,
      required this.label,
      this.onTap,
      this.icon,
      this.loading = false,
      this.height = 54})
      : gradient = AppColors.gradPrimary,
        shadows = AppColors.shadowPrimary;
  GradBtn.orange(
      {super.key,
      required this.label,
      this.onTap,
      this.icon,
      this.loading = false,
      this.height = 54})
      : gradient = AppColors.gradTeal,
        shadows = AppColors.shadowTeal;
  GradBtn.cyan(
      {super.key,
      required this.label,
      this.onTap,
      this.icon,
      this.loading = false,
      this.height = 54})
      : gradient = AppColors.gradTeal,
        shadows = AppColors.shadowTeal;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    return GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
                gradient: disabled ? null : gradient,
                color: disabled ? AppColors.borderDark : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: disabled ? [] : shadows),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (loading)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
              else if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8)
              ],
              Text(label,
                  style: AppText.seccion.copyWith(
                      color: disabled ? Colors.white54 : Colors.white)),
            ])));
  }
}
