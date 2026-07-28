import 'package:flutter/material.dart';
import 'models.dart';

enum OrientacionMedicion { horizontal, vertical, axial }

class PuntoVisual {
  final int punto;
  final double x;
  final double y;
  final String nombre;
  final String asset;

  const PuntoVisual({
    required this.punto,
    required this.x,
    required this.y,
    required this.nombre,
    required this.asset,
  });
}

class EquipoVisualConfig {
  final String id;
  final String nombre;
  final String asset;
  final String cleanAsset;
  final BoxFit fit;
  final double aspectRatio;
  final List<PuntoVisual> puntos;

  const EquipoVisualConfig({
    required this.id,
    required this.nombre,
    required this.asset,
    required this.puntos,
    String? cleanAsset,
    this.fit = BoxFit.contain,
    this.aspectRatio = 16 / 9,
  }) : cleanAsset = cleanAsset ?? asset;

  PuntoVisual punto(int n) {
    for (final p in puntos) {
      if (p.punto == n) return p;
    }
    if (puntos.isNotEmpty) return puntos.last;
    return const PuntoVisual(
      punto: 1,
      x: 0.50,
      y: 0.50,
      nombre: 'Punto 1',
      asset: 'assets/images/point_refs/bomba_general_p01.jpg',
    );
  }

  String assetForPoint(int n) => punto(n).asset;
}

/// Define la relación entre el punto que ve el operador, el punto gráfico
/// de la ilustración y la columna real de MDB_VIBR_MUES.
class PuntoCapturaConfig {
  final int puntoPantalla;
  final int puntoVisual;
  final int puntoDb;
  final String nombre;

  const PuntoCapturaConfig({
    required this.puntoPantalla,
    required this.puntoVisual,
    required this.puntoDb,
    required this.nombre,
  });
}

/// Plan oficial de captura basado exclusivamente en MDB_EQUIPO.PUNTOS.
///
/// PUNTOS no representa la cantidad de lecturas. Es el código de distribución
/// física del equipo y determina qué columnas H/V/A deben llenarse.
class PlanMedicionResolver {
  static List<PuntoCapturaConfig> fromEquipo(Equipo equipo) {
    return fromPuntos(equipo.ptEq);
  }

  static List<PuntoCapturaConfig> fromPuntos(int puntos) {
    switch (puntos) {
      // MOTOR + BOMBA:
      // Punto 1 -> H1/V1/A1, Punto 2 -> H2/V2/A2,
      // Punto 3 -> H5/V5/A5, Punto 4 -> H6/V6/A6.
      case 1:
        return _motorBomba(const [1, 2, 3, 4]);
      case 2:
        // En esta ilustración el motor está en los puntos gráficos 4 y 3,
        // y la bomba en los puntos gráficos 1 y 2.
        return _motorBomba(const [4, 3, 1, 2]);
      case 3:
        // La ilustración muestra bomba lado libre en el gráfico 4 y
        // bomba lado acople en el gráfico 3.
        return _motorBomba(const [1, 2, 4, 3]);
      case 7:
        // La imagen actual tiene una referencia para motor y otra para bomba.
        // Se reutiliza cada referencia para sus dos apoyos.
        return _motorBomba(const [1, 1, 2, 2]);
      case 8:
        return _motorBomba(const [1, 1, 2, 2]);
      case 9:
        return _motorBomba(const [1, 2, 4, 3]);

      // MOTOR + FINFAN:
      // Punto 3 visible escribe en H9/V9/A9.
      case 4:
        return const [
          PuntoCapturaConfig(
            puntoPantalla: 1,
            puntoVisual: 1,
            puntoDb: 1,
            nombre: 'Motor - lado libre',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 2,
            puntoVisual: 2,
            puntoDb: 2,
            nombre: 'Motor - lado acople',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 3,
            puntoVisual: 3,
            puntoDb: 9,
            nombre: 'Ventilador FINFAN - lado libre',
          ),
        ];

      // MOTOR + VENTILADOR:
      // Puntos visibles 3 y 4 escriben H7/V7/A7 y H8/V8/A8.
      case 5:
        return const [
          PuntoCapturaConfig(
            puntoPantalla: 1,
            puntoVisual: 1,
            puntoDb: 1,
            nombre: 'Motor - lado libre',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 2,
            puntoVisual: 2,
            puntoDb: 2,
            nombre: 'Motor - lado acople',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 3,
            puntoVisual: 3,
            puntoDb: 7,
            nombre: 'Ventilador - punto 1',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 4,
            puntoVisual: 4,
            puntoDb: 8,
            nombre: 'Ventilador - punto 2',
          ),
        ];

      // MOTOR + CAJA MULTIPLICADORA + BOMBA.
      case 6:
        return const [
          PuntoCapturaConfig(
            puntoPantalla: 1,
            puntoVisual: 1,
            puntoDb: 1,
            nombre: 'Motor - lado libre',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 2,
            puntoVisual: 2,
            puntoDb: 2,
            nombre: 'Motor - lado acople',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 3,
            puntoVisual: 3,
            puntoDb: 3,
            nombre: 'Caja multiplicadora - lado baja (caja-motor)',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 4,
            puntoVisual: 4,
            puntoDb: 4,
            nombre: 'Caja multiplicadora - lado alta (caja-bomba)',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 5,
            puntoVisual: 6,
            puntoDb: 5,
            nombre: 'Bomba - lado libre',
          ),
          PuntoCapturaConfig(
            puntoPantalla: 6,
            puntoVisual: 5,
            puntoDb: 6,
            nombre: 'Bomba - lado acople',
          ),
        ];

      default:
        // Fallback seguro: nunca se inventan columnas fuera del patrón oficial.
        return _motorBomba(const [1, 2, 3, 4]);
    }
  }

  static List<PuntoCapturaConfig> _motorBomba(List<int> visuales) {
    return [
      PuntoCapturaConfig(
        puntoPantalla: 1,
        puntoVisual: visuales[0],
        puntoDb: 1,
        nombre: 'Motor - lado libre',
      ),
      PuntoCapturaConfig(
        puntoPantalla: 2,
        puntoVisual: visuales[1],
        puntoDb: 2,
        nombre: 'Motor - lado acople',
      ),
      PuntoCapturaConfig(
        puntoPantalla: 3,
        puntoVisual: visuales[2],
        puntoDb: 5,
        nombre: 'Bomba - lado acople',
      ),
      PuntoCapturaConfig(
        puntoPantalla: 4,
        puntoVisual: visuales[3],
        puntoDb: 6,
        nombre: 'Bomba - lado libre',
      ),
    ];
  }
}

class EquipoVisualResolver {
  static EquipoVisualConfig fromEquipo(Equipo equipo) {
    // REGLA FINAL V13:
    // La imagen y puntos salen DIRECTAMENTE de MOT_EQUIP.PUNTOS.
    // No se decide por nombre, sistema, tag, cantidad de puntos ni LC_EQ.
    // Si ves una imagen incorrecta, corrige PUNTOS en MariaDB y refresca catálogo.
    final config = _fromPtEq(equipo.ptEq);
    if (config != null) return config;

    // Fallback visible y seguro cuando la API/base de datos no manda PUNTOS.
    return _bombaGeneral;
  }

  static EquipoVisualConfig previewFromEquipo(Equipo equipo) {
    final n = _norm(equipo.equipo);
    final lc = equipo.localizacion;

    if (_ventPreviewLocalizaciones.contains(lc) ||
        _containsAny(
            n, const ['VENT TURB', 'VEN TURB', 'VENT GEN', 'VEN GEN'])) {
      return _ventiladores;
    }

    if (_finfanPreviewLocalizaciones.contains(lc) ||
        _containsAny(n, const ['FINFAN', 'FIN FAN', 'FIN FAN'])) {
      return _finfan;
    }

    return fromEquipo(equipo);
  }

  static const Set<int> _ventPreviewLocalizaciones = {
    4,
    5,
    6,
    7,
    11,
    12,
    13,
    14,
  };

  static const Set<int> _finfanPreviewLocalizaciones = {
    15,
    16,
    17,
    18,
  };

  static EquipoVisualConfig? _fromPtEq(int ptEq) {
    switch (ptEq) {
      case 1:
        return _bombaGeneral; // PDF pagina 1
      case 2:
        return _electricaSci; // PDF pagina 5
      case 3:
        return _dieselSci; // PDF pagina 9
      case 4:
        return _ventiladores; // PDF pagina 13
      case 5:
        return _finfan; // PDF pagina 16
      case 6:
        return _nox; // PDF pagina 20
      case 7:
        return _jockeySci; // PDF pagina 26
      case 8:
        return _sprint; // PDF pagina 28
      case 9:
        return _starterHidraulico; // PDF pagina 30
      default:
        return null;
    }
  }

  static String _norm(String value) {
    return value
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('.', '')
        .replaceAll(',', ' ')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll('/', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsAny(String value, List<String> tokens) {
    final v = _norm(value);
    for (final token in tokens) {
      final t = _norm(token);
      if (v.contains(t)) return true;
    }
    return false;
  }

  static const EquipoVisualConfig _bombaGeneral = EquipoVisualConfig(
    id: 'bomba_general',
    nombre: 'Motor-bomba horizontal',
    asset: 'assets/images/point_refs/bomba_general_p01.jpg',
    cleanAsset: 'assets/images/visual_bomba_general.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.2157,
          y: 0.3972,
          nombre: 'Motor lado libre',
          asset: 'assets/images/point_refs/bomba_general_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.3168,
          y: 0.4999,
          nombre: 'Motor lado acople',
          asset: 'assets/images/point_refs/bomba_general_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.4775,
          y: 0.4517,
          nombre: 'Bomba - lado acople',
          asset: 'assets/images/point_refs/bomba_general_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.7353,
          y: 0.4996,
          nombre: 'Bomba - lado libre',
          asset: 'assets/images/point_refs/bomba_general_p04.jpg'),
    ],
  );

  static const EquipoVisualConfig _electricaSci = EquipoVisualConfig(
    id: 'electrica_sci',
    nombre: 'Bomba electrica SCI',
    asset: 'assets/images/point_refs/electrica_sci_p01.jpg',
    cleanAsset: 'assets/images/visual_electrica_sci.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.3105,
          y: 0.5419,
          nombre: 'Bomba lado succion',
          asset: 'assets/images/point_refs/electrica_sci_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.4033,
          y: 0.5421,
          nombre: 'Bomba lado acople',
          asset: 'assets/images/point_refs/electrica_sci_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.5373,
          y: 0.5442,
          nombre: 'Motor lado acople',
          asset: 'assets/images/point_refs/electrica_sci_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.6822,
          y: 0.4996,
          nombre: 'Motor lado libre',
          asset: 'assets/images/point_refs/electrica_sci_p04.jpg'),
    ],
  );

  static const EquipoVisualConfig _dieselSci = EquipoVisualConfig(
    id: 'diesel_sci',
    nombre: 'Bomba diesel SCI',
    asset: 'assets/images/point_refs/diesel_sci_p01.jpg',
    cleanAsset: 'assets/images/visual_diesel_sci.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.3817,
          y: 0.5511,
          nombre: 'Motor diesel lado libre',
          asset: 'assets/images/point_refs/diesel_sci_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.5498,
          y: 0.5603,
          nombre: 'Motor diesel lado acople',
          asset: 'assets/images/point_refs/diesel_sci_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.6785,
          y: 0.4995,
          nombre: 'Bomba lado acople',
          asset: 'assets/images/point_refs/diesel_sci_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.7471,
          y: 0.4996,
          nombre: 'Bomba lado libre',
          asset: 'assets/images/point_refs/diesel_sci_p04.jpg'),
    ],
  );

  static const EquipoVisualConfig _ventiladores = EquipoVisualConfig(
    id: 'ventiladores',
    nombre: 'Ventilador / extractor',
    asset: 'assets/images/point_refs/ventiladores_p01.jpg',
    cleanAsset: 'assets/images/visual_ventiladores.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.3492,
          y: 0.7630,
          nombre: 'Motor parte inferior',
          asset: 'assets/images/point_refs/ventiladores_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.3492,
          y: 0.5270,
          nombre: 'Motor parte superior',
          asset: 'assets/images/point_refs/ventiladores_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.4800,
          y: 0.3274,
          nombre: 'Eje / polea superior',
          asset: 'assets/images/point_refs/ventiladores_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.2250,
          y: 0.4550,
          nombre: 'Correa FIN-FAN',
          asset: 'assets/images/visual_ventiladores.jpg'),
    ],
  );

  static const EquipoVisualConfig _finfan = EquipoVisualConfig(
    id: 'finfan',
    nombre: 'Fin fan / ventilador generador',
    asset: 'assets/images/point_refs/finfan_p01.jpg',
    cleanAsset: 'assets/images/visual_finfan.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.7017,
          y: 0.6356,
          nombre: 'Motor inferior',
          asset: 'assets/images/point_refs/finfan_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.7017,
          y: 0.4165,
          nombre: 'Motor superior',
          asset: 'assets/images/point_refs/finfan_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.3787,
          y: 0.3239,
          nombre: 'Carcasa superior',
          asset: 'assets/images/point_refs/finfan_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.3787,
          y: 0.6921,
          nombre: 'Carcasa inferior',
          asset: 'assets/images/point_refs/finfan_p04.jpg'),
    ],
  );

  static const EquipoVisualConfig _nox = EquipoVisualConfig(
    id: 'nox',
    nombre: 'NOX liquido',
    asset: 'assets/images/point_refs/nox_p01.jpg',
    cleanAsset: 'assets/images/visual_nox.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.2225,
          y: 0.4122,
          nombre: 'Motor lado libre',
          asset: 'assets/images/point_refs/nox_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.3469,
          y: 0.5138,
          nombre: 'Motor lado acople',
          asset: 'assets/images/point_refs/nox_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.4839,
          y: 0.3402,
          nombre: 'Caja / reductor superior',
          asset: 'assets/images/point_refs/nox_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.5312,
          y: 0.4121,
          nombre: 'Caja / reductor inferior',
          asset: 'assets/images/point_refs/nox_p04.jpg'),
      PuntoVisual(
          punto: 5,
          x: 0.7328,
          y: 0.5420,
          nombre: 'Bomba lado acople',
          asset: 'assets/images/point_refs/nox_p05.jpg'),
      PuntoVisual(
          punto: 6,
          x: 0.6556,
          y: 0.4403,
          nombre: 'Bomba lado libre',
          asset: 'assets/images/point_refs/nox_p06.jpg'),
    ],
  );

  static const EquipoVisualConfig _jockeySci = EquipoVisualConfig(
    id: 'jockey_sci',
    nombre: 'Bomba jockey SCI',
    asset: 'assets/images/point_refs/jockey_sci_p01.jpg',
    cleanAsset: 'assets/images/visual_jockey_sci.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.4454,
          y: 0.2077,
          nombre: 'Motor - lado libre',
          asset: 'assets/images/point_refs/jockey_sci_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.5056,
          y: 0.2970,
          nombre: 'Motor - lado acople',
          asset: 'assets/images/point_refs/jockey_sci_p01.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.5056,
          y: 0.3990,
          nombre: 'Bomba - lado acople',
          asset: 'assets/images/point_refs/jockey_sci_p02.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.5056,
          y: 0.5150,
          nombre: 'Bomba - lado libre',
          asset: 'assets/images/point_refs/jockey_sci_p02.jpg'),
    ],
  );

  static const EquipoVisualConfig _sprint = EquipoVisualConfig(
    id: 'sprint',
    nombre: 'Bomba vertical SPRINT',
    asset: 'assets/images/point_refs/sprint_p01.jpg',
    cleanAsset: 'assets/images/visual_sprint.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.4607,
          y: 0.1974,
          nombre: 'Motor - lado libre',
          asset: 'assets/images/point_refs/sprint_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.5400,
          y: 0.2920,
          nombre: 'Motor - lado acople',
          asset: 'assets/images/point_refs/sprint_p01.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.5400,
          y: 0.3863,
          nombre: 'Bomba - lado acople',
          asset: 'assets/images/point_refs/sprint_p02.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.5400,
          y: 0.5080,
          nombre: 'Bomba - lado libre',
          asset: 'assets/images/point_refs/sprint_p02.jpg'),
    ],
  );

  static const EquipoVisualConfig _starterHidraulico = EquipoVisualConfig(
    id: 'starter_hidraulico',
    nombre: 'Starter hidraulico',
    asset: 'assets/images/point_refs/starter_hidraulico_p01.jpg',
    cleanAsset: 'assets/images/visual_starter_hidraulico.jpg',
    puntos: [
      PuntoVisual(
          punto: 1,
          x: 0.7037,
          y: 0.4996,
          nombre: 'Motor lado libre',
          asset: 'assets/images/point_refs/starter_hidraulico_p01.jpg'),
      PuntoVisual(
          punto: 2,
          x: 0.5329,
          y: 0.4996,
          nombre: 'Motor lado acople',
          asset: 'assets/images/point_refs/starter_hidraulico_p02.jpg'),
      PuntoVisual(
          punto: 3,
          x: 0.4108,
          y: 0.5579,
          nombre: 'Cuerpo / acople',
          asset: 'assets/images/point_refs/starter_hidraulico_p03.jpg'),
      PuntoVisual(
          punto: 4,
          x: 0.3032,
          y: 0.5751,
          nombre: 'Bomba / extremo',
          asset: 'assets/images/point_refs/starter_hidraulico_p04.jpg'),
    ],
  );
}

OrientacionMedicion orientacionFromEje(String eje) {
  switch (eje.toUpperCase()) {
    case 'V':
      return OrientacionMedicion.vertical;
    case 'A':
      return OrientacionMedicion.axial;
    case 'H':
    default:
      return OrientacionMedicion.horizontal;
  }
}

String nombreOrientacion(String eje) {
  switch (eje.toUpperCase()) {
    case 'H':
      return 'Horizontal';
    case 'V':
      return 'Vertical';
    case 'A':
      return 'Axial';
    default:
      return eje;
  }
}

String ejeCorto(String eje) => eje.toUpperCase();

Color colorOrientacion(String eje) {
  switch (eje.toUpperCase()) {
    case 'H':
      return Colors.black;
    case 'V':
      return const Color(0xFFE8E8E8);
    case 'A':
      return const Color(0xFFD50000);
    default:
      return const Color(0xFF0A1C3E);
  }
}

Color colorOrientacionUi(String eje) {
  switch (eje.toUpperCase()) {
    case 'H':
      return const Color(0xFF111827);
    case 'V':
      return const Color(0xFF6B7280);
    case 'A':
      return const Color(0xFFD50000);
    default:
      return const Color(0xFF0A1C3E);
  }
}
