"""Llenado de los formatos oficiales SF-OP-FOR-020 revision 6."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable
import sqlite3

import fitz

from reporte_texto import medicion, observacion


TEMPLATE_BY_POINTS = {
    1: "Motor-Bomba(A).pdf", 2: "Motor-Bomba(A).pdf",
    3: "Motor-Bomba(A).pdf", 4: "Motor-Ventilador(Fin-Fan).pdf",
    5: "Motor-Ventilador(Vent).pdf", 6: "Motor-Caja-Bomba.pdf",
    7: "Motor-Bomba(B).pdf", 8: "Motor-Bomba(B).pdf",
    9: "Motor-Bomba(A).pdf",
}

POINT_MAP = {
    1: [1, 2, 5, 6], 2: [1, 2, 5, 6], 3: [1, 2, 5, 6],
    4: [1, 2, 9, 10], 5: [1, 2, 7, 8], 6: [1, 2, 3, 4, 5, 6],
    7: [1, 2, 5, 6], 8: [1, 2, 5, 6], 9: [1, 2, 5, 6],
}

VIBRATION_CELLS = {
    "Motor-Bomba(A).pdf": [
        [(16, 474.23, 70, 488.62), (70, 474.23, 159, 488.62), (159, 474.23, 270, 488.62)],
        [(270, 474.23, 382, 488.62), (382, 474.23, 511, 488.62), (511, 474.23, 598, 488.62)],
        [(16, 561.25, 70, 575.65), (70, 561.25, 159, 575.65), (159, 561.25, 270, 575.65)],
        [(270, 561.25, 382, 575.65), (382, 561.25, 511, 575.65), (511, 561.25, 598, 575.65)],
    ],
    "Motor-Bomba(B).pdf": [
        [(16, 465.83, 70, 480.23), (70, 465.83, 159, 480.23), (159, 465.83, 270, 480.23)],
        [(270, 465.83, 382, 480.23), (382, 465.83, 511, 480.23), (511, 465.83, 598, 480.23)],
        [(16, 551.42, 70, 565.85), (70, 551.42, 159, 565.85), (159, 551.42, 270, 565.85)],
        [(270, 551.42, 382, 565.85), (382, 551.42, 511, 565.85), (511, 551.42, 598, 565.85)],
    ],
    "Motor-Caja-Bomba.pdf": [
        [(16, 496.62, 70, 511.03), (70, 496.62, 159, 511.03), (159, 496.62, 213, 511.03)],
        [(213, 496.62, 270, 511.03), (270, 496.62, 326, 511.03), (326, 496.62, 382, 511.03)],
        [(382, 496.62, 439, 511.03), (439, 496.62, 511, 511.03), (511, 496.62, 598, 511.03)],
        [(16, 580.05, 70, 594.45), (70, 580.05, 159, 594.45), (159, 580.05, 213, 594.45)],
        [(213, 580.05, 270, 594.45), (270, 580.05, 326, 594.45), (326, 580.05, 382, 594.45)],
        [(382, 580.05, 439, 594.45), (439, 580.05, 511, 594.45), (511, 580.05, 598, 594.45)],
    ],
    "Motor-Ventilador(Fin-Fan).pdf": [
        [(16, 495.23, 159, 509.62), (159, 495.23, 270, 509.62)],
        [(270, 495.23, 439, 509.62), (439, 495.23, 598, 509.62)],
        [(16, 578.05, 213, 592.45), (213, 578.05, 382, 592.45), (382, 578.05, 598, 592.45)],
    ],
    "Motor-Ventilador(Vent).pdf": [
        [(16, 495.23, 159, 509.62), (159, 495.23, 270, 509.62)],
        [(270, 495.23, 439, 509.62), (439, 495.23, 598, 509.62)],
        [(16, 578.05, 159, 592.45), (159, 578.05, 270, 592.45)],
        [(270, 578.05, 439, 592.45), (439, 578.05, 598, 592.45)],
    ],
}

TEMP_LAYOUT = {
    # (x punto, x temperatura, x lubricacion, x final, y inicial, filas, alto)
    "Motor-Bomba(A).pdf": (400, 438, 510, 598, 327.37, 4, 14.41),
    "Motor-Bomba(B).pdf": (270, 320, 438, 598, 317.98, 4, 14.40),
    "Motor-Caja-Bomba.pdf": (400, 438, 510, 598, 339.37, 6, 14.41),
    "Motor-Ventilador(Fin-Fan).pdf": (270, 320, 438, 598, 310.78, 4, 14.40),
    "Motor-Ventilador(Vent).pdf": (270, 320, 438, 598, 310.78, 4, 14.40),
}

EQUIPMENT_ROWS = {
    "Motor-Bomba(A).pdf": (["MOTOR", "BOMBA"], 159, 14),
    "Motor-Bomba(B).pdf": (["MOTOR", "BOMBA"], 159, 14),
    "Motor-Caja-Bomba.pdf": (["MOTOR", "CAJA", "BOMBA"], 157, 14),
    "Motor-Ventilador(Fin-Fan).pdf": (["MOTOR", "VENT."], 159, 14),
    "Motor-Ventilador(Vent).pdf": (["MOTOR", "VENT."], 159, 14),
}


def _text(value: Any) -> str:
    if value is None or str(value).strip() == "":
        return "/"
    return str(value).strip()


def _number(value: Any) -> str:
    return medicion(value, vacio="/")


def _center(page: fitz.Page, rect: tuple[float, float, float, float], value: Any, size: float = 7.5) -> None:
    box = fitz.Rect(*rect)
    text = _text(value)
    font = size
    while fitz.get_text_length(text, fontname="helv", fontsize=font) > box.width - 4 and font > 4.5:
        font -= .3
    width = fitz.get_text_length(text, fontname="helv", fontsize=font)
    x = box.x0 + max(2, (box.width - width) / 2)
    y = box.y0 + (box.height + font * .72) / 2
    page.insert_text((x, y), text, fontsize=font, fontname="helv", color=(0, 0, 0), overlay=True)


def _left(page: fitz.Page, rect: tuple[float, float, float, float], value: Any, size: float = 7.5) -> None:
    page.insert_textbox(fitz.Rect(*rect), _text(value), fontsize=size, fontname="helv", align=0, color=(0, 0, 0), overlay=True)


def _enabled(selected: set[str], service: str) -> bool:
    return "all" in selected or service in selected


def fill_official_form(
    template_path: Path,
    output_path: Path,
    data: dict[str, Any],
    selected_services: Iterable[str],
) -> Path:
    selected = set(selected_services)
    template_name = template_path.name
    points = int(data.get("points") or 1)
    doc = fitz.open(str(template_path))
    page = doc[0]

    # Los valores del encabezado ocupan el area libre posterior a cada rotulo.
    # Se centran tanto horizontal como verticalmente dentro de su celda.
    _center(page, (48, 83, 316, 102), data.get("date"), 8)
    _center(page, (352, 83, 598, 102), data.get("tag"), 8)
    _center(page, (58, 102, 316, 122), data.get("system"), 8)
    _center(page, (380, 102, 598, 122), data.get("subsystem"), 8)

    names, current_y, row_h = EQUIPMENT_ROWS[template_name]
    current = data.get("current", {})
    replacement = data.get("replacement", {}) if _enabled(selected, "replacement") else {}
    replacement_y = 237 if template_name == "Motor-Caja-Bomba.pdf" else 221
    for idx, name in enumerate(names):
        current_row = current.get(name, {})
        replace_row = replacement.get(name, {})
        y = current_y + idx * row_h
        ry = replacement_y + idx * row_h
        for rect, key in [((70, y, 270, y + row_h), "brand"), ((270, y, 438, y + row_h), "model"), ((438, y, 598, y + row_h), "serial")]:
            _center(page, rect, current_row.get(key))
        for rect, key in [((70, ry, 270, ry + row_h), "brand"), ((270, ry, 438, ry + row_h), "model"), ((438, ry, 598, ry + row_h), "serial")]:
            _center(page, rect, replace_row.get(key))

    point_x, temp_x, lub_x, right_x, temp_top, count, height = TEMP_LAYOUT[template_name]
    source_points = POINT_MAP.get(points, list(range(1, count + 1)))
    temperatures = data.get("temperature", {}) if _enabled(selected, "temperature") else {}
    lubrications = data.get("lubrication", {}) if _enabled(selected, "lubrication") else {}
    for row in range(count):
        point = source_points[row] if row < len(source_points) else row + 1
        y = temp_top + row * height
        # Los numeros de punto ya forman parte del formato oficial.
        _center(page, (temp_x, y, lub_x, y + height), _number(temperatures.get(f"T{point}")))
        _center(page, (lub_x, y, right_x, y + height), _number(lubrications.get(f"L{point}")))

    vibration = data.get("vibration", {}) if _enabled(selected, "vibration") else {}
    axes_by_template = {
        "Motor-Ventilador(Fin-Fan).pdf": [["H", "V"], ["H", "V"], ["H", "V", "A"]],
        "Motor-Ventilador(Vent).pdf": [["H", "V"], ["H", "V"], ["H", "V"], ["H", "V"]],
    }
    axes = axes_by_template.get(template_name, [["H", "V", "A"] for _ in VIBRATION_CELLS[template_name]])
    for row, cells in enumerate(VIBRATION_CELLS[template_name]):
        point = source_points[row] if row < len(source_points) else row + 1
        for axis, rect in zip(axes[row], cells):
            _center(page, rect, _number(vibration.get(f"{axis}{point}")), 8.5)

    alignment = data.get("alignment", {}) if _enabled(selected, "alignment") else {}
    if template_name == "Motor-Bomba(A).pdf":
        for rect, key in [((270, 312.98, 326, 327.37), "AMB_ANGULO_V"), ((326, 312.98, 384, 327.37), "AMB_ANGULO_H"), ((270, 327.37, 326, 341.78), "AMB_COMPENSACION_V"), ((326, 327.37, 384, 341.78), "AMB_COMPENSACION_H")]:
            _center(page, rect, _number(alignment.get(key)))
    elif template_name == "Motor-Caja-Bomba.pdf":
        for prefix, top in (("ACM", 324.98), ("ACB", 397.0)):
            for rect, suffix in [((270, top, 326, top + 14.4), "ANGULO_V"), ((326, top, 384, top + 14.4), "ANGULO_H"), ((270, top + 14.4, 326, top + 28.8), "COMPENSACION_V"), ((326, top + 14.4, 384, top + 28.8), "COMPENSACION_H")]:
                _center(page, rect, _number(alignment.get(f"{prefix}_{suffix}")))

    if template_name in {"Motor-Bomba(A).pdf", "Motor-Caja-Bomba.pdf"}:
        coupling = data.get("coupling") if _enabled(selected, "coupling") else None
        y = 584 if template_name == "Motor-Bomba(A).pdf" else 597
        _center(page, (148, y, 196, y + 13), "X" if coupling is True else "/")
        _center(page, (226, y, 274, y + 13), "X" if coupling is False else "/")
    if "Ventilador" in template_name:
        belt = data.get("belt") if _enabled(selected, "belt") else None
        # Las lineas son para escritura; la marca debe quedar sobre ellas, no atravesada.
        _center(page, (118, 405, 165, 418), "X" if belt is True else "/")
        _center(page, (194, 405, 241, 418), "X" if belt is False else "/")
        _center(page, (278, 405, 334, 418), _number(data.get("belt_tension")) if belt is not None else "/")

    observation_rect = {
        "Motor-Bomba(A).pdf": (18, 616, 596, 673), "Motor-Bomba(B).pdf": (18, 583, 596, 660),
        "Motor-Caja-Bomba.pdf": (18, 628, 596, 681), "Motor-Ventilador(Fin-Fan).pdf": (18, 605, 596, 666),
        "Motor-Ventilador(Vent).pdf": (18, 605, 596, 666),
    }[template_name]
    _left(page, (observation_rect[0] + 4, observation_rect[1] + 12, observation_rect[2] - 4, observation_rect[3] - 3), observacion(data.get("observations")), 7)
    signature_y = 688 if template_name == "Motor-Bomba(B).pdf" else 699
    _left(page, (62, signature_y, 300, signature_y + 19), data.get("responsible"), 7.5)
    _left(page, (55, signature_y + 26, 300, signature_y + 45), data.get("role"), 7.5)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(output_path), garbage=4, deflate=True)
    doc.close()
    return output_path


def sample_data(points: int) -> dict[str, Any]:
    values = POINT_MAP[points]
    return {
        "points": points, "date": "03/08/2026 14:35", "tag": f"EQ-{points:02d}-PTBG",
        "system": "SERVICIOS AUXILIARES", "subsystem": "AREA DE PRUEBA",
        "current": {
            "MOTOR": {"brand": "SIEMENS", "model": "1LE1503", "serial": "MTR-2026-001"},
            "BOMBA": {"brand": "GOULDS", "model": "3196", "serial": "BMB-2026-014"},
            "CAJA": {"brand": "FLENDER", "model": "H3SH", "serial": "CJ-2026-008"},
            "VENT.": {"brand": "HOWDEN", "model": "AXIAL-48", "serial": "VNT-2026-004"},
        },
        "replacement": {
            "MOTOR": {"brand": "WEG", "model": "W22", "serial": "MTR-NVO-101"},
            "BOMBA": {"brand": "KSB", "model": "ETA", "serial": "BMB-NVA-202"},
            "CAJA": {"brand": "SEW", "model": "X3K", "serial": "CJ-NVA-303"},
            "VENT.": {"brand": "TWIN CITY", "model": "BCS", "serial": "VNT-NVO-404"},
        },
        "temperature": {f"T{p}": 52 + i * 4.5 for i, p in enumerate(values)},
        "lubrication": {f"L{p}": 22 + i * 6 for i, p in enumerate(values)},
        "vibration": {f"{axis}{p}": round(2.1 + i * .55 + j * .18, 2) for i, p in enumerate(values) for j, axis in enumerate("HVA")},
        "alignment": {
            "AMB_ANGULO_V": .04, "AMB_ANGULO_H": .03, "AMB_COMPENSACION_V": .06, "AMB_COMPENSACION_H": .05,
            "ACM_ANGULO_V": .03, "ACM_ANGULO_H": .04, "ACM_COMPENSACION_V": .05, "ACM_COMPENSACION_H": .06,
            "ACB_ANGULO_V": .04, "ACB_ANGULO_H": .05, "ACB_COMPENSACION_V": .07, "ACB_COMPENSACION_H": .06,
        },
        "coupling": True, "belt": True, "belt_tension": "42 N",
        "observations": "Equipo inspeccionado. Valores registrados dentro de la orden de trabajo de demostracion.",
        "responsible": "TECNICO DEMOSTRACION", "role": "MECANICO ROTATIVO",
    }


def _row(conn: sqlite3.Connection, table: str, localizacion: int, odt: int | None = None):
    try:
        where, args = "localizacion = ?", [localizacion]
        if odt is not None:
            where += " AND odt = ?"
            args.append(odt)
        return conn.execute(
            f"SELECT * FROM {table} WHERE {where} ORDER BY created_at DESC LIMIT 1", args
        ).fetchone()
    except sqlite3.Error:
        return None


def _texto_tension(valor) -> str:
    """Preserva la precision y representa la lectura cero como no tomada."""
    return _number(valor)


def build_official_report_from_db(
    db_path: Path, localizacion: int, report_types: Iterable[str], output_dir: Path,
    template_dir: Path, odt: int | None = None,
    current_components: dict[str, dict[str, Any]] | None = None,
    uninstalled_components: dict[str, dict[str, Any]] | None = None,
) -> Path:
    """Construye el formato Rev. 6 usando una sola ODT o las ultimas lecturas."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        eq = conn.execute("SELECT * FROM EQUIPOS WHERE LOCALIZACION=?", (localizacion,)).fetchone()
        if eq is None:
            raise RuntimeError("No se encontro el equipo solicitado en la tablet.")
        points = int(eq["PT_EQ"] or eq["PUNTOS"] or 1)
        if points == 10:
            raise RuntimeError('Formulario oficial del separador tipo 10 pendiente de incorporar. Los registros permanecen guardados.')
        info = conn.execute("SELECT * FROM EQUIPO_INFO WHERE localizacion=?", (localizacion,)).fetchone()
        tables = {
            "vibration": "MEDICIONES_LOCAL", "temperature": "TEMPERATURAS_LOCAL",
            "alignment": "ALINEACIONES_LOCAL", "lubrication": "LUBRICACIONES_LOCAL",
            "replacement": "REEMPLAZOS_LOCAL", "coupling": "CAMBIOS_COUPLING_LOCAL",
            "belt": "AJUSTES_CORREA_LOCAL",
        }
        rows = {k: _row(conn, v, localizacion, odt) for k, v in tables.items()}
        aliases = {
            "replacements": "replacement",
            "coupling_changes": "coupling",
            "belt_adjustment": "belt",
        }
        selected = {aliases.get(str(item), str(item)) for item in report_types}
        if "integral" in selected or "all" in selected:
            selected = set(tables)
        def values(row, prefixes):
            if row is None: return {}
            return {k: row[k] for k in row.keys() if any(k.upper().startswith(p) for p in prefixes)}
        source = next((r for r in rows.values() if r is not None), None)
        current = {"MOTOR": {
            "brand": info["marca"] if info else (source["marca"] if source and "marca" in source.keys() else None),
            "model": info["modelo"] if info else (source["modelo"] if source and "modelo" in source.keys() else None),
            "serial": info["serial"] if info else (source["serial"] if source and "serial" in source.keys() else None),
        }}
        if current_components:
            for component, component_data in current_components.items():
                current[component] = dict(component_data)
        repl = {}
        try:
            repl_rows = conn.execute(
                "SELECT * FROM REEMPLAZOS_LOCAL WHERE localizacion=? " + ("AND odt=? " if odt is not None else "") + "ORDER BY created_at DESC",
                (localizacion, odt) if odt is not None else (localizacion,),
            ).fetchall()
            labels = {1: "MOTOR", 2: "BOMBA", 3: "CAJA", 4: "VENT."}
            for r in repl_rows:
                label = labels.get(int(r["equipo"] or 0))
                if label and label not in repl:
                    repl[label] = {"brand": r["marca"], "model": r["modelo"], "serial": r["serial"]}
        except sqlite3.Error:
            pass
        # En el formato oficial, arriba van los componentes que quedaron
        # instalados y abajo los retirados. REEMPLAZOS_LOCAL contiene la placa
        # nueva capturada; cuando existe historial remoto usamos expresamente
        # la placa anterior para la tabla de desinstalados.
        if uninstalled_components:
            repl = {
                component: dict(component_data)
                for component, component_data in uninstalled_components.items()
            }
        observations = [str(r["observaciones"]).strip() for k, r in rows.items()
                        if k in selected and r is not None and "observaciones" in r.keys() and r["observaciones"]]
        data = {
            "points": points,
            "date": ((source["fecha"] or "") + " " + (source["hora"] or "")).strip() if source else "/",
            "tag": eq["QR_CODE"] or eq["EQUIPO"], "system": eq["SISTEMA"], "subsystem": eq["SUBSISTEMA"],
            "current": current, "replacement": repl,
            "temperature": values(rows["temperature"], ["T"]),
            "lubrication": values(rows["lubrication"], ["L"]),
            "vibration": values(rows["vibration"], ["H", "V", "A"]),
            "alignment": values(rows["alignment"], ["AMB_", "ACM_", "ACB_"]),
            "coupling": True if rows["coupling"] is not None else None,
            # La casilla del ajuste de correa ya existia en el formato y
            # salia siempre vacia: no habia donde llenarla en la tablet.
            "belt": (
                None if rows["belt"] is None
                else bool(int(rows["belt"]["ajustada"] or 0))
            ),
            "belt_tension": (
                None if rows["belt"] is None
                else _texto_tension(rows["belt"]["tension"])
            ),
            "observations": " | ".join(observations) or "/",
            "responsible": source["responsable"] if source and "responsable" in source.keys() else "/",
            "role": source["cargo"] if source and "cargo" in source.keys() else "/",
        }
        template_name = TEMPLATE_BY_POINTS.get(points, "Motor-Bomba(A).pdf")
        suffix = f"ODT-{odt}" if odt is not None else "ULTIMO"
        output = output_dir / f"{eq['EQUIPO'] or 'EQUIPO'}-{localizacion}-{suffix}.pdf"
        return fill_official_form(template_dir / template_name, output, data, selected)
    finally:
        conn.close()
