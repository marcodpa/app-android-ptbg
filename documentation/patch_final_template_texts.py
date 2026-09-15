import difflib
import unicodedata
from pathlib import Path

import fitz
from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
OLD_XLSX = ROOT / "tmp" / "xlsx" / "formatos_rev6"
NEW_XLSX = ROOT / "tmp" / "xlsx" / "formatos_rev6_final"
BASE_PDF = ROOT / "documentation" / "backup_formatos_pdf_antes_final_2026-08-04"
OUTPUT = ROOT / "formatos_pdf_nuevos"


def normalized(value):
    value = unicodedata.normalize("NFKD", str(value))
    return "".join(ch for ch in value if not unicodedata.combining(ch)).casefold().strip()


def replacements_for(file_name):
    old_sheet = load_workbook(OLD_XLSX / file_name, data_only=True).active
    new_sheet = load_workbook(NEW_XLSX / file_name, data_only=True).active
    replacements = {}
    for row in range(1, max(old_sheet.max_row, new_sheet.max_row) + 1):
        for col in range(1, max(old_sheet.max_column, new_sheet.max_column) + 1):
            before = old_sheet.cell(row, col).value
            after = new_sheet.cell(row, col).value
            if not isinstance(before, str) or not isinstance(after, str):
                continue
            if before == after:
                continue
            score = difflib.SequenceMatcher(None, normalized(before), normalized(after)).ratio()
            if score >= 0.72:
                replacements[before] = after
    replacements.update({
        "NIVELACION": "NIVELACIÓN",
        "ALINEACION": "ALINEACIÓN",
        "LUBRICACION": "LUBRICACIÓN",
        "VIBRACION": "VIBRACIÓN",
    })
    return sorted(replacements.items(), key=lambda pair: len(pair[0]), reverse=True)


def font_info(page, rect):
    best = None
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                span_rect = fitz.Rect(span["bbox"])
                overlap = span_rect & rect
                if overlap.is_empty:
                    continue
                area = overlap.get_area()
                if best is None or area > best[0]:
                    best = (area, float(span["size"]), int(span["flags"]))
    if best is None:
        return 7.0, "helv"
    bold = bool(best[2] & 16)
    return best[1], "hebo" if bold else "helv"


def insert_fitted(page, rect, text, size, font):
    pdf_font = fitz.Font(fontname=font)
    chosen = max(4.2, size)
    available = max(2.0, rect.width)
    measured = pdf_font.text_length(text, fontsize=chosen)
    if measured > available:
        chosen = max(4.2, chosen * available / measured * 0.98)
    baseline = rect.y0 + min(rect.height - 0.4, chosen * 0.92)
    page.insert_text(
        (rect.x0, baseline),
        text,
        fontsize=chosen,
        fontname=font,
        color=(0, 0, 0),
        overlay=True,
    )


def patch_one(xlsx_name):
    pdf_name = Path(xlsx_name).with_suffix(".pdf").name
    document = fitz.open(BASE_PDF / pdf_name)
    page = document[0]
    pending = []
    replaced = []
    for before, after in replacements_for(xlsx_name):
        # Los encabezados largos ocupan varias líneas en el PDF. Se conservan
        # para no alterar su composición; el resto de las etiquetas sí cambia.
        is_equipment_heading = before.startswith(
            "DATOS DE EQUIPOS ROTATIVOS A REEMPLAZAR"
        )
        if ((len(before) > 48 and not is_equipment_heading)
                or "\n" in before or "\n" in after):
            continue
        hits = page.search_for(before)
        for rect in hits:
            size, font = font_info(page, rect)
            # No expandir el rectángulo ni pintarlo: así se conserva el color
            # original de la celda y no se borran los bordes cercanos.
            text_rect = fitz.Rect(rect)
            page.add_redact_annot(text_rect, fill=False)
            pending.append((text_rect, after, size, font))
            replaced.append((before, after))
    # Eliminar sólo glifos; conservar imágenes y gráficos vectoriales (líneas,
    # rellenos y marcos del formato oficial).
    page.apply_redactions(images=0, graphics=0, text=0)
    for rect, after, size, font in pending:
        insert_fitted(page, rect, after, size, font)
    target = OUTPUT / pdf_name
    document.save(target, garbage=4, deflate=True)
    document.close()
    print(f"{pdf_name}: {len(replaced)} textos actualizados")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for xlsx in sorted(NEW_XLSX.glob("*.xlsx")):
        patch_one(xlsx.name)


if __name__ == "__main__":
    main()
