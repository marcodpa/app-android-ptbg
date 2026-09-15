from pathlib import Path

import fitz
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Image,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from build_visual_report import SCREENS


ROOT = Path(__file__).resolve().parent
CAPTURES = ROOT / "capturas_app"
OUTPUT_DIR = ROOT.parent / "output" / "pdf"
OUTPUT = OUTPUT_DIR / "Informe_visual_STER_2026-08-04.pdf"
RENDER_DIR = ROOT.parent / "tmp" / "pdfs" / "informe_visual_ster"

NAVY = colors.HexColor("#0A1C3E")
BLUE = colors.HexColor("#1F4D78")
TEAL = colors.HexColor("#009B82")
MUTED = colors.HexColor("#576579")
LIGHT = colors.HexColor("#E8EEF5")
PALE = colors.HexColor("#F4F6F9")
RED = colors.HexColor("#9B1C1C")
GOLD = colors.HexColor("#7A5A00")


def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#D7E3F1"))
    canvas.setLineWidth(0.5)
    canvas.line(0.72 * inch, letter[1] - 0.48 * inch, letter[0] - 0.72 * inch, letter[1] - 0.48 * inch)
    canvas.setFont("Helvetica-Bold", 8.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(0.72 * inch, letter[1] - 0.38 * inch, "STER | Sistema de Trazabilidad de Equipos Rotativos")
    canvas.setFont("Helvetica", 8.5)
    canvas.drawRightString(letter[0] - 0.72 * inch, 0.4 * inch, f"Pagina {doc.page}")
    canvas.restoreState()


def scaled_image(path: Path, max_width=3.55 * inch, max_height=5.55 * inch):
    pix = fitz.Pixmap(str(path))
    width, height = pix.width, pix.height
    scale = min(max_width / width, max_height / height)
    return Image(str(path), width=width * scale, height=height * scale)


def build():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="ReportTitle", parent=styles["Title"], fontName="Helvetica-Bold",
        fontSize=30, leading=34, textColor=NAVY, alignment=TA_CENTER,
        spaceAfter=8,
    ))
    styles.add(ParagraphStyle(
        name="ReportSubtitle", parent=styles["Normal"], fontName="Helvetica-Bold",
        fontSize=16, leading=20, textColor=BLUE, alignment=TA_CENTER,
        spaceAfter=16,
    ))
    styles.add(ParagraphStyle(
        name="Kicker", parent=styles["Normal"], fontName="Helvetica-Bold",
        fontSize=10, leading=13, textColor=TEAL, alignment=TA_CENTER,
        spaceAfter=16,
    ))
    styles.add(ParagraphStyle(
        name="H1x", parent=styles["Heading1"], fontName="Helvetica-Bold",
        fontSize=16, leading=20, textColor=BLUE, spaceBefore=4, spaceAfter=9,
    ))
    styles.add(ParagraphStyle(
        name="Bodyx", parent=styles["BodyText"], fontName="Helvetica",
        fontSize=10.5, leading=14, textColor=colors.HexColor("#232B37"),
        spaceAfter=7,
    ))
    styles.add(ParagraphStyle(
        name="Captionx", parent=styles["Normal"], fontName="Helvetica-Bold",
        fontSize=8.5, leading=11, textColor=MUTED, alignment=TA_CENTER,
        spaceAfter=8,
    ))
    styles.add(ParagraphStyle(
        name="Bulletx", parent=styles["BodyText"], fontName="Helvetica",
        fontSize=10.5, leading=14, leftIndent=18, firstLineIndent=-9,
        bulletIndent=5, textColor=colors.HexColor("#232B37"), spaceAfter=5,
    ))

    doc = SimpleDocTemplate(
        str(OUTPUT), pagesize=letter,
        leftMargin=0.78 * inch, rightMargin=0.78 * inch,
        topMargin=0.65 * inch, bottomMargin=0.62 * inch,
        title="Informe visual STER",
        author="Equipo STER",
    )
    story = []

    story.extend([
        Spacer(1, 1.05 * inch),
        Paragraph("INFORME DE REVISION VISUAL Y FUNCIONAL", styles["Kicker"]),
        Paragraph("STER", styles["ReportTitle"]),
        Paragraph("Sistema de Trazabilidad de Equipos Rotativos", styles["ReportSubtitle"]),
        Spacer(1, 0.25 * inch),
        Paragraph("Levantamiento completo de pantallas en tablet<br/>4 de agosto de 2026", styles["Captionx"]),
        Spacer(1, 0.9 * inch),
        Paragraph("17 capturas verificadas | modos noche y dia | flujo USB", styles["Kicker"]),
        PageBreak(),
        Paragraph("Resumen ejecutivo", styles["ReportTitle"]),
        Paragraph(
            "Se realizo un recorrido visual completo de la aplicacion Android STER instalada en la tablet conectada. "
            "El levantamiento cubrio navegacion principal, equipos, QR, seis servicios, sincronizacion USB, historial, "
            "generacion de reportes, impresion y ajustes.", styles["Bodyx"]),
        Paragraph(
            "Para acceder a todas las configuraciones se utilizo una copia local de demostracion con tres equipos. "
            "Al terminar, la base original de la tablet fue restaurada. No se enviaron datos de demostracion a MariaDB.",
            styles["Bodyx"]),
        Paragraph("Cobertura", styles["H1x"]),
    ])
    for text in (
        "Inicio en modo noche y modo dia.",
        "Modulo Equipos y seleccion multiple de servicios.",
        "Vibracion, Temperatura, Lubricacion, Alineacion, Reemplazo y Cambio de coupling.",
        "Escaneo QR e ingreso manual.",
        "Sincronizacion exclusiva por USB y eliminacion de pendientes.",
        "Historial, reporte PDF, impresion de formatos y Ajustes.",
    ):
        story.append(Paragraph(f"• {text}", styles["Bulletx"]))
    story.append(Paragraph("Hallazgos prioritarios", styles["H1x"]))
    for text in (
        "Critico: Reporte PDF e Imprimir usan texto negro sobre fondo azul oscuro en modo dia.",
        "Alto: el titulo Alineacion Motor-Caja usa azul oscuro sobre fondo oscuro.",
        "Medio: Modelo, Serial y Marca tienen contraste insuficiente sobre las tarjetas blancas.",
        "Medio: el resumen del inicio puede indicar cero equipos aunque existan activos locales.",
    ):
        story.append(Paragraph(f"• {text}", styles["Bulletx"]))

    story.append(Spacer(1, 8))
    data = [["Modulo", "Funcion", "Estado"],
            ["Inicio", "Panel, indicadores, USB y rutas", "Revisado"],
            ["Equipos", "Activos, filtros, reportes y servicios", "Revisado"],
            ["Servicios", "Seis flujos operativos", "Revisado"],
            ["Sincronizacion", "Descarga y subida por USB", "Revisado"],
            ["Reportes", "Historial, PDF e impresion", "Con hallazgo"],
            ["Ajustes", "Sesion, version e ISO 10816", "Revisado"]]
    table = Table(data, colWidths=[1.45 * inch, 3.65 * inch, 1.05 * inch], repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), LIGHT),
        ("TEXTCOLOR", (0, 0), (-1, 0), NAVY),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#B7C5D7")),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(table)

    for number, (relative, title, description, review) in enumerate(SCREENS, start=1):
        story.extend([
            PageBreak(),
            Paragraph(f"{number}. {title}", styles["H1x"]),
            scaled_image(CAPTURES / relative),
            Paragraph(f"Figura {number}. {title}", styles["Captionx"]),
            Paragraph(f"<b>Funcion.</b> {description}", styles["Bodyx"]),
        ])
        review_style = styles["Bodyx"]
        if "Hallazgo critico" in review or "Hallazgo crítico" in review:
            review_style = ParagraphStyle("Critical", parent=styles["Bodyx"], textColor=RED)
        elif "Hallazgo importante" in review:
            review_style = ParagraphStyle("Important", parent=styles["Bodyx"], textColor=GOLD)
        story.append(Paragraph(f"<b>Revision.</b> {review}", review_style))

    story.extend([
        PageBreak(),
        Paragraph("Conclusiones y acciones recomendadas", styles["ReportTitle"]),
        Paragraph(
            "La aplicacion cubre de forma coherente el ciclo operativo: identificar el equipo, seleccionar servicios, "
            "capturar lecturas guiadas, conservarlas offline, sincronizar por USB y consultar o imprimir resultados.",
            styles["Bodyx"]),
        Paragraph("Acciones de interfaz", styles["H1x"]),
    ])
    for text in (
        "Aplicar colores de texto dependientes de la superficie en los paneles de reporte e impresion.",
        "Cambiar Alineacion Motor-Caja a texto primario claro o turquesa.",
        "Oscurecer el texto tecnico mostrado sobre tarjetas blancas.",
        "Unificar la recarga del contador del inicio con la lista local de Equipos.",
    ):
        story.append(Paragraph(f"• {text}", styles["Bulletx"]))
    story.extend([
        Paragraph("Resultado", styles["H1x"]),
        Paragraph(
            "Las 17 capturas originales quedan organizadas por modulo. Este documento registra el estado observado "
            "en la tablet y sirve como referencia para la siguiente ronda de correcciones y pruebas de regresion.",
            styles["Bodyx"]),
    ])

    doc.build(story, onFirstPage=header_footer, onLaterPages=header_footer)

    pdf = fitz.open(OUTPUT)
    for old in RENDER_DIR.glob("page-*.png"):
        old.unlink()
    for index, page in enumerate(pdf):
        pix = page.get_pixmap(matrix=fitz.Matrix(1.35, 1.35), alpha=False)
        pix.save(RENDER_DIR / f"page-{index + 1:02d}.png")
    print(f"PDF: {OUTPUT}")
    print(f"Pages: {len(pdf)}")
    print(f"Render: {RENDER_DIR}")


if __name__ == "__main__":
    build()
