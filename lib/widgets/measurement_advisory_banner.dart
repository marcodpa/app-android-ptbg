import 'package:flutter/material.dart';

import '../models/measurement_validation.dart';
import '../theme.dart';

class MeasurementAdvisoryBanner extends StatelessWidget {
  const MeasurementAdvisoryBanner({super.key, required this.advisory});

  final MeasurementAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (advisory.level) {
      MeasurementAdvisoryLevel.normal => (
          AppColors.success,
          AppColors.successBg,
          Icons.check_circle_rounded
        ),
      MeasurementAdvisoryLevel.attention => (
          AppColors.warning,
          AppColors.warningBg,
          Icons.warning_amber_rounded
        ),
      MeasurementAdvisoryLevel.high => (
          AppColors.error,
          AppColors.errorBg,
          Icons.error_rounded
        ),
      MeasurementAdvisoryLevel.critical => (
          AppColors.error,
          AppColors.errorBg,
          Icons.report_problem_rounded
        ),
      MeasurementAdvisoryLevel.empty => (
          AppColors.textSecondary,
          AppColors.surface2,
          Icons.speed_rounded
        ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: background.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '${advisory.label}: ${advisory.detail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.etiqueta.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
