# -*- coding: utf-8 -*-
"""
Llenado del formato oficial SF-OP-FOR-036: CHECK LIST BLACK START.

Escribe los datos encima del PDF aprobado que esta en `formatos_pdf_nuevos/
BlackStart.pdf`, igual que los formatos de compresores y de equipos rotativos.
Asi lo que sale por la impresora es el documento oficial y no una copia.

Las coordenadas se midieron sobre la propia plantilla: las lineas de la tabla
dan las columnas y las filas, y las etiquetas impresas dan la altura de cada
renglon. Van todas juntas aqui arriba porque si algun dia se reedita el
formato hay que volver a medirlas.
"""
from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

from reporte_texto import medicion, observacion

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover - se informa al generar.
    fitz = None

PLANTILLA = "BlackStart.pdf"
CODIGO = "SF-OP-FOR-036"

FUENTE = "helv"
NEGRO = (0, 0, 0)

# ── Fecha ───────────────────────────────────────────────────────────────────
# El formato trae impreso "/  /" donde va la fecha; se tapa antes de escribir.
CAJA_FECHA = (462.0, 119.0, 525.0, 134.0)
POS_FECHA = (466.0, 131.5)

# ── Parametros y variables operativas ───────────────────────────────────────
# La columna DESCRIPCION va de 407.4 a 524.9 y en estas filas esta unida, asi
# que el valor se centra en todo el ancho.
PARAM_X0, PARAM_X1 = 408.0, 524.5
FILAS_PARAMETROS = [168.0, 189.2, 210.6, 232.1, 253.6, 275.1]

# ── Estados y verificaciones de componentes ─────────────────────────────────
# Aqui la misma franja se parte en dos: APTO y NO APTO.
APTO_X0, APTO_X1 = 408.0, 463.0
NO_APTO_X0, NO_APTO_X1 = 464.0, 524.5
FILAS_COMPONENTES = [307.7, 328.9, 350.3, 371.8]

# ── Observaciones ───────────────────────────────────────────────────────────
CAJA_OBSERVACIONES = (82.0, 448.0, 521.0, 513.0)

# ── Firma de quien lo realizo ───────────────────────────────────────────────
# Solo la primera de las tres columnas: revisado y aprobado los firma otra
# persona sobre el papel.
POS_NOMBRE = (110.0, 578.5)
POS_CARGO = (105.0, 592.6)

TAM_DATO = 9.0
TAM_OBS = 8.0
TAM_MARCA = 12.0
ALTO_CELDA = 9.0

# Cada parametro con el titulo tal como esta impreso en el formato.
#
# La unidad se saca del parentesis del titulo y se imprime junto al valor: en
# la columna DESCRIPCION un "85" suelto no dice si son por ciento, voltios o
# grados, y obliga a devolver la vista a la izquierda para entenderlo.
PARAMETROS = [
    ("trabajo_hrs", "HORAS DE TRABAJO (Hrs)"),
    ("refrigerante_lvl", "NIVEL DE REFRIGERANTE (%)"),
    ("combustible_lvl", "NIVEL DE COMBUSTIBLE (%)"),
    ("aceite_lvl", "NIVEL DE ACEITE (%)"),
    ("voltaje_bat", "VOLTAJE DE BATERIAS (V DC)"),
    ("amperaje_bat", "AMPERAJE DE BATERIAS (Amp DC)"),
]


def _unidad(titulo: str) -> str:
    """La nomenclatura del titulo, sin parentesis.

    Se deriva del titulo en vez de escribirla aparte para que no puedan
    quedar desincronizadas: si el formato cambia "(%)" por "(bar)", basta
    corregir el titulo de arriba.
    """
    match = re.search(r"\(([^)]+)\)\s*$", titulo.strip())
    return match.group(1).strip() if match else ""


def _con_unidad(valor, titulo: str) -> str:
    """El valor seguido de su unidad, o vacio si no se midio."""
    texto = medicion(valor)
    if not texto:
        return ""
    if texto == "/":
        return texto
    unidad = _unidad(titulo)
    return f"{texto} {unidad}" if unidad else texto

COMPONENTES = ["filtro_aceite", "filtro_aire", "panel_control", "correa"]


def _texto(valor) -> str:
    if valor is None:
        return ""
    return str(valor).strip()


def _entero(valor) -> int:
    try:
        return int(valor or 0)
    except (TypeError, ValueError):
        return 0


def _fecha_legible(valor) -> str:
    texto = _texto(valor)
    match = re.match(r"^(\d{4})-(\d{2})-(\d{2})", texto)
    if match:
        return f"{match.group(3)}/{match.group(2)}/{match.group(1)}"
    return texto


def _escribir(pagina, posicion, valor, tam=TAM_DATO):
    texto = _texto(valor)
    if not texto:
        return
    pagina.insert_text(
        posicion, texto, fontsize=tam, fontname=FUENTE, color=NEGRO,
        overlay=True,
    )


def _centrar(pagina, x0, x1, y_centro, valor, tam=TAM_DATO):
    """Valor centrado en su celda.

    Se centra y no se alinea a la izquierda porque son cifras sueltas en una
    columna: alineadas al borde se leen como si colgaran de la raya.

    Se calcula el ancho y se usa insert_text en vez de una caja con align
    centrado: insert_textbox no dibuja NADA si el texto no le cabe con su
    interlineado, y con la X a 12 pt en una celda de 21 pt no cabia. Fallaba
    en silencio, que es lo peor que puede hacer: el formato salia impreso con
    las casillas vacias como si nadie hubiera revisado nada.
    """
    texto = _texto(valor)
    if not texto:
        return
    ancho = fitz.get_text_length(texto, fontname=FUENTE, fontsize=tam)
    x = x0 + ((x1 - x0) - ancho) / 2
    # El desplazamiento vertical lleva la linea base al centro optico de la
    # celda: sin el, el texto se apoya en el borde de arriba.
    pagina.insert_text(
        (x, y_centro + tam * 0.35), texto, fontsize=tam, fontname=FUENTE,
        color=NEGRO, overlay=True,
    )


def build_black_start_pdf(
    fila: dict,
    output_dir: Path,
    templates_dir: Path | str | None = None,
) -> Path:
    """Llena el formato oficial y devuelve la ruta del PDF.

    [fila] es un registro de MOT_BLKS_CHKL con sus nombres de columna.
    """
    if fitz is None:
        raise RuntimeError("Falta PyMuPDF. Instale con: pip install pymupdf")
    if not fila:
        raise RuntimeError("No hay check list que imprimir.")

    carpeta = Path(templates_dir or Path(__file__).parent /
                   "formatos_pdf_nuevos")
    plantilla = carpeta / PLANTILLA
    if not plantilla.exists():
        raise RuntimeError(f"No se encontro la plantilla: {plantilla}")

    documento = fitz.open(str(plantilla))
    pagina = documento[0]

    pagina.draw_rect(
        fitz.Rect(*CAJA_FECHA), color=None, fill=(1, 1, 1), overlay=True,
    )
    _escribir(pagina, POS_FECHA, _fecha_legible(fila.get("FECHA")))

    for (clave, titulo), y in zip(PARAMETROS, FILAS_PARAMETROS):
        _centrar(
            pagina, PARAM_X0, PARAM_X1, y,
            _con_unidad(fila.get(clave.upper()), titulo),
        )

    for clave, y in zip(COMPONENTES, FILAS_COMPONENTES):
        apto = _entero(fila.get(clave.upper())) == 1
        if apto:
            _centrar(pagina, APTO_X0, APTO_X1, y, "X", tam=TAM_MARCA)
        else:
            _centrar(pagina, NO_APTO_X0, NO_APTO_X1, y, "X", tam=TAM_MARCA)

    observaciones = observacion(fila.get("OBSERVACIONES"))
    if observaciones:
        pagina.insert_textbox(
            fitz.Rect(*CAJA_OBSERVACIONES), observaciones,
            fontsize=TAM_OBS, fontname=FUENTE, color=NEGRO,
            align=0, overlay=True,
        )

    _escribir(pagina, POS_NOMBRE, fila.get("USUARIO"))
    _escribir(pagina, POS_CARGO, fila.get("CARGO"), tam=TAM_OBS)

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    marca = datetime.now().strftime("%Y%m%d-%H%M%S")
    pdf_path = output_dir / f"{CODIGO}_BLACK-START_{marca}.pdf"
    documento.save(str(pdf_path))
    documento.close()
    return pdf_path
