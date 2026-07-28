import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/widgets/replacement_focus_image.dart';

void main() {
  test('une regiones superpuestas en un solo contorno exterior', () {
    final path = buildReplacementRegionPath(
      const [
        Rect.fromLTRB(0, 0, 0.6, 1),
        Rect.fromLTRB(0.4, 0, 1, 1),
      ],
      const Size(100, 100),
    );

    final metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.length, closeTo(400, 0.1));
  });

  test('mantiene contornos separados para regiones desconectadas', () {
    final path = buildReplacementRegionPath(
      const [
        Rect.fromLTRB(0, 0, 0.3, 1),
        Rect.fromLTRB(0.7, 0, 1, 1),
      ],
      const Size(100, 100),
    );

    expect(path.computeMetrics().toList(), hasLength(2));
  });
}
