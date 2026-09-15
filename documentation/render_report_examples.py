from pathlib import Path

import fitz


root = Path(__file__).resolve().parent.parent
out = root / "documentation" / "capturas_informe_corto"
examples = [
    (
        root / "output" / "pdf" / "SCV-PTBG_ejemplo_ODT_integral.pdf",
        "10_salida_reporte_integral.png",
        0,
    ),
    (
        root / "output" / "pdf" / "formatos_rev6_ejemplos" / "Motor-Caja-Bomba-FULL.pdf",
        "11_salida_formato_impresion.png",
        0,
    ),
]

for source, filename, page_number in examples:
    document = fitz.open(source)
    page = document[page_number]
    pixmap = page.get_pixmap(matrix=fitz.Matrix(1.7, 1.7), alpha=False)
    pixmap.save(out / filename)
    print(source, len(document), out / filename)
