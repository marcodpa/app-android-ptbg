# -*- coding: utf-8 -*-
"""
Llenado del formato oficial SF-OP-FOR-040.

CHECK LIST DE MANTENIMIENTO A COMPRESORES DE AIRE.

Escribe los datos encima del PDF aprobado que esta en `formatos_pdf_nuevos/
Compresores.pdf`, igual que se hace con los formatos SF-OP-FOR-020 de los
equipos rotativos. Asi lo que sale por la impresora es el documento oficial —
con su membrete, su codigo y su revision— y no una reproduccion parecida.

Las coordenadas salen de la propia plantilla: se midieron sobre las etiquetas
impresas ("FECHA:", "SISTEMA:", cada pregunta) y los valores se colocan a su
derecha o en la columna que les toca. Si algun dia se reedita el formato y las
filas se mueven, hay que volver a medirlas; por eso van todas juntas aqui
arriba y no repartidas por el codigo.
"""
from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

from reporte_texto import medicion, observacion
from equipment_report import _clave_historial

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover - se informa al generar.
    fitz = None

PLANTILLA = "Compresores.pdf"
CODIGO = "SF-OP-FOR-040"

FUENTE = "helv"
NEGRO = (0, 0, 0)

# ── Cabecera ────────────────────────────────────────────────────────────────
# (x, y) del texto, tomando la linea base de la etiqueta que tiene al lado.
POS_DISCIPLINA = (101.0, 130.0)
POS_SISTEMA = (101.0, 141.0)
POS_SUBSISTEMA = (360.0, 141.0)
POS_EQUIPO = (101.0, 152.0)
# El valor del TAG empieza en 356.6, igual que el del subsistema justo
# encima: esa columna divide las dos filas. Escribir antes partia el codigo
# con la raya de la tabla.
POS_TAG = (360.0, 152.0)
POS_FECHA = (103.0, 174.0)
# El formato trae impreso "___/___/____" donde va la fecha. Se tapa antes de
# escribir: encima de las rayas la fecha se lee mal, y en el papel el tecnico
# escribiria sobre ellas, no entre ellas.
CAJA_FECHA = (100.5, 166.0, 155.4, 176.0)
POS_H_INICIO = (196.0, 174.0)
POS_H_FIN = (283.0, 174.0)
POS_N_HORAS = (399.0, 174.0)
POS_N_ARRANQUES = (530.0, 174.0)

# ── Inspeccion ──────────────────────────────────────────────────────────────
# Centro vertical de cada una de las once filas, medido sobre su pregunta.
FILAS_INSPECCION = [
    227.2, 253.0, 278.8, 304.5, 330.2, 355.8,
    381.5, 407.1, 432.8, 458.5, 484.2,
]
X_SI = 317.0
X_NO = 344.0
# La observacion es una caja: el texto se ajusta solo si ocupa dos lineas.
OBS_X0, OBS_X1 = 358.0, 556.0
ALTO_FILA = 11.0

# ── Control de mantenimiento ────────────────────────────────────────────────
FILAS_MANTENIMIENTO = [548.0, 579.0, 610.0, 635.0]
X_ULTIMA_FECHA = 186.0
X_HORAS = 276.0
MTTO_OBS_X0, MTTO_OBS_X1 = 358.0, 556.0

# ── Firma ───────────────────────────────────────────────────────────────────
# Nombre y cargo van juntos en la linea de "Nombre:". La de "Firma:" se deja
# libre a proposito: la firma el responsable a mano sobre el papel.
POS_NOMBRE = (88.0, 678.0)

TAM_DATO = 8.0
TAM_OBS = 6.6
TAM_MARCA = 11.0


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
    """Pasa 2026-08-18 a 18/08/2026, que es como se lee en el formato."""
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


def _escribir_caja(pagina, x0, y_centro, x1, valor, tam=TAM_OBS):
    """Texto dentro de una celda, centrado verticalmente y con salto de linea.

    Se usa para las observaciones: en el papel caben dos renglones y el ancho
    de la columna es el que manda, no la longitud de lo que escribio el
    tecnico.
    """
    texto = _texto(valor)
    if not texto:
        return
    caja = fitz.Rect(x0, y_centro - ALTO_FILA, x1, y_centro + ALTO_FILA)
    pagina.insert_textbox(
        caja, texto, fontsize=tam, fontname=FUENTE, color=NEGRO,
        align=0, overlay=True,
    )


def _marca(pagina, x, y_centro):
    """La X de SI o NO, centrada en su casilla."""
    pagina.insert_text(
        (x, y_centro + 3.5), "X", fontsize=TAM_MARCA, fontname=FUENTE,
        color=NEGRO, overlay=True,
    )


def checklist_con_mantenimientos_anteriores(fila: dict, historial=()) -> dict:
    """Resuelve solo para imprimir: nunca modifica ni vuelve a registrar datos.

    Una tarea vacia recupera su ultima fila completa del mismo compresor hasta
    la planilla elegida. No toma mantenimientos de fechas posteriores ni mezcla
    una fecha nueva con horas/observaciones de una tarea anterior.
    """
    actual = {str(k).upper(): v for k, v in fila.items()}

    def clave(row):
        return (_clave_historial({"fecha": row.get("FECHA"), "hora": row.get("HORA")}),
                _texto(row.get("UUID")))

    limite = clave(actual)
    candidatos = [{str(k).upper(): v for k, v in row.items()} for row in historial]
    candidatos = sorted((row for row in candidatos
                         if _texto(row.get("LOCALIZACION")) == _texto(actual.get("LOCALIZACION"))
                         and _texto(row.get("UUID")) != _texto(actual.get("UUID"))
                         and clave(row) <= limite), key=clave, reverse=True)
    for tarea in ("LUB", "INH", "AIR", "ACE"):
        fecha, horas, obs = (f"MTTO_{tarea}_{sufijo}" for sufijo in ("UF", "UH", "OBS"))
        if _texto(actual.get(fecha)) or _texto(actual.get(horas)):
            continue
        for anterior in candidatos:
            if _texto(anterior.get(fecha)) or _texto(anterior.get(horas)):
                for campo in (fecha, horas, obs):
                    actual[campo] = anterior.get(campo)
                break
    return actual


def build_compressor_checklist_pdf(
    fila: dict,
    output_dir: Path,
    templates_dir: Path | str | None = None,
    *,
    historial=(),
) -> Path:
    """Llena el formato oficial y devuelve la ruta del PDF.

    [fila] es un registro de MOT_COMP_CHKL con sus nombres de columna.
    """
    if fitz is None:
        raise RuntimeError(
            "Falta PyMuPDF. Instale con: pip install pymupdf"
        )
    if not fila:
        raise RuntimeError("No hay check list que imprimir.")
    fila = checklist_con_mantenimientos_anteriores(fila, historial)

    carpeta_plantillas = Path(templates_dir or Path(__file__).parent /
                              "formatos_pdf_nuevos")
    plantilla = carpeta_plantillas / PLANTILLA
    if not plantilla.exists():
        raise RuntimeError(
            f"No se encontro la plantilla del formato: {plantilla}"
        )

    documento = fitz.open(str(plantilla))
    pagina = documento[0]

    # Cabecera.
    _escribir(pagina, POS_DISCIPLINA, "MECANICA")
    _escribir(pagina, POS_SISTEMA, "AIRE COMPRIMIDO")
    _escribir(pagina, POS_SUBSISTEMA, fila.get("SUBSISTEMA"))
    _escribir(pagina, POS_EQUIPO, fila.get("EQUIPO"))
    _escribir(pagina, POS_TAG, fila.get("TAG"))
    pagina.draw_rect(
        fitz.Rect(*CAJA_FECHA), color=None, fill=(1, 1, 1), overlay=True,
    )
    _escribir(pagina, POS_FECHA, _fecha_legible(fila.get("FECHA")))
    _escribir(pagina, POS_H_INICIO, fila.get("H_INICIO"))
    _escribir(pagina, POS_H_FIN, fila.get("H_FIN"))
    _escribir(pagina, POS_N_HORAS, medicion(fila.get("N_HORAS")))
    _escribir(pagina, POS_N_ARRANQUES, medicion(fila.get("N_ARRANQUES")))

    # Las once inspecciones.
    for indice, y in enumerate(FILAS_INSPECCION, start=1):
        respuesta = _entero(fila.get(f"ACT{indice}")) == 1
        _marca(pagina, X_SI if respuesta else X_NO, y)
        _escribir_caja(
            pagina, OBS_X0, y, OBS_X1,
            observacion(fila.get(f"ACT{indice}_OBS")),
        )

    # Control de mantenimiento.
    for clave, y in zip(("LUB", "INH", "AIR", "ACE"), FILAS_MANTENIMIENTO):
        sin_registro = not (_texto(fila.get(f"MTTO_{clave}_UF")) or
                            _texto(fila.get(f"MTTO_{clave}_UH")))
        _escribir(
            pagina, (X_ULTIMA_FECHA, y + 3),
            _fecha_legible(fila.get(f"MTTO_{clave}_UF")),
        )
        _escribir(
            pagina, (X_HORAS, y + 3), medicion(fila.get(f"MTTO_{clave}_UH"))
        )
        _escribir_caja(
            pagina, MTTO_OBS_X0, y, MTTO_OBS_X1,
            "SIN REGISTRO PREVIO" if sin_registro else observacion(fila.get(f"MTTO_{clave}_OBS")),
        )

    # Quien lo hizo. La aprobacion se deja en blanco: la firma el supervisor
    # sobre el papel impreso.
    responsable = _texto(fila.get("USUARIO"))
    cargo = _texto(fila.get("CARGO"))
    if responsable and cargo:
        responsable = f"{responsable}  ·  {cargo}"
    _escribir(pagina, POS_NOMBRE, responsable)

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    etiqueta = re.sub(
        r"[^A-Za-z0-9_-]+", "-",
        _texto(fila.get("TAG")) or f"LOC-{_entero(fila.get('LOCALIZACION'))}",
    ).strip("-")
    marca = datetime.now().strftime("%Y%m%d-%H%M%S")
    pdf_path = output_dir / f"{CODIGO}_{etiqueta}_{marca}.pdf"
    documento.save(str(pdf_path))
    documento.close()
    return pdf_path
