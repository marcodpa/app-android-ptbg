"""Generador de reportes PDF profesionales por equipo para SCV-PTBG."""

from __future__ import annotations

import re
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.graphics.charts.linecharts import HorizontalLineChart
from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.graphics.widgets.markers import makeMarker
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from reporte_texto import medicion, observacion

NAVY = colors.HexColor("#0B2146")
TEAL = colors.HexColor("#08A896")
LIGHT = colors.HexColor("#F2F5F8")
MID = colors.HexColor("#D8E0EA")
TEXT = colors.HexColor("#17243A")
MUTED = colors.HexColor("#5D6B7E")

REPORT_LABELS = {
    "integral": "Reporte integral",
    "vibration": "Vibración",
    "temperature": "Temperatura",
    "alignment": "Alineación",
    "lubrication": "Lubricación",
    "replacements": "Reemplazos",
    "coupling_changes": "Cambios de coupling",
    "technical": "Ficha técnica",
}

SECTIONS = {
    "vibration": ("Vibración", ("MEDICIONES_LOCAL", "MEDICIONES_REMOTAS"), tuple(f"{axis}{i}" for i in range(1, 10) for axis in "HVA")),
    "temperature": ("Temperatura", ("TEMPERATURAS_LOCAL", "TEMPERATURAS_REMOTAS"), tuple(f"T{i}" for i in range(1, 11))),
    "alignment": ("Alineación", ("ALINEACIONES_LOCAL", "ALINEACIONES_REMOTAS"), (
        "AMB_ANGULO_V", "AMB_ANGULO_H", "AMB_COMPENSACION_V", "AMB_COMPENSACION_H",
        "ACM_ANGULO_V", "ACM_ANGULO_H", "ACM_COMPENSACION_V", "ACM_COMPENSACION_H",
        "ACB_ANGULO_V", "ACB_ANGULO_H", "ACB_COMPENSACION_V", "ACB_COMPENSACION_H",
    )),
    "lubrication": ("Lubricación", ("LUBRICACIONES_LOCAL", "LUBRICACIONES_REMOTAS"), tuple(f"L{i}" for i in range(1, 10))),
}

FIELD_LABELS = {
    "marca": "Marca", "modelo": "Modelo", "serial": "Serial", "hp": "Potencia (HP)",
    "start": "Arranque", "volts": "Voltaje", "fla": "Corriente", "sf": "Factor de servicio",
    "hz": "Frecuencia", "ph": "Fases", "rpm": "Velocidad (RPM)",
    "brgs_drive": "Rodamiento lado acople", "brgs_opp": "Rodamiento lado libre",
    "lubricacion": "Tipo de lubricación", "motores_lub": "Motores a lubricar",
    "cant_mot_lub": "Cantidad motor (g)", "elec_mot_lub": "Emboladas eléctricas - motor",
    "man_mot_lub": "Emboladas manuales - motor", "elemento_lub": "Elementos a lubricar",
    "cant_elem_lub": "Cantidad elemento (g)", "elec_elem_lub": "Emboladas eléctricas - elemento",
    "man_elem_lub": "Emboladas manuales - elemento",
}

RECORD_LABELS = {
    "equipo": "Componente", "marca": "Marca", "modelo": "Modelo", "serial": "Serial",
    "voltaje": "Voltaje", "corriente": "Corriente", "rpm": "RPM", "sf": "Factor de servicio",
    "hp": "HP", "frame": "Frame", "brgs_drive": "Rodamiento acople", "brgs_opp": "Rodamiento libre",
    "ciclo": "Ciclo", "arranque": "Arranque", "ph": "Fases", "tension": "Tensión",
    "lubricacion": "Lubricación",
}

MEASUREMENT_FIELDS = frozenset(
    field for _, _, fields in SECTIONS.values() for field in fields
) | {"RMS", "voltaje", "corriente", "rpm", "sf", "hp", "ciclo", "ph", "tension"}


def _reading(field: str, value: Any) -> str:
    return medicion(value) if field in MEASUREMENT_FIELDS else _value(value)

CHART_COLORS = (
    colors.HexColor("#08A896"), colors.HexColor("#1677C8"),
    colors.HexColor("#F39C12"), colors.HexColor("#8E5BB7"),
    colors.HexColor("#D94B64"), colors.HexColor("#52796F"),
    colors.HexColor("#6A994E"), colors.HexColor("#BC4749"),
    colors.HexColor("#4361EE"), colors.HexColor("#FF6B35"),
    colors.HexColor("#2A9D8F"), colors.HexColor("#9B5DE5"),
    colors.HexColor("#0077B6"), colors.HexColor("#E76F51"),
    colors.HexColor("#588157"), colors.HexColor("#7209B7"),
    colors.HexColor("#F4A261"), colors.HexColor("#264653"),
)

ISO_ZONE_COLORS = {
    "A": colors.HexColor("#DDF4E4"),
    "B": colors.HexColor("#EAF3C7"),
    "C": colors.HexColor("#FFE4A8"),
    "D": colors.HexColor("#F7B5B5"),
}

POINT_LABELS = {
    10: {1: "Motor - lado libre", 2: "Motor - lado acople"},
    1: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    2: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    3: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    4: {1: "Motor - lado libre", 2: "Motor - lado acople", 9: "Ventilador FIN-FAN - lado libre"},
    5: {1: "Motor - lado libre", 2: "Motor - lado acople", 7: "Ventilador - punto superior", 8: "Ventilador - punto inferior"},
    6: {1: "Motor - lado libre", 2: "Motor - lado acople", 3: "Caja - lado baja", 4: "Caja - lado alta", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    7: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    8: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
    9: {1: "Motor - lado libre", 2: "Motor - lado acople", 5: "Bomba - lado libre", 6: "Bomba - lado acople"},
}


def _point_labels_for(visual_type: int, section: str) -> dict[int, str]:
    labels = dict(POINT_LABELS.get(visual_type, POINT_LABELS[1]))
    if section in {"vibration", "temperature"} and 5 in labels and 6 in labels:
        labels[5], labels[6] = "Bomba - lado acople", "Bomba - lado libre"
    if section == "temperature" and visual_type == 4:
        labels[10] = "Correa del FIN-FAN"
    return labels


def _register_fonts() -> tuple[str, str]:
    candidates = [
        (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/arialbd.ttf")),
        (Path("C:/Windows/Fonts/segoeui.ttf"), Path("C:/Windows/Fonts/seguisb.ttf")),
    ]
    for regular, bold in candidates:
        if regular.exists() and bold.exists():
            try:
                pdfmetrics.registerFont(TTFont("SCVRegular", str(regular)))
                pdfmetrics.registerFont(TTFont("SCVBold", str(bold)))
                return "SCVRegular", "SCVBold"
            except Exception:
                pass
    return "Helvetica", "Helvetica-Bold"


FONT, FONT_BOLD = _register_fonts()


def _value(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if not text or text.lower() in {"none", "null", "nan"}:
        return ""
    return text


def _safe(text: Any) -> str:
    return (_value(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _table_exists(conn: sqlite3.Connection, name: str) -> bool:
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def _clave_historial(row: dict[str, Any]) -> str:
    """Clave ISO ordenable de una fila. El MISMO criterio que la pantalla de
    historial de la tablet (lib/models/historial_servicio.dart): con dos
    recetas distintas, "los ultimos 5" del PDF y los de la pantalla no
    coincidian. Si se cambia aqui, cambiarlo alla tambien."""
    iso = _value(row.get("fecha_hora_iso"))
    if len(iso) >= 19 and not iso.startswith("1970"):
        return iso[:19]

    fecha = _value(row.get("fecha")).split(" ")[0]  # DATETIME trae hora pegada
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", fecha):
        fecha_iso = fecha
    else:
        dmy = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", fecha)
        if not dmy or not (1 <= int(dmy[1]) <= 31 and 1 <= int(dmy[2]) <= 12):
            return "0000-01-01T00:00:00"
        fecha_iso = f"{dmy[3]}-{int(dmy[2]):02d}-{int(dmy[1]):02d}"

    hora = _value(row.get("hora"))
    if re.match(r"^\d{2}:\d{2}:\d{2}", hora):
        hora = hora[:8]
    elif re.fullmatch(r"\d{2}:\d{2}", hora):
        hora = f"{hora}:00"
    elif re.fullmatch(r"\d{1}:\d{2}", hora):
        hora = f"0{hora}:00"
    else:
        hora = "00:00:00"
    return f"{fecha_iso}T{hora}"


def _rows(conn: sqlite3.Connection, tables: Iterable[str], localizacion: int) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    for table in tables:
        if not _table_exists(conn, table):
            continue
        for row in conn.execute(f'SELECT * FROM "{table}" WHERE localizacion=?', (localizacion,)):
            found.append({**dict(row), "_source": table})

    # Una medicion sincronizada vive dos veces: en su tabla *_LOCAL y como
    # espejo en *_REMOTAS. Se agrupa por instante y manda la fila local; los
    # campos que solo trae la remota (equipo, tagname) se completan sin pisar
    # nada. Se conservan TODAS las locales del grupo: un reemplazo escribe una
    # fila por componente con el mismo instante y no son duplicados.
    grupos: dict[str, list[dict[str, Any]]] = {}
    for row in found:
        grupos.setdefault(_clave_historial(row), []).append(row)

    resultado: list[dict[str, Any]] = []
    for grupo in grupos.values():
        locales = [r for r in grupo if str(r.get("_source", "")).endswith("_LOCAL")]
        elegidas = locales if locales else [grupo[0]]
        remotas = [r for r in grupo if r not in elegidas]
        for elegida in elegidas:
            for remota in remotas:
                for clave, valor in remota.items():
                    if _value(valor) and not _value(elegida.get(clave)):
                        elegida[clave] = valor
        resultado.extend(elegidas)

    return sorted(resultado, key=_clave_historial, reverse=True)


def load_equipment_report_data(db_path: Path, localizacion: int) -> dict[str, Any]:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        equipment_row = conn.execute("SELECT * FROM EQUIPOS WHERE LOCALIZACION=? LIMIT 1", (localizacion,)).fetchone()
        if equipment_row is None:
            raise RuntimeError(f"No existe el equipo LOC {localizacion} en la tablet.")
        equipment = dict(equipment_row)
        info_row = conn.execute("SELECT * FROM EQUIPO_INFO WHERE localizacion=? LIMIT 1", (localizacion,)).fetchone() if _table_exists(conn, "EQUIPO_INFO") else None
        info = dict(info_row) if info_row else {}
        histories = {key: _rows(conn, spec[1], localizacion) for key, spec in SECTIONS.items()}
        histories["replacements"] = _rows(conn, ("REEMPLAZOS_LOCAL",), localizacion)
        histories["coupling_changes"] = _rows(conn, ("CAMBIOS_COUPLING_LOCAL",), localizacion)
        return {"equipment": equipment, "info": info, "histories": histories}
    finally:
        conn.close()


def _styles():
    base = getSampleStyleSheet()
    return {
        "cover_title": ParagraphStyle("cover_title", parent=base["Title"], fontName=FONT_BOLD, fontSize=25, leading=30, textColor=colors.white, alignment=TA_LEFT),
        "cover_sub": ParagraphStyle("cover_sub", parent=base["Normal"], fontName=FONT, fontSize=11, leading=16, textColor=colors.HexColor("#C9D8EC")),
        "h1": ParagraphStyle("h1", parent=base["Heading1"], fontName=FONT_BOLD, fontSize=17, leading=21, textColor=NAVY, spaceAfter=8),
        "h2": ParagraphStyle("h2", parent=base["Heading2"], fontName=FONT_BOLD, fontSize=11, leading=14, textColor=TEAL, spaceBefore=8, spaceAfter=5),
        "body": ParagraphStyle("body", parent=base["BodyText"], fontName=FONT, fontSize=8.5, leading=11, textColor=TEXT),
        "small": ParagraphStyle("small", parent=base["BodyText"], fontName=FONT, fontSize=7.3, leading=9, textColor=TEXT),
        "muted": ParagraphStyle("muted", parent=base["BodyText"], fontName=FONT, fontSize=8, leading=11, textColor=MUTED),
        "center": ParagraphStyle("center", parent=base["BodyText"], fontName=FONT_BOLD, fontSize=8, leading=10, textColor=colors.white, alignment=TA_CENTER),
    }


def _p(value: Any, style) -> Paragraph:
    return Paragraph(_safe(value) or "-", style)


def _kv_table(items: list[tuple[str, Any]], styles, columns: int = 2) -> Table | None:
    meaningful = [(label, value) for label, value in items if _value(value)]
    if not meaningful:
        return None
    cells = []
    row = []
    for label, value in meaningful:
        row.append([_p(label, styles["small"]), _p(value, styles["body"])])
        if len(row) == columns:
            cells.append(row); row = []
    if row:
        row.extend([[Paragraph("", styles["small"]), Paragraph("", styles["body"])]] * (columns - len(row)))
        cells.append(row)
    data = []
    for source in cells:
        flat = []
        for label, value in source:
            flat.extend((label, value))
        data.append(flat)
    table = Table(data, colWidths=[31*mm, 55*mm] * columns, repeatRows=0)
    table.setStyle(TableStyle([
        ("FONTNAME", (0,0), (-1,-1), FONT), ("VALIGN", (0,0), (-1,-1), "TOP"),
        ("BACKGROUND", (0,0), (-1,-1), colors.white), ("GRID", (0,0), (-1,-1), 0.35, MID),
        ("BACKGROUND", (0,0), (0,-1), LIGHT), ("BACKGROUND", (2,0), (2,-1), LIGHT),
        ("TEXTCOLOR", (0,0), (-1,-1), TEXT), ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6), ("TOPPADDING", (0,0), (-1,-1), 6), ("BOTTOMPADDING", (0,0), (-1,-1), 6),
    ]))
    return table


def _record_block(title: str, row: dict[str, Any], value_fields: Iterable[str], styles, unit: str = "", field_labels: dict[str, str] | None = None, iso_profile: dict[str, Any] | None = None):
    values = [(field, row.get(field)) for field in value_fields if _value(row.get(field))]
    if not values and not any(_value(row.get(k)) for k in ("observaciones", "odt", "responsable", "cargo", "RMS")):
        return None
    header = Table([[
        _p(title, styles["center"]),
        _p(f"{_value(row.get('fecha'))}  {_value(row.get('hora'))}", styles["center"]),
    ]], colWidths=[112*mm, 62*mm])
    header.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), NAVY), ("VALIGN", (0,0), (-1,-1), "MIDDLE"), ("LEFTPADDING", (0,0), (-1,-1), 7), ("TOPPADDING", (0,0), (-1,-1), 6), ("BOTTOMPADDING", (0,0), (-1,-1), 6)]))
    grid = []
    grid_backgrounds = []
    for i in range(0, len(values), 4):
        group = values[i:i+4]
        cells = []
        backgrounds = []
        for name, value in group:
            suffix = ""
            background = colors.white
            texto = _reading(name, value)
            if texto != "/" and iso_profile and name[:1] in {"H", "V", "A"} and _number(value) is not None:
                zone = _iso_zone(_number(value), iso_profile)
                background = ISO_ZONE_COLORS[zone]
            cells.append(_p(f"{(field_labels or {}).get(name, RECORD_LABELS.get(name, name))}: {texto}{unit if texto != '/' else ''}{suffix}", styles["small"]))
            backgrounds.append(background)
        cells.extend([Paragraph("", styles["small"])] * (4-len(cells)))
        backgrounds.extend([colors.white] * (4-len(backgrounds)))
        grid.append(cells)
        grid_backgrounds.append(backgrounds)
    extras = []
    for key, label in (("RMS", "RMS"), ("odt", "ODT"), ("responsable", "Responsable"), ("cargo", "Cargo"), ("observaciones", "Observaciones")):
        if _value(row.get(key)):
            valor = (observacion(row.get(key)) if key == "observaciones"
                     else medicion(row.get(key)) if key == "RMS" else row.get(key))
            extras.append((label, valor))
    content = [header]
    if grid:
        values_table = Table(grid, colWidths=[43.5*mm]*4)
        value_style = [("GRID", (0,0), (-1,-1), 0.35, MID), ("BACKGROUND", (0,0), (-1,-1), colors.white), ("VALIGN", (0,0), (-1,-1), "TOP"), ("LEFTPADDING", (0,0), (-1,-1), 5), ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5)]
        for row_index, backgrounds in enumerate(grid_backgrounds):
            for col_index, background in enumerate(backgrounds):
                if background != colors.white:
                    value_style.append(("BACKGROUND", (col_index, row_index), (col_index, row_index), background))
        values_table.setStyle(TableStyle(value_style))
        content.append(values_table)
    extra_table = _kv_table(extras, styles, columns=2)
    if extra_table:
        content.append(extra_table)
    content.append(Spacer(1, 5*mm))
    return KeepTogether(content)


def _number(value: Any) -> float | None:
    try:
        return float(_value(value).replace(",", ".")) if _value(value) else None
    except (TypeError, ValueError):
        return None


def _iso_profile(info: dict[str, Any]) -> dict[str, Any]:
    hp = _number(info.get("hp"))
    kw = hp * 0.7457 if hp is not None else None
    if kw is not None and kw <= 15:
        return {"class": "Clase I", "limits": (0.71, 1.8, 4.5), "basis": f"potencia aproximada {kw:.1f} kW"}
    if kw is not None and kw <= 75:
        return {"class": "Clase II", "limits": (1.12, 2.8, 7.1), "basis": f"potencia aproximada {kw:.1f} kW"}
    if kw is not None and kw <= 300:
        return {"class": "Clase III provisional", "limits": (1.8, 4.5, 11.2), "basis": f"potencia aproximada {kw:.1f} kW; soporte rígido por confirmar"}
    return {"class": "Clase II provisional", "limits": (1.12, 2.8, 7.1), "basis": "potencia o tipo de soporte no disponibles"}


def _iso_zone(value: float | None, profile: dict[str, Any]) -> str:
    if value is None:
        return "A"
    ab, bc, cd = profile["limits"]
    if value <= ab:
        return "A"
    if value <= bc:
        return "B"
    if value <= cd:
        return "C"
    return "D"


def _iso_reference_table(profile: dict[str, Any], styles) -> list[Any]:
    ab, bc, cd = profile["limits"]
    rows = [[
        _p(f"≤ {ab:.2f} mm/s", styles["small"]),
        _p(f"> {ab:.2f} a {bc:.2f} mm/s", styles["small"]),
        _p(f"> {bc:.2f} a {cd:.2f} mm/s", styles["small"]),
        _p(f"> {cd:.2f} mm/s", styles["small"]),
    ]]
    table = Table(rows, colWidths=[43.5*mm]*4)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (0,-1), ISO_ZONE_COLORS["A"]),
        ("BACKGROUND", (1,0), (1,-1), ISO_ZONE_COLORS["B"]),
        ("BACKGROUND", (2,0), (2,-1), ISO_ZONE_COLORS["C"]),
        ("BACKGROUND", (3,0), (3,-1), ISO_ZONE_COLORS["D"]),
        ("TEXTCOLOR", (0,0), (-1,0), NAVY), ("GRID", (0,0), (-1,-1), 0.5, colors.white),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"), ("ALIGN", (0,0), (-1,-1), "CENTER"),
        ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]))
    note = Paragraph(
        f"Referencia visual ISO 10816: {profile['class']} ({_safe(profile['basis'])}). "
        "La clase, el tipo de soporte y la parte de la norma aplicable deben confirmarse antes de usar los colores como diagnóstico. "
        "ISO 10816-3 fue retirada y sustituida por la serie ISO 20816.",
        styles["muted"],
    )
    return [Paragraph("Escala de colores de referencia", styles["h2"]), table, Spacer(1, 2*mm), note, Spacer(1, 5*mm)]


def _comparative_table(
    rows: list[dict[str, Any]],
    fields: Iterable[str],
    field_labels: dict[str, str],
    unit: str,
    styles,
    iso_profile: dict[str, Any] | None = None,
    column_label: str = "Medición",
) -> Table:
    header = [_p("Ubicación / lectura", styles["center"])]
    for index, row in enumerate(rows, 1):
        date = _value(row.get("fecha"))
        time_text = _value(row.get("hora"))[:5]
        header.append(Paragraph(
            f"{_safe(column_label)} {index}<br/>{_safe(date)}<br/>{_safe(time_text)}",
            styles["center"],
        ))
    data = [header]
    backgrounds: list[tuple[int, int, Any]] = []
    for field in fields:
        if not any(_value(row.get(field)) for row in rows):
            continue
        table_row = [_p(field_labels.get(field, field), styles["small"])]
        for column, row in enumerate(rows, 1):
            value = row.get(field)
            if not _value(value):
                table_row.append(_p("-", styles["small"]))
                continue
            suffix = ""
            texto = _reading(field, value)
            if texto != "/" and iso_profile and field[:1] in {"H", "V", "A"} and _number(value) is not None:
                zone = _iso_zone(_number(value), iso_profile)
                backgrounds.append((column, len(data), ISO_ZONE_COLORS[zone]))
            table_row.append(Paragraph(
                _safe(f"{texto}{unit if texto != '/' else ''}{suffix}"),
                styles["small"],
            ))
        data.append(table_row)
    for key, label in (("responsable", "Responsable"), ("cargo", "Cargo"), ("odt", "ODT"), ("observaciones", "Observaciones")):
        if not any(_value(row.get(key)) for row in rows):
            continue
        data.append([_p(label, styles["small"])] + [
            _p(observacion(row.get(key)) if key == "observaciones"
               else row.get(key), styles["small"])
            for row in rows
        ])
    measurement_width = 110*mm / max(1, len(rows))
    table = Table(data, colWidths=[64*mm] + [measurement_width]*len(rows), repeatRows=1)
    table_style = [
        ("BACKGROUND", (0,0), (-1,0), NAVY), ("TEXTCOLOR", (0,0), (-1,0), colors.white),
        ("BACKGROUND", (0,1), (0,-1), LIGHT), ("GRID", (0,0), (-1,-1), 0.4, MID),
        ("VALIGN", (0,0), (-1,-1), "TOP"), ("ALIGN", (1,1), (-1,-1), "CENTER"),
        ("LEFTPADDING", (0,0), (-1,-1), 4), ("RIGHTPADDING", (0,0), (-1,-1), 4),
        ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]
    for column, row_index, background in backgrounds:
        table_style.append(("BACKGROUND", (column, row_index), (column, row_index), background))
    table.setStyle(TableStyle(table_style))
    return table


def _field_label(field: str, point_labels: dict[int, str]) -> str:
    match = re.search(r"(\d+)$", field)
    if not match:
        alignment_labels = {
            "AMB": "Acople motor-bomba", "ACM": "Acople caja-motor", "ACB": "Acople caja-bomba",
            "ANGULO": "Ángulo", "COMPENSACION": "Compensación", "V": "Vertical", "H": "Horizontal",
        }
        parts = field.split("_")
        return " - ".join(alignment_labels.get(part, part.title()) for part in parts)
    point = int(match.group(1))
    location = point_labels.get(point, f"Ubicación {point}")
    prefix = field[:match.start()]
    measurement = {"H": "Horizontal", "V": "Vertical", "A": "Axial", "T": "Temperatura", "L": "Lubricante aplicado"}.get(prefix, prefix)
    return f"{location} - {measurement}"


def _chart_label(label: str) -> str:
    """Keep dense multi-series legends readable without losing the location."""
    replacements = {
        "Acople motor-bomba": "Motor-bomba",
        "Acople caja-motor": "Caja-motor",
        "Acople caja-bomba": "Caja-bomba",
        "Compensación": "Comp.",
        "CompensaciÃ³n": "Comp.",
        "Ángulo": "Ángulo",
        "Ãngulo": "Ángulo",
        "mm/100 mm": "mm/100mm",
    }
    for source, target in replacements.items():
        label = label.replace(source, target)
    return label


def _trend_text(rows: list[dict[str, Any]], field: str, unit: str = "") -> str:
    values = [_number(medicion(row.get(field))) for row in rows]
    values = [value for value in values if value is not None]
    if len(values) < 2:
        return "Sin comparación anterior"
    delta = values[0] - values[1]
    tolerance = max(abs(values[1]) * 0.005, 0.005)
    if abs(delta) <= tolerance:
        return "Se mantuvo estable"
    direction = "Subió" if delta > 0 else "Bajó"
    return f"{direction} {abs(delta):.2f}{unit} respecto a la medición anterior"


def _trend_chart(
    title: str,
    rows: list[dict[str, Any]],
    series: list[tuple[str, str]],
    unit: str,
    styles,
    show_summary: bool = True,
):
    chronological = list(reversed(rows))
    usable = []
    for field, label in series:
        values = [_number(medicion(row.get(field))) for row in chronological]
        if any(value is not None for value in values):
            usable.append((field, label, values))
    if not usable:
        return None
    legend_rows = (len(usable) + 2) // 3
    drawing_height = 175 + max(0, legend_rows - 2) * 12
    drawing = Drawing(500, drawing_height)
    drawing.add(String(8, drawing_height - 12, title, fontName=FONT_BOLD, fontSize=10, fillColor=NAVY))
    chart = HorizontalLineChart()
    chart.x = 42; chart.y = 28; chart.width = 430; chart.height = 88
    chart.data = [values for _, _, values in usable]
    labels = []
    label_step = max(1, (len(chronological) + 7) // 8)
    for index, row in enumerate(chronological, 1):
        date = _value(row.get("fecha"))
        time_text = _value(row.get("hora"))[:5]
        if re.match(r"\d{4}-\d{2}-\d{2}", date):
            date = f"{date[8:10]}/{date[5:7]}"
        elif re.match(r"\d{2}/\d{2}/\d{4}", date):
            date = date[:5]
        full_label = f"{date} {time_text}".strip() if date else f"Med. {index}"
        labels.append(full_label if index == 1 or index == len(chronological) or (index - 1) % label_step == 0 else "")
    chart.categoryAxis.categoryNames = labels
    chart.categoryAxis.labels.fontName = FONT
    chart.categoryAxis.labels.fontSize = 6.5
    chart.categoryAxis.labels.angle = 20
    chart.categoryAxis.labels.dy = -6
    chart.valueAxis.labels.fontName = FONT
    chart.valueAxis.labels.fontSize = 7
    all_values = [value for _, _, values in usable for value in values if value is not None]
    low, high = min(all_values), max(all_values)
    margin = max((high - low) * 0.15, abs(high) * 0.08, 1.0)
    chart.valueAxis.valueMin = min(0, low - margin)
    chart.valueAxis.valueMax = high + margin
    chart.valueAxis.valueStep = max((chart.valueAxis.valueMax - chart.valueAxis.valueMin) / 4, 0.1)
    chart.joinedLines = 1
    for index, (_, _, _) in enumerate(usable):
        color = CHART_COLORS[index % len(CHART_COLORS)]
        chart.lines[index].strokeColor = color
        chart.lines[index].strokeWidth = 1.8
        chart.lines[index].symbol = makeMarker("FilledCircle")
        chart.lines[index].symbol.fillColor = color
        chart.lines[index].symbol.strokeColor = color
        chart.lines[index].symbol.size = 4
    drawing.add(chart)
    for index, (_, label, _) in enumerate(usable):
        label = _chart_label(label)
        x = 10 + (index % 3) * 155
        y = drawing_height - 27 - (index // 3) * 11
        color = CHART_COLORS[index % len(CHART_COLORS)]
        drawing.add(Rect(x, y, 6, 6, fillColor=color, strokeColor=color))
        drawing.add(String(x + 10, y, label, fontName=FONT, fontSize=6.5, fillColor=TEXT))
    latest_rows = []
    for field, label, _ in usable:
        current = next((medicion(row.get(field)) for row in rows
                        if _number(medicion(row.get(field))) is not None), None)
        if current is not None:
            latest_rows.append([_p(label, styles["small"]), _p(f"{current}{unit}", styles["body"]), _p(_trend_text(rows, field, unit), styles["small"])])
    if not show_summary:
        return [drawing, Spacer(1, 5*mm)]
    trend_table = Table(latest_rows, colWidths=[76*mm, 30*mm, 68*mm])
    trend_table.setStyle(TableStyle([
        ("GRID", (0,0), (-1,-1), 0.35, MID), ("BACKGROUND", (0,0), (0,-1), LIGHT),
        ("VALIGN", (0,0), (-1,-1), "TOP"), ("LEFTPADDING", (0,0), (-1,-1), 5),
        ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]))
    return [KeepTogether([drawing, trend_table, Spacer(1, 5*mm)])]


def _footer(canvas, doc, tag: str, report_label: str):
    canvas.saveState()
    canvas.setStrokeColor(MID); canvas.setLineWidth(0.5)
    canvas.line(18*mm, 13*mm, A4[0]-18*mm, 13*mm)
    canvas.setFont(FONT, 7); canvas.setFillColor(MUTED)
    canvas.drawString(18*mm, 8.5*mm, f"SCV-PTBG | {tag} | {report_label}")
    canvas.drawRightString(A4[0]-18*mm, 8.5*mm, f"Página {doc.page}")
    canvas.restoreState()


def _normalizar_tipos(report_type) -> list:
    """Deja la seleccion como una lista de tipos validos, sin repetidos.

    La tablet deja elegir varios sistemas en la misma hoja, asi que aqui puede
    llegar un solo codigo o una lista. Antes solo se aceptaba un texto y el
    resto de lo marcado se perdia en silencio.
    """
    if isinstance(report_type, (list, tuple, set, frozenset)):
        crudos = list(report_type)
    else:
        crudos = str(report_type or "").split(",")

    tipos = []
    for crudo in crudos:
        codigo = str(crudo or "").strip().lower()
        if not codigo or codigo in tipos:
            continue
        if codigo not in REPORT_LABELS:
            # Se nombra el tipo: "no valido" a secas no le dice al operador
            # cual de los que marco es el que sobra.
            raise RuntimeError(
                f"El reporte '{codigo}' no existe. "
                f"Disponibles: {', '.join(sorted(REPORT_LABELS))}."
            )
        tipos.append(codigo)

    if not tipos:
        raise RuntimeError("No se indico que reporte generar.")
    # Integral ya incluye todo lo demas: mezclarlo duplicaria secciones.
    return ["integral"] if "integral" in tipos else tipos


def build_equipment_report_pdf(db_path: Path, localizacion: int, report_type, output_dir: Path, measurement_count: int = 5) -> Path:
    tipos = _normalizar_tipos(report_type)
    es_integral = tipos == ["integral"]
    # La ficha tecnica se imprime si se pidio sola o junto con otros sistemas.
    con_ficha = es_integral or "technical" in tipos
    data = load_equipment_report_data(db_path, localizacion)
    measurement_count = max(1, min(int(measurement_count or 5), 50))
    equipment, info, histories = data["equipment"], data["info"], data["histories"]
    tag = _value(equipment.get("QR_CODE")) or _value(equipment.get("SCADA")) or f"LOC-{localizacion}"
    safe_tag = re.sub(r"[^A-Za-z0-9_-]+", "-", tag).strip("-") or f"LOC-{localizacion}"
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir = output_dir / safe_tag
    output_dir.mkdir(parents=True, exist_ok=True)
    slug = "-".join(tipos)
    pdf_path = output_dir / f"SCV-PTBG_{safe_tag}_{slug}_{timestamp}.pdf"
    styles = _styles()
    report_label = " + ".join(REPORT_LABELS[t] for t in tipos)
    frame = Frame(18*mm, 17*mm, A4[0]-36*mm, A4[1]-34*mm, id="main")
    doc = BaseDocTemplate(str(pdf_path), pagesize=A4, leftMargin=18*mm, rightMargin=18*mm, topMargin=17*mm, bottomMargin=17*mm, title=f"SCV-PTBG - {report_label} - {tag}", author="SCV-PTBG")
    doc.addPageTemplates([PageTemplate(id="report", frames=[frame], onPage=lambda c, d: _footer(c, d, tag, report_label))])
    story = []
    banner = Table([[
        Paragraph("SCV-PTBG", styles["cover_title"]),
        Paragraph(f"<b>{_safe(report_label)}</b><br/>Generado {_safe(datetime.now().strftime('%d/%m/%Y %H:%M'))}", styles["cover_sub"]),
    ]], colWidths=[72*mm, 102*mm], rowHeights=[36*mm])
    banner.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), NAVY), ("VALIGN", (0,0), (-1,-1), "MIDDLE"), ("LEFTPADDING", (0,0), (-1,-1), 10), ("RIGHTPADDING", (0,0), (-1,-1), 10)]))
    story.extend([banner, Spacer(1, 8*mm), Paragraph(_safe(equipment.get("EQUIPO")) or "Equipo", styles["h1"])])
    identity = _kv_table([
        ("TAG / QR", tag), ("Localización", localizacion), ("Sistema", equipment.get("SISTEMA")),
        ("Subsistema", equipment.get("SUBSISTEMA")), ("SCADA", equipment.get("SCADA")), ("Configuración", equipment.get("PT_EQ") or equipment.get("PUNTOS")),
    ], styles)
    if identity: story.extend([identity, Spacer(1, 6*mm)])
    technical = [(FIELD_LABELS[key], info.get(key)) for key in FIELD_LABELS]
    if con_ficha:
        technical_table = _kv_table(technical, styles)
        if technical_table:
            story.extend([Paragraph("Ficha técnica", styles["h1"]), technical_table, Spacer(1, 5*mm)])
    if es_integral:
        selected = list(SECTIONS) + ["replacements", "coupling_changes"]
    else:
        # Se respeta el orden en que llegaron los tipos: es el orden en que el
        # tecnico los marco en la tablet.
        selected = [t for t in tipos if t != "technical"]
    available_sections = [key for key in selected if histories.get(key)]
    if es_integral and available_sections:
        summary_rows = [[_p("Sistema", styles["center"]), _p("Registros", styles["center"]), _p("Último registro", styles["center"])]]
        for key in available_sections:
            rows = histories[key]
            label = REPORT_LABELS.get(key, key.title())
            last = f"{_value(rows[0].get('fecha'))} {_value(rows[0].get('hora'))}".strip()
            shown = min(measurement_count, len(rows))
            summary_rows.append([_p(label, styles["body"]), _p(f"{shown} últimas de {len(rows)}", styles["body"]), _p(last, styles["body"])])
        summary = Table(summary_rows, colWidths=[80*mm, 32*mm, 62*mm], repeatRows=1)
        summary.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,0), TEAL), ("GRID", (0,0), (-1,-1), 0.35, MID), ("VALIGN", (0,0), (-1,-1), "TOP"), ("LEFTPADDING", (0,0), (-1,-1), 6), ("TOPPADDING", (0,0), (-1,-1), 6), ("BOTTOMPADDING", (0,0), (-1,-1), 6)]))
        story.append(KeepTogether([
            Paragraph("Resumen del historial", styles["h1"]),
            summary,
        ]))
    for key in selected:
        all_rows = histories.get(key) or []
        if not all_rows:
            continue
        rows = all_rows[:measurement_count]
        story.append(PageBreak())
        if key == "replacements":
            heading = f"Últimos {len(rows)} reemplazos"
            explanation = f"Se muestran hasta {measurement_count} eventos de los {len(all_rows)} disponibles."
        elif key == "coupling_changes":
            heading = f"Últimos {len(rows)} cambios de coupling"
            explanation = f"Se muestran hasta {measurement_count} cambios confirmados de los {len(all_rows)} disponibles."
        else:
            measurement_word = "medición" if len(rows) == 1 else "mediciones"
            latest_word = "Última" if len(rows) == 1 else "Últimas"
            heading = f"{latest_word} {len(rows)} {measurement_word} de {REPORT_LABELS.get(key, key.title()).lower()}"
            explanation = f"Se muestran hasta {measurement_count} registros de los {len(all_rows)} disponibles. En las gráficas, el orden va de la medición más antigua a la más reciente."
        story.append(Paragraph(heading, styles["h1"]))
        story.append(Paragraph(explanation, styles["muted"]))
        story.append(Spacer(1, 4*mm))
        if key in SECTIONS:
            fields = SECTIONS[key][2]
            try:
                visual_type = int(equipment.get("PT_EQ") or equipment.get("PUNTOS") or 1)
            except (TypeError, ValueError):
                visual_type = 1
            point_labels = _point_labels_for(visual_type, key)
            if key in {"vibration", "temperature", "lubrication"}:
                active_points = tuple(point_labels)
                fields = tuple(field for field in fields if int(re.search(r"\d+$", field).group()) in active_points)
            unit = " °C" if key == "temperature" else (" emboladas" if key == "lubrication" and visual_type == 5 else (" g" if key == "lubrication" else ""))
            field_labels = {field: _field_label(field, point_labels) for field in fields}
            if key == "alignment" and visual_type == 10:
                fields = tuple(field for field in fields if field.startswith("AMB_"))
            if key == "alignment":
                field_labels = {
                    field: f"{label} ({'mm/100 mm' if '_ANGULO_' in field else 'mm'})"
                    for field, label in field_labels.items()
                }

            iso_profile = _iso_profile(info) if key == "vibration" else None
            if iso_profile:
                story.extend(_iso_reference_table(iso_profile, styles))
            story.append(Paragraph("Tabla comparativa", styles["h2"]))
            story.append(Paragraph(
                "Medición 1 es la lectura más reciente. Cada columna conserva su fecha y hora.",
                styles["muted"],
            ))
            story.append(Spacer(1, 2*mm))
            story.append(_comparative_table(
                rows, fields, field_labels, unit, styles, iso_profile,
            ))

            story.append(PageBreak())
            graph_heading = "Gráfica del historial completo"
            story.append(Paragraph(graph_heading, styles["h1"]))
            story.append(Paragraph(
                f"La evolución incluye las {len(all_rows)} mediciones disponibles, desde la más antigua hasta la más reciente."
                + (" Cada punto del equipo tiene su propia gráfica con sus tres ejes."
                   if key == "vibration" else ""),
                styles["muted"],
            ))
            story.append(Spacer(1, 4*mm))

            if key == "vibration":
                # Una grafica POR PUNTO, cada una con sus tres ejes. La version
                # anterior metia todas las lecturas en una sola grafica: hasta
                # 18 lineas cruzadas donde no se podia seguir el comportamiento
                # de ningun punto en el tiempo.
                axis_names = {"H": "Horizontal", "V": "Vertical", "A": "Axial"}
                for point, location in point_labels.items():
                    series = [
                        (f"{axis}{point}", axis_names[axis])
                        for axis in ("H", "V", "A")
                        if f"{axis}{point}" in fields
                    ]
                    # Solo la ubicacion fisica: el numero de punto es cosa
                    # interna de las columnas H/V/A y al mecanico no le dice
                    # nada.
                    chart_block = _trend_chart(
                        location,
                        all_rows,
                        series,
                        " mm/s",
                        styles,
                        show_summary=False,
                    )
                    if chart_block:
                        story.append(KeepTogether(chart_block))
            elif key in {"temperature", "lubrication"}:
                prefix = "T" if key == "temperature" else "L"
                series = [(f"{prefix}{point}", location) for point, location in point_labels.items()]
                chart_title = "Historial completo de temperatura" if key == "temperature" else "Historial completo de lubricante aplicado"
                chart_block = _trend_chart(
                    chart_title, all_rows, series, unit, styles,
                    show_summary=False,
                )
                if chart_block: story.extend(chart_block)
            elif key == "alignment":
                chart_block = _trend_chart(
                    "Evolución completa de la alineación",
                    all_rows,
                    [(field, field_labels[field]) for field in fields],
                    "",
                    styles,
                    show_summary=False,
                )
                if chart_block:
                    story.extend(chart_block)
            story.append(Paragraph(
                "La tendencia describe el cambio observado entre mediciones; por sí sola no determina la condición del equipo.",
                styles["muted"],
            ))
            story.append(Spacer(1, 4*mm))
        elif key == "coupling_changes":
            coupling_fields = (
                "marca", "modelo", "serial",
            )
            coupling_labels = {
                "marca": "Marca", "modelo": "Modelo", "serial": "Serial",
            }
            story.append(Paragraph("Tabla comparativa", styles["h2"]))
            story.append(Paragraph(
                "Cambio 1 es el registro confirmado más reciente.",
                styles["muted"],
            ))
            story.append(Spacer(1, 2*mm))
            story.append(_comparative_table(
                rows, coupling_fields, coupling_labels, "", styles,
                column_label="Cambio",
            ))
        else:
            replacement_fields = ("equipo", "marca", "modelo", "serial", "voltaje", "corriente", "rpm", "sf", "hp", "frame", "brgs_drive", "brgs_opp", "ciclo", "arranque", "ph", "tension", "lubricacion")
            replacement_labels = {
                field: RECORD_LABELS.get(field, field.replace("_", " ").title())
                for field in replacement_fields
            }
            story.append(Paragraph("Tabla comparativa", styles["h2"]))
            story.append(Paragraph(
                "Evento 1 es el reemplazo más reciente. Cada columna conserva su fecha y hora.",
                styles["muted"],
            ))
            story.append(Spacer(1, 2*mm))
            story.append(_comparative_table(
                rows, replacement_fields, replacement_labels, "", styles,
                column_label="Evento",
            ))
    # Lo que se pidio y no tiene ni una fila. Se nombra siempre, aunque otros
    # sistemas si hayan salido: si el tecnico marca tres y solo aparece uno,
    # sin este aviso no sabe si el equipo no tiene registros o si el reporte
    # se genero mal.
    vacios = [key for key in selected if not histories.get(key)]
    if vacios:
        pedidos = ", ".join(REPORT_LABELS[t] for t in vacios)
        story.extend([
            Spacer(1, 8*mm),
            Paragraph(
                f"No hay registros de {_safe(pedidos)} para este equipo.",
                styles["muted"],
            ),
        ])
    doc.build(story)
    return pdf_path
