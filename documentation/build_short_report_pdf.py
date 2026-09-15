from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle, PageBreak
from PIL import Image as PILImage


ROOT = Path(__file__).resolve().parents[1]
CAP = ROOT / "documentation" / "capturas_informe_corto"
SERVICE_CAP = ROOT / "documentation" / "capturas_app" / "04_servicios"
OUT = ROOT / "output" / "pdf" / "Informe_resumido_STER_2026-08-04.pdf"

NAVY = colors.HexColor("#07172F")
PANEL = colors.HexColor("#10233E")
CYAN = colors.HexColor("#28D7E8")
GREEN = colors.HexColor("#31D09A")
TEXT = colors.HexColor("#17243A")
MUTED = colors.HexColor("#52647E")
LIGHT = colors.HexColor("#EEF3F8")
WHITE = colors.white


def register_fonts():
    regular = Path("C:/Windows/Fonts/segoeui.ttf")
    bold = Path("C:/Windows/Fonts/segoeuib.ttf")
    if regular.exists() and bold.exists():
        pdfmetrics.registerFont(TTFont("STER", str(regular)))
        pdfmetrics.registerFont(TTFont("STER-Bold", str(bold)))
        return "STER", "STER-Bold"
    return "Helvetica", "Helvetica-Bold"


FONT, FONT_BOLD = register_fonts()


def shot(name, max_w, max_h):
    path = CAP / name
    with PILImage.open(path) as im:
        w, h = im.size
    scale = min(max_w / w, max_h / h)
    img = Image(str(path), width=w * scale, height=h * scale)
    img.hAlign = "CENTER"
    return img


def service_shot(name, max_w=49 * mm, max_h=82 * mm):
    path = SERVICE_CAP / name
    with PILImage.open(path) as im:
        w, h = im.size
    scale = min(max_w / w, max_h / h)
    img = Image(str(path), width=w * scale, height=h * scale)
    img.hAlign = "CENTER"
    return img


def service_tile(name, label):
    tile = Table(
        [[service_shot(name)], [para(label, 8.5, NAVY, True, align=1)]],
        colWidths=[53 * mm],
    )
    tile.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), WHITE),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#CAD6E3")),
        ("TOPPADDING", (0, 0), (-1, 0), 2 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 1.5 * mm),
        ("TOPPADDING", (0, 1), (-1, 1), 1.5 * mm),
        ("BOTTOMPADDING", (0, 1), (-1, 1), 2 * mm),
    ]))
    return tile


def para(text, size=9.2, color=TEXT, bold=False, leading=None, align=0):
    return Paragraph(
        text,
        ParagraphStyle(
            "p",
            fontName=FONT_BOLD if bold else FONT,
            fontSize=size,
            leading=leading or size * 1.3,
            textColor=color,
            alignment=align,
            spaceAfter=0,
        ),
    )


def card(title, body, image_name, w=82 * mm, h=101 * mm):
    inner = Table(
        [[shot(image_name, w - 8 * mm, h - 31 * mm)], [para(title, 11, NAVY, True)], [para(body, 8.5, MUTED)]],
        colWidths=[w - 6 * mm],
    )
    inner.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), WHITE),
        ("BOX", (0, 0), (-1, -1), 0.7, colors.HexColor("#CAD6E3")),
        ("LEFTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("TOPPADDING", (0, 0), (-1, 0), 3 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 2 * mm),
        ("TOPPADDING", (0, 1), (-1, -1), 2 * mm),
        ("BOTTOMPADDING", (0, -1), (-1, -1), 3 * mm),
    ]))
    return inner


def header(canvas, doc):
    canvas.saveState()
    w, h = A4
    canvas.setFillColor(NAVY)
    canvas.rect(0, h - 18 * mm, w, 18 * mm, fill=1, stroke=0)
    canvas.setFont(FONT_BOLD, 13)
    canvas.setFillColor(WHITE)
    canvas.drawString(16 * mm, h - 11.5 * mm, "STER")
    canvas.setFont(FONT, 8)
    canvas.setFillColor(colors.HexColor("#B9C8D9"))
    canvas.drawRightString(w - 16 * mm, h - 11.5 * mm, "Sistema de Trazabilidad de Equipos Rotativos")
    canvas.setStrokeColor(colors.HexColor("#D7E1EA"))
    canvas.line(16 * mm, 13 * mm, w - 16 * mm, 13 * mm)
    canvas.setFont(FONT, 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(16 * mm, 8 * mm, "Informe resumido de funcionamiento - modo noche")
    canvas.drawRightString(w - 16 * mm, 8 * mm, f"Pagina {doc.page}")
    canvas.restoreState()


def title(text, subtitle=None):
    items = [para(text, 20, NAVY, True), Spacer(1, 2 * mm)]
    if subtitle:
        items += [para(subtitle, 9.5, MUTED), Spacer(1, 5 * mm)]
    return items


def two_cards(left, right):
    t = Table([[left, right]], colWidths=[84 * mm, 84 * mm], hAlign="CENTER")
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 1 * mm), ("RIGHTPADDING", (0, 0), (-1, -1), 1 * mm)]))
    return t


def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUT), pagesize=A4, rightMargin=16 * mm, leftMargin=16 * mm,
        topMargin=24 * mm, bottomMargin=18 * mm,
        title="Informe resumido STER", author="STER",
    )
    story = []

    story += title("STER: operacion clara en campo", "Vista resumida de las areas principales y de los documentos que genera la aplicacion.")
    story.append(shot("01_inicio.png", 170 * mm, 150 * mm))
    story += [Spacer(1, 5 * mm), para("El inicio concentra al usuario, estado USB, accesos principales y ruta de trabajo. La navegacion lateral mantiene disponibles Inicio, Equipos, Sincronizacion, Historial, tema y Configuracion.", 10, TEXT)]
    story.append(PageBreak())

    story += title("Equipos y ruta de trabajo", "La informacion se organiza alrededor de cada equipo rotativo.")
    story.append(two_cards(
        card("Equipos", "Permite buscar, filtrar y abrir la ficha de cada activo para consultar datos, registrar servicios o generar documentos.", "02_equipos.png"),
        card("Servicios", "Al seleccionar un equipo se eligen los trabajos de una misma ODT: vibracion, temperatura, alineacion, lubricacion, coupling, correas o reemplazo.", "05_servicios.png"),
    ))
    story.append(PageBreak())

    story += title("Capturas de cada servicio", "Vista de las pantallas utilizadas por el mecanico durante el registro en campo.")
    services = [
        service_tile("02_vibracion_captura.png", "Vibracion"),
        service_tile("03_temperatura_captura.png", "Temperatura"),
        service_tile("04_lubricacion_captura.png", "Lubricacion"),
        service_tile("05_alineacion_captura.png", "Alineacion"),
        service_tile("06_reemplazo_equipo.png", "Reemplazo de equipo"),
        service_tile("07_cambio_coupling.png", "Cambio de coupling"),
    ]
    grid = Table(
        [services[:3], services[3:]],
        colWidths=[56 * mm, 56 * mm, 56 * mm],
        rowHeights=[96 * mm, 96 * mm],
        hAlign="CENTER",
    )
    grid.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 1.5 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 1.5 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 1 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1 * mm),
    ]))
    story.append(grid)
    story.append(PageBreak())

    story += title("Identificacion y trazabilidad", "Captura rapida en campo y seguimiento centralizado.")
    story.append(two_cards(
        card("Escanear QR", "Identifica el equipo por su codigo y abre directamente su ficha, reduciendo errores de seleccion.", "06_qr.png"),
        card("Historial", "Consulta las ordenes y servicios ya registrados para revisar la evolucion y la trazabilidad del activo.", "08_historial.png"),
    ))
    story.append(PageBreak())

    story += title("Trabajo sin conexion WiFi", "La transferencia de datos se realiza por USB entre la tablet y la laptop.")
    story.append(two_cards(
        card("Sincronizacion USB", "Muestra los registros pendientes, permite revisar la cola y transferir mediciones de forma controlada.", "07_sincronizacion.png"),
        card("Configuracion", "Administra datos del usuario, preferencias, tema visual y parametros necesarios para trabajar en campo.", "09_ajustes.png"),
    ))
    story.append(PageBreak())

    story += title("Reporte PDF", "Documento tecnico de analisis y comparacion.")
    story.append(two_cards(
        card("1. Seleccion", "Desde el equipo se eligen los sistemas y mediciones que formaran el reporte comparativo.", "03_reporte_seleccion.png", 82 * mm, 108 * mm),
        card("2. Resultado", "El PDF presenta datos historicos, tablas comparativas y graficas para interpretar la evolucion del equipo.", "10_salida_reporte_integral.png", 82 * mm, 108 * mm),
    ))
    story += [Spacer(1, 4 * mm), para("El boton Reporte conserva el formato analitico existente y permite revisar tendencias antes de tomar decisiones de mantenimiento.", 9.5, TEXT)]
    story.append(PageBreak())

    story += title("Imprimir formato oficial", "Planilla operativa lista para archivo o impresion.")
    story.append(two_cards(
        card("1. Seleccion", "Se escoge una ODT y uno o varios servicios. Los campos sin informacion se representan con '/' para evitar espacios ambiguos.", "04_imprimir_seleccion.png", 82 * mm, 108 * mm),
        card("2. Resultado", "STER llena el formato correspondiente al tipo de equipo y lo prepara para abrir e imprimir desde la laptop.", "11_salida_formato_impresion.png", 82 * mm, 108 * mm),
    ))
    story += [Spacer(1, 4 * mm), para("Reporte e Imprimir son funciones distintas: Reporte analiza y compara; Imprimir genera la planilla oficial de la orden seleccionada.", 9.5, TEXT, True)]
    story.append(PageBreak())

    story += title("Resumen de servicios", "Cada registro queda asociado al equipo y a una ODT comun.")
    rows = [
        ("Vibracion", "Lecturas por punto, estado inmediato y evolucion historica."),
        ("Temperatura", "Temperaturas por componente con aviso visual durante la captura."),
        ("Alineacion", "Datos de alineacion del conjunto motor-caja-bomba."),
        ("Lubricacion", "Puntos graficos, gramos o emboladas y tipo de grasera manual/electrica."),
        ("Coupling y correas", "Confirmacion de cambio de coupling y registro del ajuste de correas."),
        ("Reemplazo", "Actualiza primero los datos del equipo para que los demas servicios usen la nueva placa."),
    ]
    data = [[para("Servicio", 9, WHITE, True), para("Funcion", 9, WHITE, True)]] + [[para(a, 9, NAVY, True), para(b, 9, TEXT)] for a, b in rows]
    table = Table(data, colWidths=[42 * mm, 128 * mm], rowHeights=[10 * mm] + [19 * mm] * len(rows))
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("BACKGROUND", (0, 1), (-1, -1), LIGHT),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#C7D3DF")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4 * mm),
    ]))
    story += [table, Spacer(1, 7 * mm), para("Resultado: una aplicacion enfocada en el trabajo de campo, con captura guiada, trazabilidad por ODT, sincronizacion USB y salidas documentales profesionales.", 11, NAVY, True)]

    doc.build(story, onFirstPage=header, onLaterPages=header)
    print(OUT)


if __name__ == "__main__":
    build()
