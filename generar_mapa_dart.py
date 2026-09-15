# -*- coding: utf-8 -*-
"""Pasa mapa_planta.py a lib/models/mapa_planta.dart.

Las coordenadas se colocan y se corrigen en `mapa_planta.py`, que es el unico
sitio donde se editan. Este script las lleva a Dart para que la app las use.
Si algun dia se mueve un equipo de sitio, se recoloca alli y se vuelve a
correr esto:

    python generar_mapa_dart.py

Se genera en vez de leerse el .py desde la app porque Flutter no ejecuta
Python, y en vez de copiarse a mano porque a mano se copia mal.
"""
import importlib.util
import io
import re
from pathlib import Path

BASE = Path(__file__).parent
ORIGEN = BASE / "mapa_planta.py"
DESTINO = BASE / "lib" / "models" / "mapa_planta.dart"

spec = importlib.util.spec_from_file_location("mapa_planta", ORIGEN)
mapa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mapa)

problemas = mapa.validar()
if problemas:
    print("El mapa tiene problemas:")
    for p in problemas:
        print("   ", p)
    raise SystemExit(1)

# Nombre y TAG de cada equipo, de los comentarios del propio archivo, para
# poder comentar el Dart igual y que se lea sin abrir la base.
texto = io.open(ORIGEN, encoding="utf-8").read()
detalle = {}
for m in re.finditer(r"^\s*(\d+): \([^)]*\),\s*#\s*(.+)$", texto, re.M):
    partes = [t.strip() for t in m.group(2).split("·")]
    detalle[int(m.group(1))] = (partes + ["", ""])[:2]

sistema_de = {}
sistema = ""
for linea in texto.splitlines():
    t = re.match(r"\s*#\s*──\s*(.+?)\s*─+\s*$", linea)
    if t:
        sistema = t.group(1)
        continue
    m = re.match(r"\s*(\d+): \(", linea)
    if m:
        sistema_de[int(m.group(1))] = sistema

colocados = {loc: p for loc, p in mapa.EQUIPOS.items() if p[0] is not None}

lineas = [
    "// GENERADO por generar_mapa_dart.py — no editar a mano.",
    "//",
    "// Las posiciones se colocan en mapa_planta.py con ubicar_equipos.html",
    "// (o ubicar_equipos.py) y desde alli se regeneran. Editar aqui se pierde",
    "// en la siguiente regeneracion.",
    "",
    "/// Un punto sobre el plano, en fracciones de 0 a 1 del ancho y del alto.",
    "///",
    "/// Se guardan como fraccion y no en pixeles a proposito: si el plano se",
    "/// reexporta con otro tamano, los marcadores siguen cayendo en el mismo",
    "/// sitio de la planta sin tener que recolocar nada.",
    "class PuntoMapa {",
    "  const PuntoMapa(this.x, this.y);",
    "",
    "  final double x;",
    "  final double y;",
    "}",
    "",
    "/// Un area del plano, para rotularla cuando se ve la planta completa.",
    "class ZonaMapa {",
    "  const ZonaMapa(this.nombre, this.x0, this.y0, this.x1, this.y1);",
    "",
    "  final String nombre;",
    "  final double x0;",
    "  final double y0;",
    "  final double x1;",
    "  final double y1;",
    "",
    "  double get centroX => (x0 + x1) / 2;",
    "  double get centroY => (y0 + y1) / 2;",
    "}",
    "",
    f"const planoPlanta = 'assets/images/{mapa.PLANO}';",
    "",
    "/// Proporcion del plano (ancho / alto), para dibujarlo sin deformarlo.",
    "const planoRelacion = __RELACION__;",
    "",
    "/// Donde esta cada equipo, por LOCALIZACION.",
    "///",
    "/// Los que no estan en este mapa no tienen posicion asignada todavia y",
    "/// simplemente no se dibujan; el resto de la app no se entera.",
    "const mapaEquipos = <int, PuntoMapa>{",
]

sistema = None
for loc in sorted(colocados, key=lambda l: (sistema_de.get(l, ""), l)):
    if sistema_de.get(loc) != sistema:
        sistema = sistema_de.get(loc)
        lineas.append(f"  // {sistema}")
    x, y = colocados[loc]
    nombre, tag = detalle.get(loc, ("", ""))
    lineas.append(f"  {loc}: PuntoMapa({x}, {y}),".ljust(34)
                  + f"// {nombre} · {tag}")
lineas.append("};")
lineas.append("")

if mapa.BLACK_START[0] is not None:
    lineas += [
        "/// El black start no tiene LOCALIZACION: es uno solo en la planta y",
        "/// su registro no cuelga de ningun equipo, asi que va aparte.",
        f"const mapaBlackStart = PuntoMapa"
        f"({mapa.BLACK_START[0]}, {mapa.BLACK_START[1]});",
        "",
    ]
else:
    lineas += ["const PuntoMapa? mapaBlackStart = null;", ""]

lineas += [
    "/// Rotulos de area, para ubicarse cuando se ve la planta entera.",
    "const mapaZonas = <ZonaMapa>[",
]
for nombre, (x0, y0, x1, y1) in mapa.ZONAS.items():
    lineas.append(f"  ZonaMapa('{nombre}', {x0}, {y0}, {x1}, {y1}),")
lineas.append("];")

# La relacion del plano se saca de la imagen, no se escribe a mano.
from PIL import Image
ancho, alto = Image.open(BASE / "assets" / "images" / mapa.PLANO).size
salida = "\n".join(lineas).replace("__RELACION__", f"{ancho} / {alto}")

DESTINO.write_text(salida + "\n", encoding="utf-8")
faltan = mapa.sin_ubicar()
print(f"{DESTINO.relative_to(BASE)}: {len(colocados)} equipos"
      + (f", faltan {len(faltan)}: "
         + ", ".join(f'LOC-{n}' for n in faltan) if faltan else ""))
