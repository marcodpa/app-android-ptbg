import '../models/models.dart';

// Tipo de equipo -> imagen asset
const Map<String, String> tipoImagenMap = {
  'C': 'assets/images/tipo_caja_bomba.png',     // Motor-Caja-Bomba
  'A': 'assets/images/tipo_motor_bomba.png',    // Motor-Bomba horizontal
  'B': 'assets/images/tipo_bomba_vertical.png', // Motor-Bomba vertical
  'E': 'assets/images/tipo_fin_fan.png',        // Ventilador radial / Fin Fan
  'D': 'assets/images/tipo_ventilador.png',     // Motor-Correa-Ventilador
};

// Nombre tipo legible
const Map<String, String> tipoNombreMap = {
  'A': 'Motor-Bomba',
  'B': 'Bomba Vertical',
  'C': 'Motor-Caja-Bomba',
  'D': 'Motor-Correa-Ventilador',
  'E': 'Ventilador Radial',
};

// Detectar tipo por nombre de equipo
String detectarTipo(String nombre, int puntos) {
  final n = nombre.toUpperCase();
  if (n.contains('NOX')) return 'C';
  if (n.contains('FIN FAN')) return 'E';
  if (n.contains('VENT GEN') || n.contains('VEN GEN')) return 'E';
  if (n.contains('VENT TURB') || n.contains('VEN TURB')) return 'D';
  if (n.contains('SPRINT') || n.contains('JOCKEY') || puntos == 2) return 'B';
  return 'A';
}

// Version del catalogo incrustado. Al subirla, la app limpia el cache viejo
// de la tablet y vuelve a sembrar este catalogo (para que los TAC nuevos
// funcionen offline aunque hubiera un catalogo anterior guardado).
const int catalogoBaseVersion = 2;

// Catalogo REAL de PTBG (PTBG_DAT.MOT_EQUIPO). qrCode = CODE_QR (el TAC).
// Generado desde /equipos. Sirve como catalogo OFFLINE incrustado en la app.
final List<Equipo> mockEquipos = [
  Equipo(id:1, codeSys:1, localizacion:1, equipo:'BOOSTER', qrCode:'11-MOT-6241', puntos:1, ptEq:1, sistema:'TURBINA BG-1', scada:'MOT-6241'),
  Equipo(id:2, codeSys:1, localizacion:2, equipo:'NOX-LIQUIDO', qrCode:'11-MOT-6242', puntos:6, ptEq:6, sistema:'TURBINA BG-1', scada:'MOT-6242'),
  Equipo(id:3, codeSys:1, localizacion:3, equipo:'NOX-GAS', qrCode:'11-MOT-62059', puntos:6, ptEq:6, sistema:'TURBINA BG-1', scada:'MOT-62059'),
  Equipo(id:4, codeSys:1, localizacion:4, equipo:'VENT TURB A', qrCode:'11-MOT-6417', puntos:5, ptEq:5, sistema:'TURBINA BG-1', scada:'MOT-6417'),
  Equipo(id:5, codeSys:1, localizacion:5, equipo:'VENT TURB B', qrCode:'11-MOT-6418', puntos:5, ptEq:5, sistema:'TURBINA BG-1', scada:'MOT-6418'),
  Equipo(id:11, codeSys:1, localizacion:6, equipo:'VENT GEN A', qrCode:'11-MOT-6413', puntos:5, ptEq:5, sistema:'TURBINA BG-1', scada:'MOT-6413'),
  Equipo(id:12, codeSys:1, localizacion:7, equipo:'VENT GEN B', qrCode:'11-MOT-6416', puntos:5, ptEq:5, sistema:'TURBINA BG-1', scada:'MOT-6416'),
  Equipo(id:6, codeSys:2, localizacion:8, equipo:'BOOSTER', qrCode:'12-MOT-6241', puntos:1, ptEq:1, sistema:'TURBINA BG-2', scada:'MOT-6241'),
  Equipo(id:7, codeSys:2, localizacion:9, equipo:'NOX-LIQUIDO', qrCode:'12-MOT-6242', puntos:6, ptEq:6, sistema:'TURBINA BG-2', scada:'MOT-6242'),
  Equipo(id:8, codeSys:2, localizacion:10, equipo:'NOX-GAS', qrCode:'12-MOT-62059', puntos:6, ptEq:6, sistema:'TURBINA BG-2', scada:'MOT-62059'),
  Equipo(id:9, codeSys:2, localizacion:11, equipo:'VENT TURB A', qrCode:'12-MOT-6417', puntos:5, ptEq:5, sistema:'TURBINA BG-2', scada:'MOT-6417'),
  Equipo(id:10, codeSys:2, localizacion:12, equipo:'VENT TURB B', qrCode:'12-MOT-6418', puntos:5, ptEq:5, sistema:'TURBINA BG-2', scada:'MOT-6418'),
  Equipo(id:13, codeSys:2, localizacion:13, equipo:'VENT GEN A', qrCode:'12-MOT-6413', puntos:5, ptEq:5, sistema:'TURBINA BG-2', scada:'MOT-6413'),
  Equipo(id:14, codeSys:2, localizacion:14, equipo:'VENT GEN B', qrCode:'12-MOT-6416', puntos:5, ptEq:5, sistema:'TURBINA BG-2', scada:'MOT-6416'),
  Equipo(id:15, codeSys:1, localizacion:15, equipo:'FIN FAN A', qrCode:'11-MOT-6090', puntos:4, ptEq:4, sistema:'TURBINA BG-1', scada:'MOT-6090'),
  Equipo(id:16, codeSys:2, localizacion:16, equipo:'FIN FAN B', qrCode:'12-MOT-6091', puntos:4, ptEq:4, sistema:'TURBINA BG-2', scada:'MOT-6091'),
  Equipo(id:17, codeSys:1, localizacion:17, equipo:'FIN FAN B', qrCode:'11-MOT-6091', puntos:4, ptEq:4, sistema:'TURBINA BG-1', scada:'MOT-6091'),
  Equipo(id:18, codeSys:2, localizacion:18, equipo:'FIN FAN A', qrCode:'12-MOT-6090', puntos:4, ptEq:4, sistema:'TURBINA BG-2', scada:'MOT-6090'),
  Equipo(id:33, codeSys:1, localizacion:19, equipo:'HYD-STR', qrCode:'11-MOT-1615', puntos:9, ptEq:9, sistema:'TURBINA BG-1', scada:'MOT-1615'),
  Equipo(id:31, codeSys:1, localizacion:20, equipo:'SPRINT', qrCode:'11-MOT-62226', puntos:8, ptEq:8, sistema:'TURBINA BG-1', scada:'MOT-62226'),
  Equipo(id:34, codeSys:2, localizacion:21, equipo:'HYD-STR', qrCode:'12-MOT-1615', puntos:9, ptEq:9, sistema:'TURBINA BG-2', scada:'MOT-1615'),
  Equipo(id:32, codeSys:2, localizacion:22, equipo:'SPRINT', qrCode:'12-MOT-62226', puntos:8, ptEq:8, sistema:'TURBINA BG-2', scada:'MOT-62226'),
  Equipo(id:39, codeSys:4, localizacion:23, equipo:'11DW-02A', qrCode:'11-DW-CP-002A', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'11-DW-CP-002A'),
  Equipo(id:40, codeSys:4, localizacion:24, equipo:'11DW-02B', qrCode:'11-DW-CP-002B', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'11-DW-CP-002B'),
  Equipo(id:41, codeSys:4, localizacion:25, equipo:'11DW-02C', qrCode:'11-DW-CP-002C', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'11-DW-CP-002C'),
  Equipo(id:42, codeSys:4, localizacion:26, equipo:'12DW-02A', qrCode:'12-DW-CP-002A', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'12-DW-CP-002A'),
  Equipo(id:43, codeSys:4, localizacion:27, equipo:'12DW-02B', qrCode:'12-DW-CP-002B', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'12-DW-CP-002B'),
  Equipo(id:44, codeSys:4, localizacion:28, equipo:'12DW-02C', qrCode:'12-DW-CP-002C', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'12-DW-CP-002C'),
  Equipo(id:45, codeSys:4, localizacion:29, equipo:'10DW-03A', qrCode:'10-DW-CP-003A', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'10-DW-CP-003A'),
  Equipo(id:46, codeSys:4, localizacion:30, equipo:'10DW-03B', qrCode:'10-DW-CP-003B', puntos:1, ptEq:1, sistema:'DEMINERALIZED WATER', scada:'10-DW-CP-003B'),
  Equipo(id:28, codeSys:5, localizacion:31, equipo:'10FW-01', qrCode:'SCI ELECTRIC MOTOR', puntos:2, ptEq:2, sistema:'S.C.I', scada:'SCI ELECTRIC MOTOR'),
  Equipo(id:29, codeSys:5, localizacion:32, equipo:'10FW-02', qrCode:'DIESEL MOTOR', puntos:3, ptEq:3, sistema:'S.C.I', scada:'DIESEL MOTOR'),
  Equipo(id:30, codeSys:5, localizacion:33, equipo:'10FW-03', qrCode:'JOCKEY MOTOR', puntos:7, ptEq:7, sistema:'S.C.I', scada:'JOCKEY MOTOR'),
  Equipo(id:19, codeSys:3, localizacion:34, equipo:'11FO-04A', qrCode:'11-FO-CP-004A', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'11-FO-CP-004A'),
  Equipo(id:20, codeSys:3, localizacion:35, equipo:'11FO-04B', qrCode:'11-FO-CP-004B', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'11-FO-CP-004B'),
  Equipo(id:21, codeSys:3, localizacion:36, equipo:'11FO-04C', qrCode:'11-FO-CP-004C', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'11-FO-CP-004C'),
  Equipo(id:22, codeSys:3, localizacion:37, equipo:'12FO-04A', qrCode:'12-FO-CP-004A', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'12-FO-CP-004A'),
  Equipo(id:23, codeSys:3, localizacion:38, equipo:'12FO-04B', qrCode:'12-FO-CP-004B', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'12-FO-CP-004B'),
  Equipo(id:24, codeSys:3, localizacion:39, equipo:'12FO-04C', qrCode:'12-FO-CP-004C', puntos:1, ptEq:1, sistema:'FUEL OIL', scada:'12-FO-CP-004C'),
  Equipo(id:25, codeSys:6, localizacion:40, equipo:'12-05-DO-EM101-S', qrCode:'12-05-DO-EM101-S', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'12-05-DO-EM101-S'),
  Equipo(id:26, codeSys:6, localizacion:41, equipo:'12-05-DO-EM101-D', qrCode:'12-05-DO-EM101-D', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'12-05-DO-EM101-D'),
  Equipo(id:27, codeSys:6, localizacion:42, equipo:'12-05-DO-EM201', qrCode:'12-05-DO-EM201', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'12-05-DO-EM201'),
  Equipo(id:47, codeSys:6, localizacion:43, equipo:'17-06-DO_EM101_S', qrCode:'17-06-DO_EM101_S', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'17-06-DO_EM101_S'),
  Equipo(id:48, codeSys:6, localizacion:44, equipo:'17-06-DO_EM101_D', qrCode:'17-06-DO_EM101_D', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'17-06-DO_EM101_D'),
  Equipo(id:49, codeSys:6, localizacion:45, equipo:'17-06-DO_EM201', qrCode:'17-06-DO_EM201', puntos:1, ptEq:1, sistema:'CENTRIFUGADORAS', scada:'17-06-DO_EM201'),
  Equipo(id:50, codeSys:7, localizacion:46, equipo:'B_NOX', qrCode:'B_NOX', puntos:6, ptEq:6, sistema:'SKID DE PRUEBA', scada:'B_NOX'),
  Equipo(id:51, codeSys:7, localizacion:47, equipo:'VENT', qrCode:'VENT', puntos:5, ptEq:5, sistema:'SKID DE PRUEBA', scada:'VENT'),
  Equipo(id:35, codeSys:8, localizacion:48, equipo:'10PW-01A', qrCode:'10-PW-CP-001A', puntos:1, ptEq:1, sistema:'AGUA POTABLE', scada:'10-PW-CP-001A'),
  Equipo(id:36, codeSys:8, localizacion:49, equipo:'10PW-01B', qrCode:'10-PW-CP-001B', puntos:1, ptEq:1, sistema:'AGUA POTABLE', scada:'10-PW-CP-001B'),
  Equipo(id:37, codeSys:8, localizacion:50, equipo:'10RW-02A', qrCode:'10-RW-CP-002A', puntos:1, ptEq:1, sistema:'AGUA POTABLE', scada:'10-RW-CP-002A'),
  Equipo(id:38, codeSys:8, localizacion:51, equipo:'10RW-02B', qrCode:'10-RW-CP-002B', puntos:1, ptEq:1, sistema:'AGUA POTABLE', scada:'10-RW-CP-002B'),
];
