import 'dart:ui';

import 'equipo_visual_config.dart';
import 'models.dart';
import 'operation_flow.dart';

class ReplacementVisualLayout {
  const ReplacementVisualLayout({
    required this.asset,
    required this.aspectRatio,
    required this.regions,
  });

  final String asset;
  final double aspectRatio;
  final Map<ReplacementComponent, List<Rect>> regions;

  Set<ReplacementComponent> get components => regions.keys.toSet();

  List<Rect> regionsFor(Set<ReplacementComponent> selected) {
    return [
      for (final component in selected) ...?regions[component],
    ];
  }
}

class ReplacementVisualResolver {
  static ReplacementVisualLayout? fromEquipo(Equipo equipo) {
    final vibrationVisual = EquipoVisualResolver.previewFromEquipo(equipo);
    if (vibrationVisual.id == 'finfan') return _finfan;
    if (vibrationVisual.id == 'ventiladores') return _ventiladores;
    return fromPuntos(equipo.ptEq);
  }

  static ReplacementVisualLayout? fromPuntos(int puntos) {
    switch (puntos) {
      case 1:
        return _bombaGeneral;
      case 2:
        return _electricaSci;
      case 3:
        return _dieselSci;
      case 4:
        return _ventiladores;
      case 5:
        return _finfan;
      case 6:
        return _nox;
      case 7:
        return _jockey;
      case 8:
        return _sprint;
      case 9:
        return _starter;
      default:
        return null;
    }
  }

  static const _bombaGeneral = ReplacementVisualLayout(
    asset: 'assets/images/visual_bomba_general.jpg',
    aspectRatio: 1444 / 644,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.00, 0.04, 0.36, 0.96)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.32, 0.00, 1.00, 1.00)],
    },
  );

  static const _electricaSci = ReplacementVisualLayout(
    asset: 'assets/images/visual_electrica_sci.jpg',
    aspectRatio: 1144 / 925,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.38, 0.18, 1.00, 0.92)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.00, 0.00, 0.44, 1.00)],
    },
  );

  static const _dieselSci = ReplacementVisualLayout(
    asset: 'assets/images/visual_diesel_sci.jpg',
    aspectRatio: 1346 / 988,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.00, 0.00, 0.74, 1.00)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.68, 0.34, 1.00, 0.82)],
    },
  );

  static const _ventiladores = ReplacementVisualLayout(
    asset: 'assets/images/visual_ventiladores.jpg',
    aspectRatio: 800 / 690,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.57, 0.15, 1.00, 0.90)],
      ReplacementComponent.fan: [Rect.fromLTRB(0.00, 0.00, 0.66, 1.00)],
    },
  );

  static const _finfan = ReplacementVisualLayout(
    asset: 'assets/images/visual_finfan.jpg',
    aspectRatio: 969 / 968,
    regions: {
      ReplacementComponent.motor: [
        Rect.fromLTRB(0.39, 0.00, 0.61, 0.19),
        Rect.fromLTRB(0.41, 0.58, 0.59, 0.80),
      ],
      ReplacementComponent.fan: [
        Rect.fromLTRB(0.00, 0.00, 0.41, 1.00),
        Rect.fromLTRB(0.59, 0.00, 1.00, 1.00),
        Rect.fromLTRB(0.40, 0.18, 0.60, 0.59),
        Rect.fromLTRB(0.40, 0.79, 0.60, 1.00),
      ],
    },
  );

  static const _nox = ReplacementVisualLayout(
    asset: 'assets/images/visual_nox.jpg',
    aspectRatio: 1536 / 785,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.04, 0.03, 0.38, 0.82)],
      ReplacementComponent.gearbox: [Rect.fromLTRB(0.32, 0.14, 0.68, 0.88)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.62, 0.00, 1.00, 1.00)],
    },
  );

  static const _jockey = ReplacementVisualLayout(
    asset: 'assets/images/visual_jockey_sci.jpg',
    aspectRatio: 696 / 1536,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.08, 0.00, 0.78, 0.53)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.00, 0.45, 1.00, 1.00)],
    },
  );

  static const _sprint = ReplacementVisualLayout(
    asset: 'assets/images/visual_sprint.jpg',
    aspectRatio: 463 / 1423,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.05, 0.00, 0.95, 0.48)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.00, 0.42, 1.00, 1.00)],
    },
  );

  static const _starter = ReplacementVisualLayout(
    asset: 'assets/images/visual_starter_hidraulico.jpg',
    aspectRatio: 1349 / 546,
    regions: {
      ReplacementComponent.motor: [Rect.fromLTRB(0.40, 0.00, 1.00, 1.00)],
      ReplacementComponent.pump: [Rect.fromLTRB(0.00, 0.12, 0.47, 1.00)],
    },
  );
}
