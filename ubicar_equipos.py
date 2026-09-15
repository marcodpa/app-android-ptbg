# -*- coding: utf-8 -*-
"""
ubicar_equipos.py — Colocar los equipos sobre el plano haciendo clic.
=====================================================================

Abre el plano de la planta, va pidiendo los equipos uno por uno y guarda en
`mapa_planta.py` el punto donde se hizo clic. Es la alternativa comoda a
escribir 55 pares de coordenadas a mano; escribe en el mismo archivo, asi que
las dos formas se pueden mezclar sin problema.

    python ubicar_equipos.py
    python ubicar_equipos.py ruta\\del\\plano.jpg     (si esta en otro sitio)

COMO SE USA
-----------
    Clic izquierdo ........ coloca el equipo resaltado y pasa al siguiente
    Arrastrar un punto .... corrige de sitio uno ya colocado
    Rueda ................. acercar y alejar (hace zoom donde esta el cursor)
    Arrastrar con derecho . mover el plano
    Clic en la lista ...... saltar a cualquier equipo, colocado o no
    Ctrl+Z ................ deshacer el ultimo
    Supr .................. quitar el punto del equipo resaltado
    Ctrl+S ................ guardar
    0 ..................... ver el plano completo

Se puede cerrar a medias y seguir otro dia: al abrir de nuevo se salta lo que
ya esta colocado y arranca en el primero que falte. Al cerrar avisa si queda
algo sin guardar.
"""
from __future__ import annotations

import re
import sys
import time
import tkinter as tk
from pathlib import Path
from tkinter import font as tkfont
from tkinter import messagebox

try:
    from PIL import Image, ImageTk
except ImportError:  # pragma: no cover
    print("Falta Pillow. Instale con:  pip install pillow")
    sys.exit(1)

BASE = Path(__file__).parent
ARCHIVO_MAPA = BASE / "mapa_planta.py"

# Sitios donde buscar el plano si no lo pasan por la linea de comandos.
CANDIDATOS_PLANO = [
    BASE / "assets" / "images" / "plano_planta.jpg",
    BASE / "assets" / "images" / "plano_planta.png",
    BASE / "plano_planta.jpg",
    BASE / "plano_planta.png",
]

# Colores. El plano es un CAD sobre fondo oscuro, asi que la ventana lo
# acompaña: un panel blanco al lado encandila y obliga a reajustar la vista
# cada vez que se mira de la lista al mapa.
FONDO = "#12161c"
PANEL = "#1b212a"
BORDE = "#2c3542"
TEXTO = "#e6edf5"
TENUE = "#8b98a8"
ACENTO = "#f5a623"     # el equipo que toca colocar ahora
PUESTO = "#3ddc84"     # ya colocado
SISTEMA = "#5aa9e6"    # encabezados de sistema en la lista

# Los marcadores son deliberadamente chicos: el punto tiene que caer sobre el
# equipo exacto, y una bola grande tapa justo lo que hay que mirar para
# acertar. Van en pixeles de pantalla, asi que al acercarse no crecen y la
# punteria mejora con el zoom.
RADIO = 4              # radio del marcador, en pixeles de pantalla
DECIMALES = 4          # precision con que se guardan las coordenadas
AGARRE = 10            # pixeles para agarrar un marcador ya colocado;
                       # algo mayor que el punto, que se dibuja chico
REBOTE = 0.4           # segundos: por debajo de esto, un clic repetido en el
                       # mismo punto se descarta por completo


# ── Lectura y escritura de mapa_planta.py ───────────────────────────────────
#
# Se edita el archivo linea por linea en vez de reescribirlo entero: asi
# sobreviven los comentarios, el orden por sistema y cualquier cosa que se
# haya tocado a mano.

LINEA_EQUIPO = re.compile(
    r"^(?P<sangria>\s*)(?P<loc>\d+):\s*\((?P<punto>[^)]*)\),(?P<cola>.*)$"
)
LINEA_BLACK_START = re.compile(r"^BLACK_START\s*=\s*\([^)]*\)\s*$")

BLACK_START_LOC = -1   # clave interna; no es una LOCALIZACION real


def leer_puntos(texto: str) -> dict:
    puntos = {}
    for linea in texto.splitlines():
        encontrado = LINEA_EQUIPO.match(linea)
        if not encontrado:
            continue
        crudo = encontrado.group("punto").strip()
        if crudo.lower().startswith("none"):
            continue
        try:
            x, y = (float(parte) for parte in crudo.split(","))
        except ValueError:
            continue
        puntos[int(encontrado.group("loc"))] = (x, y)
    encontrado = re.search(r"BLACK_START\s*=\s*\(([^)]*)\)", texto)
    if encontrado and "none" not in encontrado.group(1).lower():
        try:
            x, y = (float(p) for p in encontrado.group(1).split(","))
            puntos[BLACK_START_LOC] = (x, y)
        except ValueError:
            pass
    return puntos


def _formato(punto) -> str:
    if punto is None:
        return "(None, None)"
    return f"({punto[0]:.{DECIMALES}f}, {punto[1]:.{DECIMALES}f})"


def escribir_puntos(texto: str, puntos: dict) -> str:
    salida = []
    for linea in texto.splitlines():
        encontrado = LINEA_EQUIPO.match(linea)
        if encontrado:
            loc = int(encontrado.group("loc"))
            nuevo = _formato(puntos.get(loc))
            # La sangria se reconstruye desde cero en vez de reutilizar la
            # capturada: esa ya incluye el relleno que alinea los numeros, y
            # volver a aplicarlo corria la linea dos espacios en cada
            # guardado. Python leia igual el diccionario, pero el archivo se
            # deformaba mas cada vez que se guardaba.
            comentario = encontrado.group("cola").strip()
            linea = f"    {loc:>3}: {nuevo},".ljust(30)
            if comentario:
                linea += "  " + comentario
            salida.append(linea.rstrip())
            continue
        if LINEA_BLACK_START.match(linea):
            salida.append(
                f"BLACK_START = {_formato(puntos.get(BLACK_START_LOC))}"
            )
            continue
        salida.append(linea)
    return "\n".join(salida) + "\n"


def _unidad(sistema: str) -> str:
    """BG-1 o BG-2 si el sistema es una turbina; vacio en los demas.

    Hace falta porque los equipos de las dos turbinas se llaman igual
    —BOOSTER, VENT TURB A, FIN FAN B— y en una lista suelta no hay manera de
    saber cual es cual. Lo que de verdad los separa es el TAG (11- es la BG-1
    y 12- la BG-2), pero para leer de un vistazo sirve mejor la unidad.
    """
    encontrado = re.search(r"BG-\d", sistema or "")
    return encontrado.group(0) if encontrado else ""


def leer_catalogo(texto: str) -> list:
    """Los equipos en el orden del archivo, con su sistema y su nombre.

    El nombre sale del comentario de cada linea porque es donde esta escrito;
    no hay que abrir la base de datos para usar esta herramienta.
    """
    catalogo = []
    sistema = "SIN SISTEMA"
    dentro = False
    for linea in texto.splitlines():
        if linea.startswith("EQUIPOS = {"):
            dentro = True
            continue
        if dentro and linea.startswith("}"):
            break
        if not dentro:
            continue
        titulo = re.match(r"\s*#\s*──\s*(.+?)\s*─+\s*$", linea)
        if titulo:
            sistema = titulo.group(1)
            continue
        encontrado = LINEA_EQUIPO.match(linea)
        if not encontrado:
            continue
        comentario = encontrado.group("cola")
        partes = [
            t.strip() for t in comentario.split("#", 1)[-1].split("·")
        ]
        nombre = partes[0] if partes else ""
        tag = partes[1] if len(partes) > 1 else ""
        subsistema = partes[2] if len(partes) > 2 else ""
        catalogo.append({
            "loc": int(encontrado.group("loc")),
            "nombre": nombre or f"LOC-{encontrado.group('loc')}",
            "tag": tag,
            "subsistema": subsistema,
            "sistema": sistema,
            "unidad": _unidad(sistema),
        })
    catalogo.append({
        "loc": BLACK_START_LOC,
        "nombre": "BLACK START",
        "tag": "GEN. DIESEL",
        "subsistema": "ARRANQUE EN NEGRO",
        "sistema": "BLACK START",
        "unidad": "",
    })
    return catalogo


# ── La ventana ──────────────────────────────────────────────────────────────

class Ubicador:
    def __init__(self, raiz, plano: Path):
        self.raiz = raiz
        self.texto_archivo = ARCHIVO_MAPA.read_text(encoding="utf-8")
        self.catalogo = leer_catalogo(self.texto_archivo)
        self.puntos = leer_puntos(self.texto_archivo)
        self.historial = []
        self.sucio = False

        self.imagen = Image.open(plano).convert("RGB")
        self.ancho_img, self.alto_img = self.imagen.size

        # Vista: escala en pixeles de pantalla por pixel de imagen, y la
        # esquina de la imagen que queda arriba a la izquierda del lienzo.
        self.escala = 1.0
        self.ox = 0.0
        self.oy = 0.0
        self.foto = None
        self._arrastre = None
        self._moviendo = None     # marcador agarrado con el boton izquierdo
        self._ultimo = None       # ultimo punto colocado, para filtrar rebotes
        self._ignorar = False

        self.indice = self._primero_sin_colocar()
        self._construir()
        self.raiz.after(60, self._encajar)

    # ── Armado de la ventana ────────────────────────────────────────────
    def _construir(self):
        self.raiz.title("Ubicar equipos en el plano — SCV-PTBG")
        self.raiz.configure(bg=FONDO)
        self.raiz.geometry("1500x900")

        lateral = tk.Frame(self.raiz, bg=PANEL, width=340)
        lateral.pack(side="left", fill="y")
        lateral.pack_propagate(False)

        self.titulo = tk.Label(
            lateral, text="", bg=PANEL, fg=ACENTO, justify="left",
            anchor="w", font=("Segoe UI", 15, "bold"), wraplength=300,
        )
        self.titulo.pack(fill="x", padx=16, pady=(16, 0))

        self.subtitulo = tk.Label(
            lateral, text="", bg=PANEL, fg=TENUE, justify="left",
            anchor="w", font=("Segoe UI", 10), wraplength=300,
        )
        self.subtitulo.pack(fill="x", padx=16, pady=(2, 12))

        self.progreso = tk.Label(
            lateral, text="", bg=PANEL, fg=TEXTO, anchor="w",
            font=("Segoe UI", 10, "bold"),
        )
        self.progreso.pack(fill="x", padx=16, pady=(0, 10))

        contenedor = tk.Frame(lateral, bg=PANEL)
        contenedor.pack(fill="both", expand=True, padx=(16, 6))
        barra = tk.Scrollbar(contenedor)
        barra.pack(side="right", fill="y")
        self.lista = tk.Listbox(
            contenedor, bg=PANEL, fg=TEXTO, bd=0, highlightthickness=0,
            selectbackground=BORDE, selectforeground=TEXTO,
            activestyle="none", font=("Consolas", 9),
            yscrollcommand=barra.set,
        )
        self.lista.pack(side="left", fill="both", expand=True)
        barra.config(command=self.lista.yview)
        self.lista.bind("<<ListboxSelect>>", self._elegir_de_lista)

        ayuda = (
            "clic ............. colocar\n"
            "arrastrar punto .. corregir de sitio\n"
            "rueda ............ zoom\n"
            "derecho .......... mover el plano\n"
            "Ctrl+Z ........... deshacer\n"
            "Supr ............. quitar el punto\n"
            "0 ................ ver todo\n"
            "Ctrl+S ........... guardar"
        )
        tk.Label(
            lateral, text=ayuda, bg=PANEL, fg=TENUE, justify="left",
            anchor="w", font=("Consolas", 9),
        ).pack(fill="x", padx=16, pady=(10, 6))

        tk.Button(
            lateral, text="Guardar en mapa_planta.py", command=self.guardar,
            bg=PUESTO, fg="#0d1117", bd=0, font=("Segoe UI", 10, "bold"),
            activebackground=PUESTO, cursor="hand2", pady=8,
        ).pack(fill="x", padx=16, pady=(0, 16))

        self.lienzo = tk.Canvas(
            self.raiz, bg=FONDO, highlightthickness=0, cursor="crosshair",
        )
        self.lienzo.pack(side="right", fill="both", expand=True)

        self.lienzo.bind("<Configure>", lambda e: self._pintar())
        self.lienzo.bind("<ButtonPress-1>", self._apretar)
        self.lienzo.bind("<B1-Motion>", self._mover_marcador)
        self.lienzo.bind("<ButtonRelease-1>", self._soltar)
        self.lienzo.bind("<Button-3>", self._empezar_arrastre)
        self.lienzo.bind("<B3-Motion>", self._arrastrar)
        self.lienzo.bind(
            "<ButtonRelease-3>", lambda e: setattr(self, "_arrastre", None)
        )
        self.lienzo.bind("<MouseWheel>", self._zoom)
        self.lienzo.bind("<Motion>", self._mover_cursor)

        self.raiz.bind("<Control-z>", lambda e: self.deshacer())
        self.raiz.bind("<Control-s>", lambda e: self.guardar())
        self.raiz.bind("<Delete>", lambda e: self.quitar())
        self.raiz.bind("<Key-0>", lambda e: self._encajar())
        self.raiz.bind("<Right>", lambda e: self._ir(self.indice + 1))
        self.raiz.bind("<Left>", lambda e: self._ir(self.indice - 1))
        self.raiz.protocol("WM_DELETE_WINDOW", self._cerrar)

        self.fuente_marca = tkfont.Font(
            family="Segoe UI", size=8, weight="bold"
        )
        self._refrescar_lista()

    # ── Estado ──────────────────────────────────────────────────────────
    def _primero_sin_colocar(self) -> int:
        for i, equipo in enumerate(self.catalogo):
            if equipo["loc"] not in self.puntos:
                return i
        return 0

    @property
    def actual(self):
        return self.catalogo[self.indice]

    def _ir(self, indice):
        self.indice = max(0, min(indice, len(self.catalogo) - 1))
        self._refrescar_lista()
        self._pintar()

    def _elegir_de_lista(self, _evento):
        seleccion = self.lista.curselection()
        if not seleccion:
            return
        equipo = self._equipo_de.get(seleccion[0])
        if equipo is None:      # es un encabezado de sistema, no un equipo
            self.lista.selection_clear(0, "end")
            self.lista.selection_set(self._fila_de[self.indice])
            return
        self._ir(equipo)

    def _refrescar_lista(self):
        """Redibuja la lista con un encabezado por sistema.

        Los encabezados son filas de la misma lista, asi que hay que traducir
        entre fila y equipo con `_equipo_de` y `_fila_de`. Van agrupados
        porque sueltos, "BOOSTER" aparece dos veces igual y no se sabe cual
        toca; el encabezado dice si es el de la BG-1 o el de la BG-2.
        """
        self.lista.delete(0, "end")
        self._equipo_de = {}
        self._fila_de = {}
        sistema = None
        for i, equipo in enumerate(self.catalogo):
            if equipo["sistema"] != sistema:
                sistema = equipo["sistema"]
                cabecera = self.lista.size()
                self.lista.insert("end", f" {sistema}")
                self.lista.itemconfig(cabecera, foreground=SISTEMA)
            fila = self.lista.size()
            marca = "+" if equipo["loc"] in self.puntos else "\u00b7"
            self.lista.insert("end", f"   {marca} {equipo['nombre'][:24]}")
            color = PUESTO if equipo["loc"] in self.puntos else TENUE
            if i == self.indice:
                color = ACENTO
            self.lista.itemconfig(fila, foreground=color)
            self._equipo_de[fila] = i
            self._fila_de[i] = fila

        fila = self._fila_de[self.indice]
        self.lista.selection_clear(0, "end")
        self.lista.selection_set(fila)
        self.lista.see(fila)

        equipo = self.actual
        titulo = equipo["nombre"]
        if equipo["unidad"]:
            titulo = f"{titulo}   {equipo['unidad']}"
        self.titulo.config(text=titulo)
        detalle = equipo["tag"] or ""
        if equipo["loc"] >= 0:
            detalle = f"LOC-{equipo['loc']}   \u00b7   {detalle}"
        self.subtitulo.config(
            text="\n".join(
                [detalle, equipo["sistema"], equipo["subsistema"]]
            )
        )
        colocados = sum(1 for e in self.catalogo if e["loc"] in self.puntos)
        pendiente = "  ·  sin guardar" if self.sucio else ""
        self.progreso.config(
            text=f"{colocados} de {len(self.catalogo)} colocados{pendiente}"
        )

    # ── Vista ───────────────────────────────────────────────────────────
    def _encajar(self):
        ancho = max(self.lienzo.winfo_width(), 1)
        alto = max(self.lienzo.winfo_height(), 1)
        self.escala = min(ancho / self.ancho_img, alto / self.alto_img)
        self.ox = (self.ancho_img - ancho / self.escala) / 2
        self.oy = (self.alto_img - alto / self.escala) / 2
        self._pintar()

    def _a_pantalla(self, x, y):
        return ((x - self.ox) * self.escala, (y - self.oy) * self.escala)

    def _a_imagen(self, cx, cy):
        return (self.ox + cx / self.escala, self.oy + cy / self.escala)

    def _pintar(self):
        ancho = max(self.lienzo.winfo_width(), 1)
        alto = max(self.lienzo.winfo_height(), 1)
        self.lienzo.delete("all")

        # Se recorta lo visible y se escala solo eso. Redimensionar el plano
        # entero a 6x seria medio giga de mapa de bits para mostrar un rincon.
        x0, y0 = self.ox, self.oy
        x1 = x0 + ancho / self.escala
        y1 = y0 + alto / self.escala
        rx0, ry0 = max(0, int(x0)), max(0, int(y0))
        rx1 = min(self.ancho_img, int(x1) + 1)
        ry1 = min(self.alto_img, int(y1) + 1)
        if rx1 > rx0 and ry1 > ry0:
            recorte = self.imagen.crop((rx0, ry0, rx1, ry1))
            destino = (
                max(1, int((rx1 - rx0) * self.escala)),
                max(1, int((ry1 - ry0) * self.escala)),
            )
            metodo = Image.LANCZOS if self.escala < 1 else Image.NEAREST
            self.foto = ImageTk.PhotoImage(recorte.resize(destino, metodo))
            px, py = self._a_pantalla(rx0, ry0)
            self.lienzo.create_image(px, py, image=self.foto, anchor="nw")

        # Los rotulos ya escritos, para que los siguientes no se les encimen.
        # Donde los equipos estan pegados —los tres compresores, las seis
        # centrifugadoras— se montaban unos sobre otros y no se leia ninguno,
        # justo donde mas falta hace distinguirlos. El que no entra se calla;
        # el marcador igual se ve y la lista dice cual es.
        rotulos = []

        def cabe(x, y, ancho):
            caja = (x, y - 7, x + ancho, y + 7)
            for otra in rotulos:
                if (caja[0] < otra[2] and caja[2] > otra[0]
                        and caja[1] < otra[3] and caja[3] > otra[1]):
                    return False
            rotulos.append(caja)
            return True

        def etiqueta_de(equipo):
            texto = equipo["nombre"]
            return f"{texto} {equipo['unidad']}" if equipo["unidad"] else texto

        # El marcador activo se dibuja de ultimo, para quedar por encima de
        # los demas. Pero su rotulo se reserva antes que ninguno: es el equipo
        # que se esta colocando y su nombre no puede ser el que se calle.
        activo_punto = self.puntos.get(self.actual["loc"])
        if activo_punto is not None:
            ax, ay = self._a_pantalla(
                activo_punto[0] * self.ancho_img,
                activo_punto[1] * self.alto_img,
            )
            cabe(ax + 17, ay, self.fuente_marca.measure(
                etiqueta_de(self.actual)))

        orden = sorted(range(len(self.catalogo)),
                       key=lambda i: i == self.indice)
        for i in orden:
            equipo = self.catalogo[i]
            punto = self.puntos.get(equipo["loc"])
            if punto is None:
                continue
            cx, cy = self._a_pantalla(
                punto[0] * self.ancho_img, punto[1] * self.alto_img
            )
            if not (-40 <= cx <= ancho + 40 and -40 <= cy <= alto + 40):
                continue
            activo = i == self.indice
            color = ACENTO if activo else PUESTO
            radio = RADIO + 1 if activo else RADIO
            self.lienzo.create_oval(
                cx - radio, cy - radio, cx + radio, cy + radio,
                fill=color, outline="#0d1117", width=1,
            )
            if activo:
                # Al que se esta colocando se le cruzan dos rayas finas para
                # ver el centro exacto sin que el marcador lo tape.
                for x0, y0, x1, y1 in (
                    (cx - 14, cy, cx - radio - 2, cy),
                    (cx + radio + 2, cy, cx + 14, cy),
                    (cx, cy - 14, cx, cy - radio - 2),
                    (cx, cy + radio + 2, cx, cy + 14),
                ):
                    self.lienzo.create_line(x0, y0, x1, y1, fill=color)
            if activo or self.escala > 1.2:
                etiqueta = etiqueta_de(equipo)
                # El activo ya reservo su sitio arriba; se dibuja sin preguntar.
                if activo or cabe(cx + 17, cy,
                                  self.fuente_marca.measure(etiqueta)):
                    self.lienzo.create_text(
                        cx + 17, cy, text=etiqueta, anchor="w",
                        fill=color, font=self.fuente_marca,
                    )

        self.lienzo.create_text(
            12, alto - 12, anchor="sw", fill=TENUE, font=("Consolas", 9),
            text=f"zoom {self.escala:.2f}x   ·   "
                 f"{self.actual['nombre']} {self.actual['unidad']}",
        )

    def _mover_cursor(self, evento):
        x, y = self._a_imagen(evento.x, evento.y)
        self.raiz.title(
            f"Ubicar equipos — ({x / self.ancho_img:.3f}, "
            f"{y / self.alto_img:.3f})"
        )

    def _zoom(self, evento):
        anterior = self.escala
        factor = 1.15 if evento.delta > 0 else 1 / 1.15
        self.escala = max(0.05, min(12.0, self.escala * factor))
        # El punto bajo el cursor se queda donde esta: el zoom sigue al raton
        # y no al centro, que es lo que uno espera al acercarse a una bomba.
        ix = self.ox + evento.x / anterior
        iy = self.oy + evento.y / anterior
        self.ox = ix - evento.x / self.escala
        self.oy = iy - evento.y / self.escala
        self._pintar()

    def _empezar_arrastre(self, evento):
        self._arrastre = (evento.x, evento.y, self.ox, self.oy)

    def _arrastrar(self, evento):
        if not self._arrastre:
            return
        x0, y0, ox, oy = self._arrastre
        self.ox = ox - (evento.x - x0) / self.escala
        self.oy = oy - (evento.y - y0) / self.escala
        self._pintar()

    # ── Colocar ─────────────────────────────────────────────────────────
    def _marcador_en(self, cx, cy):
        """Indice del marcador bajo el cursor, o None.

        Se recorre al reves para que, si dos quedaron encimados, se agarre el
        que se dibuja por encima.
        """
        for i in range(len(self.catalogo) - 1, -1, -1):
            punto = self.puntos.get(self.catalogo[i]["loc"])
            if punto is None:
                continue
            mx, my = self._a_pantalla(
                punto[0] * self.ancho_img, punto[1] * self.alto_img
            )
            if (mx - cx) ** 2 + (my - cy) ** 2 <= AGARRE ** 2:
                return i
        return None

    def _apretar(self, evento):
        # Un segundo apreton en el mismo punto y en un suspiro no es una
        # accion nueva: es un doble clic o el rebote del contacto del raton.
        # Se descarta el gesto completo.
        #
        # Descartar solo la colocacion no alcanzaba, y fallaba de la peor
        # manera: el clic repetido caia encima del marcador recien puesto, lo
        # agarraba y devolvia la seleccion a ese equipo. El siguiente clic —ya
        # intencional— no colocaba el equipo que tocaba, sino que mudaba el
        # anterior a otro sitio, sin aviso.
        if self._ultimo is not None:
            t, ux, uy = self._ultimo
            if (time.monotonic() - t < REBOTE
                    and (evento.x - ux) ** 2 + (evento.y - uy) ** 2 < 14 ** 2):
                self._ignorar = True
                return
        self._ignorar = False

        golpe = self._marcador_en(evento.x, evento.y)
        if golpe is not None:
            # Agarrar uno ya colocado para corregirlo de sitio, en vez de
            # tener que borrarlo y volver a ponerlo.
            self.indice = golpe
            loc = self.catalogo[golpe]["loc"]
            self._moviendo = (golpe, self.puntos[loc])
            self.lienzo.config(cursor="fleur")
            self._refrescar_lista()
            self._pintar()

    def _mover_marcador(self, evento):
        if self._ignorar or self._moviendo is None:
            return
        i, _ = self._moviendo
        x, y = self._a_imagen(evento.x, evento.y)
        x = min(max(x, 0), self.ancho_img)
        y = min(max(y, 0), self.alto_img)
        self.puntos[self.catalogo[i]["loc"]] = (
            round(x / self.ancho_img, DECIMALES),
            round(y / self.alto_img, DECIMALES),
        )
        self._pintar()

    def _soltar(self, evento):
        if self._ignorar:
            self._ignorar = False
            return
        if self._moviendo is not None:
            i, anterior = self._moviendo
            self._moviendo = None
            self.lienzo.config(cursor="crosshair")
            # El deshacer guarda donde estaba antes de agarrarlo, no cada
            # pixel del recorrido: un Ctrl+Z lo devuelve de una vez.
            self.historial.append((self.catalogo[i]["loc"], anterior))
            self.sucio = True
            self._refrescar_lista()
            self._pintar()
            return
        self._colocar(evento)

    def _colocar(self, evento):
        x, y = self._a_imagen(evento.x, evento.y)
        if not (0 <= x <= self.ancho_img and 0 <= y <= self.alto_img):
            return
        self._ultimo = (time.monotonic(), evento.x, evento.y)
        loc = self.actual["loc"]
        self.historial.append((loc, self.puntos.get(loc)))
        # Se redondea aqui, a los mismos decimales con que se escribe el
        # archivo, para que lo que esta en memoria y lo guardado sean el mismo
        # numero. Si no, guardar y volver a abrir corre cada marcador una
        # fraccion de pixel y el archivo aparece modificado sin haber tocado
        # nada. Cuatro decimales son 0,2 px en un plano de 2000 de ancho.
        self.puntos[loc] = (
            round(x / self.ancho_img, DECIMALES),
            round(y / self.alto_img, DECIMALES),
        )
        self.sucio = True
        siguiente = self._siguiente_sin_colocar()
        if siguiente is not None:
            self.indice = siguiente
        self._refrescar_lista()
        self._pintar()

    def _siguiente_sin_colocar(self):
        for salto in range(1, len(self.catalogo) + 1):
            i = (self.indice + salto) % len(self.catalogo)
            if self.catalogo[i]["loc"] not in self.puntos:
                return i
        return None

    def quitar(self):
        loc = self.actual["loc"]
        if loc in self.puntos:
            self.historial.append((loc, self.puntos[loc]))
            del self.puntos[loc]
            self.sucio = True
            self._refrescar_lista()
            self._pintar()

    def deshacer(self):
        if not self.historial:
            return
        loc, anterior = self.historial.pop()
        if anterior is None:
            self.puntos.pop(loc, None)
        else:
            self.puntos[loc] = anterior
        self.sucio = True
        for i, equipo in enumerate(self.catalogo):
            if equipo["loc"] == loc:
                self.indice = i
                break
        self._refrescar_lista()
        self._pintar()

    def guardar(self):
        self.texto_archivo = escribir_puntos(self.texto_archivo, self.puntos)
        ARCHIVO_MAPA.write_text(self.texto_archivo, encoding="utf-8")
        self.sucio = False
        self._refrescar_lista()
        faltan = [e for e in self.catalogo if e["loc"] not in self.puntos]
        resumen = f"Guardado en {ARCHIVO_MAPA.name}."
        if faltan:
            resumen += f"\n\nQuedan {len(faltan)} sin colocar."
        messagebox.showinfo("Guardado", resumen)

    def _cerrar(self):
        if self.sucio:
            respuesta = messagebox.askyesnocancel(
                "Sin guardar",
                "Hay cambios sin guardar. ¿Guardar antes de cerrar?",
            )
            if respuesta is None:
                return
            if respuesta:
                self.texto_archivo = escribir_puntos(
                    self.texto_archivo, self.puntos
                )
                ARCHIVO_MAPA.write_text(self.texto_archivo, encoding="utf-8")
        self.raiz.destroy()


def buscar_plano():
    if len(sys.argv) > 1:
        ruta = Path(sys.argv[1])
        return ruta if ruta.exists() else None
    for ruta in CANDIDATOS_PLANO:
        if ruta.exists():
            return ruta
    return None


def main():
    plano = buscar_plano()
    if plano is None:
        print("No encontre el plano de la planta.\n")
        print("Guardelo como:")
        print(f"    {CANDIDATOS_PLANO[0]}")
        print("\no pase la ruta directamente:")
        print("    python ubicar_equipos.py C:\\ruta\\al\\plano.jpg")
        return 1
    if not ARCHIVO_MAPA.exists():
        print(f"Falta {ARCHIVO_MAPA}")
        return 1
    raiz = tk.Tk()
    Ubicador(raiz, plano)
    raiz.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
