# -*- coding: utf-8 -*-
"""
mapa_planta.py — Donde esta cada equipo en el plano de la planta.
=================================================================

Este archivo dice, para cada equipo, en que punto del plano se dibuja su
marcador en la app. Es lo unico que hay que llenar: el resto —el mapa, el
zoom, abrir el equipo al tocarlo— ya lo resuelve la aplicacion.

COMO SE LLENA
-------------
Hay dos formas, y las dos escriben en este mismo archivo:

  1. A mano. Cambia el `(None, None)` de cada equipo por sus coordenadas.

  2. Con la herramienta, que es mucho mas rapido:

         python ubicar_equipos.py       (o ubicar_equipos.html)

     Abre el plano, te va pidiendo equipo por equipo, haces clic donde esta y
     al terminar guarda aqui mismo. Se puede cerrar y retomar: lo ya colocado
     no se vuelve a preguntar.

LAS COORDENADAS
---------------
Van de 0 a 1, como fraccion del ancho y del alto de la imagen:

    (0.0, 0.0) ......... esquina superior IZQUIERDA
    (1.0, 1.0) ......... esquina inferior DERECHA
    (0.5, 0.5) ......... el centro del plano

Se usan fracciones y no pixeles a proposito: si algun dia el plano se
reexporta mas grande o mas chico, los marcadores siguen cayendo en el mismo
sitio y no hay que rehacer nada.

Un equipo en `(None, None)` simplemente no aparece en el mapa. No rompe nada,
asi que se puede ir llenando por partes.
"""

# Nombre del archivo del plano, dentro de assets/images/ en la app.
PLANO = "plano_planta.png"

# ── Un equipo por linea: LOCALIZACION: (x, y) ────────────────────────────
EQUIPOS = {

    # ── TURBINA BG-1 ────────────────────────────────────────
      1: (0.3386, 0.4564),      # BOOSTER              · 11-MOT-6241        · COMBUSTIBLE_LIQUIDO
      2: (0.3411, 0.4764),      # NOX-LIQUIDO          · 11-MOT-6242        · WATER INJECTION HIGH PRESSURE
      3: (0.3410, 0.4675),      # NOX-GAS              · 11-MOT-62059       · WATER INJECTION LOW PRESSURE
      4: (0.3572, 0.4255),      # VENT TURB A          · 11-MOT-6417        · AIRE PARA VENTILACION Y COMBUSTION
      5: (0.3635, 0.4258),      # VENT TURB B          · 11-MOT-6418        · AIRE PARA VENTILACION Y COMBUSTION
      6: (0.3569, 0.4708),      # VENT GEN A           · 11-MOT-6413        · AIRE PARA VENTILACION Y COMBUSTION
      7: (0.3635, 0.4719),      # VENT GEN B           · 11-MOT-6416        · AIRE PARA VENTILACION Y COMBUSTION
     15: (0.3338, 0.4145),      # FIN FAN A            · 11-MOT-6090        · LUBRICACION TURBINA
     17: (0.3337, 0.3992),      # FIN FAN B            · 11-MOT-6091        · LUBRICACION TURBINA
     19: (0.3479, 0.4421),      # HYD-STR              · 11-MOT-1615        · ARRANCADOR HIDRAULICO
     20: (0.3474, 0.4566),      # SPRINT               · 11-MOT-62226       · SPRINT
     52: (None, None),          # WATER WASH           · 11-MOT-6535        · LAVADO_CON_AGUA_AXIAL

    # ── TURBINA BG-2 ────────────────────────────────────────
      8: (0.4437, 0.4553),      # BOOSTER              · 12-MOT-6241        · COMBUSTIBLE LIQUIDO
      9: (0.4487, 0.4748),      # NOX-LIQUIDO          · 12-MOT-6242        · WATER INJECTION HIGH PRESSURE
     10: (0.4484, 0.4668),      # NOX-GAS              · 12-MOT-62059       · WATER INJECTION LOW PRESSURE
     11: (0.4624, 0.4256),      # VENT TURB A          · 12-MOT-6417        · AIRE PARA VENTILACION Y COMBUSTION
     12: (0.4689, 0.4248),      # VENT TURB B          · 12-MOT-6418        · AIRE PARA VENTILACION Y COMBUSTION
     13: (0.4629, 0.4687),      # VENT GEN A           · 12-MOT-6413        · AIRE PARA VENTILACION Y COMBUSTION
     14: (0.4691, 0.4685),      # VENT GEN B           · 12-MOT-6416        · AIRE PARA VENTILACION Y COMBUSTION
     16: (0.4385, 0.3993),      # FIN FAN B            · 12-MOT-6091        · LUBRICACION TURBINA
     18: (0.4388, 0.4141),      # FIN FAN A            · 12-MOT-6090        · LUBRICACION TURBINA
     21: (0.4546, 0.4396),      # HYD-STR              · 12-MOT-1615        · ARRANCADOR HIDRAULICO
     22: (0.4530, 0.4579),      # SPRINT               · 12-MOT-62226       · SPRINT

    # ── FUEL OIL ────────────────────────────────────────────
     34: (0.4025, 0.3093),      # 11FO-04A             · 11-FO-CP-004A      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE
     35: (0.4068, 0.3091),      # 11FO-04B             · 11-FO-CP-004B      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE
     36: (0.4102, 0.3090),      # 11FO-04C             · 11-FO-CP-004C      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE
     37: (0.4158, 0.3119),      # 12FO-04A             · 12-FO-CP-004A      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE
     38: (0.4193, 0.3116),      # 12FO-04B             · 12-FO-CP-004B      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE
     39: (0.4230, 0.3114),      # 12FO-04C             · 12-FO-CP-004C      · COMBUSTIBLE TRATADO ENVIO DE COMBUSTIBLE

    # ── DEMINERALIZED WATER ─────────────────────────────────
     23: (0.2694, 0.4208),      # 11DW-02A             · 11-DW-CP-002A      · AGUA DESMINERALIZADA
     24: (0.2687, 0.4126),      # 11DW-02B             · 11-DW-CP-002B      · AGUA DESMINERALIZADA
     25: (0.2698, 0.4025),      # 11DW-02C             · 11-DW-CP-002C      · AGUA DESMINERALIZADA
     26: (0.2700, 0.3914),      # 12DW-02A             · 12-DW-CP-002A      · AGUA DESMINERALIZADA
     27: (0.2685, 0.3818),      # 12DW-02B             · 12-DW-CP-002B      · AGUA DESMINERALIZADA
     28: (0.2685, 0.3731),      # 12DW-02C             · 12-DW-CP-002C      · AGUA DESMINERALIZADA
     29: (0.2673, 0.4455),      # 10DW-03A             · 10-DW-CP-003A      · AGUA DESMINERALIZADA
     30: (0.2670, 0.4372),      # 10DW-03B             · 10-DW-CP-003B      · AGUA DESMINERALIZADA

    # ── S.C.I ───────────────────────────────────────────────
     31: (0.2603, 0.0844),      # 10FW-01              · SCI ELECTRIC MOTOR · CONTRA INCENDIO
     32: (0.2605, 0.1149),      # 10FW-02              · DIESEL MOTOR       · CONTRA INCENDIO
     33: (0.2554, 0.0823),      # 10FW-03              · JOCKEY MOTOR       · CONTRA INCENDIO

    # ── CENTRIFUGADORAS ─────────────────────────────────────
     40: (0.4610, 0.3183),      # 12-05-DO-EM101-S     · 12-05-DO-EM101-S   · TRATAMIENTO DE COMBUSTIBLE
     41: (0.4830, 0.3186),      # 12-05-DO-EM101-D     · 12-05-DO-EM101-D   · TRATAMIENTO DE COMBUSTIBLE
     42: (0.4830, 0.3157),      # 12-05-DO-EM201       · 12-05-DO-EM201     · TRATAMIENTO DE COMBUSTIBLE
     43: (0.4680, 0.3166),      # 17-06-DO_EM101_S     · 17-06-DO_EM101_S   · TRATAMIENTO DE COMBUSTIBLE
     44: (0.4914, 0.3180),      # 17-06-DO_EM101_D     · 17-06-DO_EM101_D   · TRATAMIENTO DE COMBUSTIBLE
     45: (0.4962, 0.3181),      # 17-06-DO_EM201       · 17-06-DO_EM201     · TRATAMIENTO DE COMBUSTIBLE

    # ── SKID DE PRUEBA ──────────────────────────────────────
     46: (None, None),          # B_NOX                · B_NOX              · SKID DE PRUEBA
     47: (None, None),          # VENT                 · VENT               · SKID DE PRUEBA

    # ── AGUA POTABLE ────────────────────────────────────────
     48: (0.2679, 0.2218),      # 10PW-01A             · 10-PW-CP-001A      · AGUA DE SERVICIO
     49: (0.2684, 0.2126),      # 10PW-01B             · 10-PW-CP-001B      · AGUA DE SERVICIO
     50: (0.2693, 0.2636),      # 10RW-02A             · 10-RW-CP-002A      · AGUA CRUDA
     51: (0.2684, 0.2533),      # 10RW-02B             · 10-RW-CP-002B      · AGUA CRUDA

    # ── AIRE COMPRIMIDO ─────────────────────────────────────
     53: (0.3139, 0.3156),      # COMPRESOR A          · 10-IA-CPR-001A     · SISTEMA DE AIRE INSTRUMENTOS
     54: (0.3209, 0.3156),      # COMPRESOR B          · 10-IA-CPR-001B     · SISTEMA DE AIRE INSTRUMENTOS
     55: (0.3286, 0.3161),      # COMPRESOR C          · 10-SA-CPR-001      · SISTEMA DE AIRE DE USO GENERAL
}


# El black start no esta en la lista de arriba porque no tiene LOCALIZACION:
# es uno solo en la planta y su registro no cuelga de ningun equipo.
BLACK_START = (0.3382, 0.7121)


# ── Zonas del plano (opcional) ───────────────────────────────────────────────
#
# Rotulos de area que se dibujan sobre el mapa para ubicarse: "PATIO 138kV",
# "TANQUES FO", "SALA DE CONTROL". No hacen falta para que el mapa funcione,
# pero ayudan a leerlo cuando se ve la planta completa sin zoom.
#
# Cada zona es un rectangulo: (x0, y0, x1, y1) en las mismas fracciones.
ZONAS = {
    # Transcritas de los rotulos que ya trae el plano y ajustadas encima de
    # la imagen, recuadro por recuadro.
    "TANQUES DE COMBUSTIBLE":  (0.312, 0.030, 0.755, 0.255),
    "TANQUES FW / RW / DW":    (0.170, 0.055, 0.250, 0.450),
    "PLANTA DEMI":             (0.110, 0.430, 0.170, 0.600),
    "S.C.I":                   (0.243, 0.052, 0.275, 0.130),
    "AGUA POTABLE":            (0.232, 0.185, 0.272, 0.260),
    "FW-BOMBAS":               (0.232, 0.298, 0.272, 0.440),
    "COMPRESORES DE AIRE":     (0.306, 0.262, 0.343, 0.328),
    "MCC-C/D":                 (0.360, 0.262, 0.399, 0.328),
    "FO-BOMBAS":               (0.393, 0.262, 0.451, 0.328),
    "CENTRIFUGADORAS":         (0.453, 0.262, 0.503, 0.328),
    "SISTEMA DE ESPUMA":       (0.506, 0.262, 0.535, 0.328),
    "TURBINA BG-1":            (0.300, 0.360, 0.390, 0.580),
    "TURBINA BG-2":            (0.410, 0.360, 0.500, 0.580),
    "TURBINAS BG-3 / BG-4":    (0.520, 0.360, 0.720, 0.600),
    "GEN. DIESEL":             (0.320, 0.690, 0.370, 0.740),
    "TRANSFORMADORES 138/24":  (0.310, 0.760, 0.440, 0.850),
    "PATIO 138 kV":            (0.470, 0.740, 0.600, 0.860),
    "CELDAS 24 kV":            (0.300, 0.850, 0.400, 0.920),
    "SALA DE RELE":            (0.400, 0.855, 0.447, 0.915),
    "EDIFICIO DE CONTROL":     (0.190, 0.640, 0.260, 0.830),
    "TALLERES":                (0.090, 0.640, 0.190, 0.750),
    "ALMACEN LUBRICANTES":     (0.018, 0.310, 0.062, 0.400),
    "DEPOSITO QUIMICOS":       (0.018, 0.090, 0.062, 0.180),
    "DESCARGA DE GANDOLAS":    (0.730, 0.100, 0.780, 0.260),
    "SEPARADORES OWS":         (0.770, 0.240, 0.830, 0.340),
    "TANQUES AGUA ACEITOSA":   (0.893, 0.290, 0.968, 0.385),
    "LAGUNA DE EVAPORACION":   (0.830, 0.020, 1.000, 0.150),
}


def sin_ubicar():
    """Los equipos que todavia no tienen punto en el plano."""
    return [loc for loc, punto in EQUIPOS.items() if punto[0] is None]


def validar():
    """Revisa que lo colocado tenga sentido. Devuelve la lista de problemas."""
    problemas = []
    for loc, (x, y) in EQUIPOS.items():
        if x is None or y is None:
            continue
        if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            problemas.append(f"LOC-{loc}: ({x}, {y}) esta fuera del plano")
    # Dos equipos en el mismo punto suelen ser un copiar y pegar sin corregir.
    vistos = {}
    for loc, punto in EQUIPOS.items():
        if punto[0] is None:
            continue
        clave = (round(punto[0], 4), round(punto[1], 4))
        if clave in vistos:
            problemas.append(
                f"LOC-{loc} esta exactamente encima de LOC-{vistos[clave]}"
            )
        vistos[clave] = loc
    return problemas


if __name__ == "__main__":
    faltan = sin_ubicar()
    print(f"Equipos en el mapa: {len(EQUIPOS) - len(faltan)} de {len(EQUIPOS)}")
    if faltan:
        print("Sin ubicar:", ", ".join(f"LOC-{n}" for n in faltan))
    for problema in validar():
        print("  OJO:", problema)
