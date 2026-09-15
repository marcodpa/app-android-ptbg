import 'package:flutter/material.dart';

import '../theme.dart';

enum AlignmentTrainType { motorPump, motorGearboxPump }

class AlignmentReferenceCard extends StatelessWidget {
  const AlignmentReferenceCard({
    super.key,
    required this.puntos,
  });

  final int puntos;

  @override
  Widget build(BuildContext context) {
    final type = puntos == 6
        ? AlignmentTrainType.motorGearboxPump
        : AlignmentTrainType.motorPump;
    final isLongTrain = type == AlignmentTrainType.motorGearboxPump;

    return Container(
      key: Key(
        isLongTrain
            ? 'alignment-reference-motor-gearbox-pump'
            : 'alignment-reference-motor-pump',
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.gradTeal,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppColors.shadowTeal,
                ),
                child: const Icon(
                  Icons.align_horizontal_center_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referencia de alineación correcta',
                      style: AppText.seccion
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Los centros de todos los ejes coinciden',
                      style: AppText.subtitulo
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'COAXIAL',
                      style: AppText.micro.copyWith(
                        color: AppColors.tealDark,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 162,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FBFF), Color(0xFFEDF4F8)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CustomPaint(
                painter: AlignmentTrainPainter(type),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: _MachineLabel('MOTOR')),
              if (isLongTrain) const Expanded(child: _MachineLabel('CAJA')),
              const Expanded(child: _MachineLabel('BOMBA')),
            ],
          ),
          if (isLongTrain) ...[
            const SizedBox(height: 9),
            const Row(
              children: [
                Expanded(child: _CouplingLabel('Motor–Caja')),
                SizedBox(width: 8),
                Expanded(child: _CouplingLabel('Caja–Bomba')),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Guía visual · no representa un diagnóstico calculado',
                  style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MachineLabel extends StatelessWidget {
  const _MachineLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppText.micro.copyWith(
        color: AppColors.textPrimary,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _CouplingLabel extends StatelessWidget {
  const _CouplingLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.etiqueta.copyWith(color: AppColors.teal),
      ),
    );
  }
}

class AlignmentTrainPainter extends CustomPainter {
  AlignmentTrainPainter(this.type);

  final AlignmentTrainType type;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 400;
    final sy = size.height / 162;
    canvas.save();
    canvas.scale(sx, sy);

    final basePaint = Paint()..color = const Color(0xFFD9E3ED);
    final bodyPaint = Paint()..color = AppColors.headerBottom;
    final bodyDarkPaint = Paint()..color = AppColors.headerTop;
    final detailPaint = Paint()
      ..color = const Color(0xFF5E7796)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final axisPaint = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final guidePaint = Paint()
      ..color = AppColors.teal.withValues(alpha: .36)
      ..strokeWidth = 1.5;
    final couplingFill = Paint()..color = const Color(0xFFE6F7F4);
    final couplingStroke = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 126, 364, 12),
        const Radius.circular(5),
      ),
      basePaint,
    );
    canvas.drawLine(const Offset(26, 78), const Offset(374, 78), guidePaint);
    for (double x = 26; x < 374; x += 12) {
      canvas.drawLine(Offset(x, 75), Offset(x + 6, 75), guidePaint);
    }

    if (type == AlignmentTrainType.motorPump) {
      _drawMotor(canvas, const Rect.fromLTWH(36, 48, 112, 68), bodyPaint,
          bodyDarkPaint, detailPaint);
      _drawPump(canvas, const Offset(292, 82), bodyPaint, bodyDarkPaint);
      canvas.drawLine(const Offset(148, 78), const Offset(253, 78), axisPaint);
      _drawCoupling(
        canvas,
        const Offset(200, 78),
        couplingFill,
        couplingStroke,
      );
    } else {
      _drawMotor(canvas, const Rect.fromLTWH(20, 55, 82, 61), bodyPaint,
          bodyDarkPaint, detailPaint);
      _drawGearbox(
        canvas,
        const Rect.fromLTWH(160, 47, 78, 69),
        bodyPaint,
        bodyDarkPaint,
      );
      _drawPump(canvas, const Offset(335, 82), bodyPaint, bodyDarkPaint,
          radius: 38);
      canvas.drawLine(const Offset(102, 78), const Offset(297, 78), axisPaint);
      _drawCoupling(
        canvas,
        const Offset(131, 78),
        couplingFill,
        couplingStroke,
      );
      _drawCoupling(
        canvas,
        const Offset(267, 78),
        couplingFill,
        couplingStroke,
      );
    }

    final targetPaint = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(200, 78), 7, targetPaint);
    canvas.drawCircle(const Offset(200, 78), 13, targetPaint);

    canvas.restore();
  }

  void _drawMotor(
    Canvas canvas,
    Rect rect,
    Paint body,
    Paint dark,
    Paint detail,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      body,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left - 7, rect.top + 8, 10, rect.height - 16),
      dark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 24, rect.top - 10, 37, 14),
        const Radius.circular(4),
      ),
      dark,
    );
    for (double x = rect.left + 18; x < rect.right - 10; x += 13) {
      canvas.drawLine(
        Offset(x, rect.top + 10),
        Offset(x, rect.bottom - 10),
        detail,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 8, rect.bottom, 18, 10),
      dark,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.right - 28, rect.bottom, 18, 10),
      dark,
    );
  }

  void _drawGearbox(
    Canvas canvas,
    Rect rect,
    Paint body,
    Paint dark,
  ) {
    final path = Path()
      ..moveTo(rect.left + 8, rect.top)
      ..lineTo(rect.right - 12, rect.top)
      ..lineTo(rect.right, rect.top + 14)
      ..lineTo(rect.right - 5, rect.bottom)
      ..lineTo(rect.left + 5, rect.bottom)
      ..lineTo(rect.left, rect.top + 14)
      ..close();
    canvas.drawPath(path, body);
    canvas.drawCircle(
      Offset(rect.center.dx, rect.center.dy),
      18,
      dark,
    );
    canvas.drawCircle(
      Offset(rect.center.dx, rect.center.dy),
      8,
      Paint()..color = AppColors.teal,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 8, rect.bottom, rect.width - 16, 10),
      dark,
    );
  }

  void _drawPump(
    Canvas canvas,
    Offset center,
    Paint body,
    Paint dark, {
    double radius = 45,
  }) {
    canvas.drawCircle(center, radius, body);
    canvas.drawCircle(center, radius * .48, dark);
    canvas.drawCircle(
      center,
      radius * .18,
      Paint()..color = AppColors.teal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx + radius * .46,
          center.dy - radius * .24,
          radius * .74,
          radius * .48,
        ),
        const Radius.circular(5),
      ),
      body,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - radius * .55,
        center.dy + radius,
        radius * 1.1,
        9,
      ),
      dark,
    );
  }

  void _drawCoupling(
    Canvas canvas,
    Offset center,
    Paint fill,
    Paint stroke,
  ) {
    canvas.drawCircle(center, 16, fill);
    canvas.drawCircle(center, 16, stroke);
    canvas.drawCircle(center, 8, stroke);
    canvas.drawLine(
      Offset(center.dx, center.dy - 16),
      Offset(center.dx, center.dy + 16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant AlignmentTrainPainter oldDelegate) {
    return oldDelegate.type != type;
  }
}
