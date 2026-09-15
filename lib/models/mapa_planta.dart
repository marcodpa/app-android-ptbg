// GENERADO por generar_mapa_dart.py — no editar a mano.
//
// Las posiciones se colocan en mapa_planta.py con ubicar_equipos.html
// (o ubicar_equipos.py) y desde alli se regeneran. Editar aqui se pierde
// en la siguiente regeneracion.

/// Un punto sobre el plano, en fracciones de 0 a 1 del ancho y del alto.
///
/// Se guardan como fraccion y no en pixeles a proposito: si el plano se
/// reexporta con otro tamano, los marcadores siguen cayendo en el mismo
/// sitio de la planta sin tener que recolocar nada.
class PuntoMapa {
  const PuntoMapa(this.x, this.y);

  final double x;
  final double y;
}

/// Un area del plano, para rotularla cuando se ve la planta completa.
class ZonaMapa {
  const ZonaMapa(this.nombre, this.x0, this.y0, this.x1, this.y1);

  final String nombre;
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  double get centroX => (x0 + x1) / 2;
  double get centroY => (y0 + y1) / 2;
}

const planoPlanta = 'assets/images/plano_planta.png';

/// Proporcion del plano (ancho / alto), para dibujarlo sin deformarlo.
const planoRelacion = 2000 / 1115;

/// Donde esta cada equipo, por LOCALIZACION.
///
/// Los que no estan en este mapa no tienen posicion asignada todavia y
/// simplemente no se dibujan; el resto de la app no se entera.
const mapaEquipos = <int, PuntoMapa>{
  // AGUA POTABLE
  48: PuntoMapa(0.2679, 0.2218),  // 10PW-01A · 10-PW-CP-001A
  49: PuntoMapa(0.2684, 0.2126),  // 10PW-01B · 10-PW-CP-001B
  50: PuntoMapa(0.2693, 0.2636),  // 10RW-02A · 10-RW-CP-002A
  51: PuntoMapa(0.2684, 0.2533),  // 10RW-02B · 10-RW-CP-002B
  // AIRE COMPRIMIDO
  53: PuntoMapa(0.3139, 0.3156),  // COMPRESOR A · 10-IA-CPR-001A
  54: PuntoMapa(0.3209, 0.3156),  // COMPRESOR B · 10-IA-CPR-001B
  55: PuntoMapa(0.3286, 0.3161),  // COMPRESOR C · 10-SA-CPR-001
  // CENTRIFUGADORAS
  40: PuntoMapa(0.461, 0.3183),   // 12-05-DO-EM101-S · 12-05-DO-EM101-S
  41: PuntoMapa(0.483, 0.3186),   // 12-05-DO-EM101-D · 12-05-DO-EM101-D
  42: PuntoMapa(0.483, 0.3157),   // 12-05-DO-EM201 · 12-05-DO-EM201
  43: PuntoMapa(0.468, 0.3166),   // 17-06-DO_EM101_S · 17-06-DO_EM101_S
  44: PuntoMapa(0.4914, 0.318),   // 17-06-DO_EM101_D · 17-06-DO_EM101_D
  45: PuntoMapa(0.4962, 0.3181),  // 17-06-DO_EM201 · 17-06-DO_EM201
  // DEMINERALIZED WATER
  23: PuntoMapa(0.2694, 0.4208),  // 11DW-02A · 11-DW-CP-002A
  24: PuntoMapa(0.2687, 0.4126),  // 11DW-02B · 11-DW-CP-002B
  25: PuntoMapa(0.2698, 0.4025),  // 11DW-02C · 11-DW-CP-002C
  26: PuntoMapa(0.27, 0.3914),    // 12DW-02A · 12-DW-CP-002A
  27: PuntoMapa(0.2685, 0.3818),  // 12DW-02B · 12-DW-CP-002B
  28: PuntoMapa(0.2685, 0.3731),  // 12DW-02C · 12-DW-CP-002C
  29: PuntoMapa(0.2673, 0.4455),  // 10DW-03A · 10-DW-CP-003A
  30: PuntoMapa(0.267, 0.4372),   // 10DW-03B · 10-DW-CP-003B
  // FUEL OIL
  34: PuntoMapa(0.4025, 0.3093),  // 11FO-04A · 11-FO-CP-004A
  35: PuntoMapa(0.4068, 0.3091),  // 11FO-04B · 11-FO-CP-004B
  36: PuntoMapa(0.4102, 0.309),   // 11FO-04C · 11-FO-CP-004C
  37: PuntoMapa(0.4158, 0.3119),  // 12FO-04A · 12-FO-CP-004A
  38: PuntoMapa(0.4193, 0.3116),  // 12FO-04B · 12-FO-CP-004B
  39: PuntoMapa(0.423, 0.3114),   // 12FO-04C · 12-FO-CP-004C
  // S.C.I
  31: PuntoMapa(0.2603, 0.0844),  // 10FW-01 · SCI ELECTRIC MOTOR
  32: PuntoMapa(0.2605, 0.1149),  // 10FW-02 · DIESEL MOTOR
  33: PuntoMapa(0.2554, 0.0823),  // 10FW-03 · JOCKEY MOTOR
  // TURBINA BG-1
  1: PuntoMapa(0.3386, 0.4564),   // BOOSTER · 11-MOT-6241
  2: PuntoMapa(0.3411, 0.4764),   // NOX-LIQUIDO · 11-MOT-6242
  3: PuntoMapa(0.341, 0.4675),    // NOX-GAS · 11-MOT-62059
  4: PuntoMapa(0.3572, 0.4255),   // VENT TURB A · 11-MOT-6417
  5: PuntoMapa(0.3635, 0.4258),   // VENT TURB B · 11-MOT-6418
  6: PuntoMapa(0.3569, 0.4708),   // VENT GEN A · 11-MOT-6413
  7: PuntoMapa(0.3635, 0.4719),   // VENT GEN B · 11-MOT-6416
  15: PuntoMapa(0.3338, 0.4145),  // FIN FAN A · 11-MOT-6090
  17: PuntoMapa(0.3337, 0.3992),  // FIN FAN B · 11-MOT-6091
  19: PuntoMapa(0.3479, 0.4421),  // HYD-STR · 11-MOT-1615
  20: PuntoMapa(0.3474, 0.4566),  // SPRINT · 11-MOT-62226
  // TURBINA BG-2
  8: PuntoMapa(0.4437, 0.4553),   // BOOSTER · 12-MOT-6241
  9: PuntoMapa(0.4487, 0.4748),   // NOX-LIQUIDO · 12-MOT-6242
  10: PuntoMapa(0.4484, 0.4668),  // NOX-GAS · 12-MOT-62059
  11: PuntoMapa(0.4624, 0.4256),  // VENT TURB A · 12-MOT-6417
  12: PuntoMapa(0.4689, 0.4248),  // VENT TURB B · 12-MOT-6418
  13: PuntoMapa(0.4629, 0.4687),  // VENT GEN A · 12-MOT-6413
  14: PuntoMapa(0.4691, 0.4685),  // VENT GEN B · 12-MOT-6416
  16: PuntoMapa(0.4385, 0.3993),  // FIN FAN B · 12-MOT-6091
  18: PuntoMapa(0.4388, 0.4141),  // FIN FAN A · 12-MOT-6090
  21: PuntoMapa(0.4546, 0.4396),  // HYD-STR · 12-MOT-1615
  22: PuntoMapa(0.453, 0.4579),   // SPRINT · 12-MOT-62226
};

/// El black start no tiene LOCALIZACION: es uno solo en la planta y
/// su registro no cuelga de ningun equipo, asi que va aparte.
const mapaBlackStart = PuntoMapa(0.3382, 0.7121);

/// Rotulos de area, para ubicarse cuando se ve la planta entera.
const mapaZonas = <ZonaMapa>[
  ZonaMapa('TANQUES DE COMBUSTIBLE', 0.312, 0.03, 0.755, 0.255),
  ZonaMapa('TANQUES FW / RW / DW', 0.17, 0.055, 0.25, 0.45),
  ZonaMapa('PLANTA DEMI', 0.11, 0.43, 0.17, 0.6),
  ZonaMapa('S.C.I', 0.243, 0.052, 0.275, 0.13),
  ZonaMapa('AGUA POTABLE', 0.232, 0.185, 0.272, 0.26),
  ZonaMapa('FW-BOMBAS', 0.232, 0.298, 0.272, 0.44),
  ZonaMapa('COMPRESORES DE AIRE', 0.306, 0.262, 0.343, 0.328),
  ZonaMapa('MCC-C/D', 0.36, 0.262, 0.399, 0.328),
  ZonaMapa('FO-BOMBAS', 0.393, 0.262, 0.451, 0.328),
  ZonaMapa('CENTRIFUGADORAS', 0.453, 0.262, 0.503, 0.328),
  ZonaMapa('SISTEMA DE ESPUMA', 0.506, 0.262, 0.535, 0.328),
  ZonaMapa('TURBINA BG-1', 0.3, 0.36, 0.39, 0.58),
  ZonaMapa('TURBINA BG-2', 0.41, 0.36, 0.5, 0.58),
  ZonaMapa('TURBINAS BG-3 / BG-4', 0.52, 0.36, 0.72, 0.6),
  ZonaMapa('GEN. DIESEL', 0.32, 0.69, 0.37, 0.74),
  ZonaMapa('TRANSFORMADORES 138/24', 0.31, 0.76, 0.44, 0.85),
  ZonaMapa('PATIO 138 kV', 0.47, 0.74, 0.6, 0.86),
  ZonaMapa('CELDAS 24 kV', 0.3, 0.85, 0.4, 0.92),
  ZonaMapa('SALA DE RELE', 0.4, 0.855, 0.447, 0.915),
  ZonaMapa('EDIFICIO DE CONTROL', 0.19, 0.64, 0.26, 0.83),
  ZonaMapa('TALLERES', 0.09, 0.64, 0.19, 0.75),
  ZonaMapa('ALMACEN LUBRICANTES', 0.018, 0.31, 0.062, 0.4),
  ZonaMapa('DEPOSITO QUIMICOS', 0.018, 0.09, 0.062, 0.18),
  ZonaMapa('DESCARGA DE GANDOLAS', 0.73, 0.1, 0.78, 0.26),
  ZonaMapa('SEPARADORES OWS', 0.77, 0.24, 0.83, 0.34),
  ZonaMapa('TANQUES AGUA ACEITOSA', 0.893, 0.29, 0.968, 0.385),
  ZonaMapa('LAGUNA DE EVAPORACION', 0.83, 0.02, 1.0, 0.15),
];
