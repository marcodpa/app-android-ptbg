"""Prepara el catalogo offline del APK leyendo MariaDB, sin modificar la planta.

Usa las mismas credenciales locales del uploader seguro. Si no hay clave en el
entorno, la solicita en su ventana local; nunca la escribe en el catalogo.
"""

import argparse
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent
CATALOGO = ROOT / "lib" / "data" / "mock_data.dart"
SQL_CATALOGO = """
    SELECT e.ID, e.CODE_SYS, e.EQUIPO, e.LOCALIZACION,
           e.CODE_QR, e.PUNTOS, e.TAGNAME,
           e.NAME_SYS_2 AS subsistema, e.FAMILIA_COMPAT,
           s.SISTEMA AS sistema
    FROM MOT_EQUIPO e
    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
    ORDER BY e.LOCALIZACION
"""


def entero(value, campo, minimo=0):
    try:
        numero = Decimal(str(value))
        if not numero.is_finite() or numero != numero.to_integral_value():
            raise ValueError()
        resultado = int(numero)
        if resultado < minimo:
            raise ValueError()
        return resultado
    except (ValueError, InvalidOperation):
        raise ValueError(f"Catalogo invalido: {campo} debe ser un entero >= {minimo}.") from None


def normalizar_catalogo(filas):
    equipos = []
    ids, localizaciones = set(), set()
    for fila in filas:
        equipo_id = entero(fila.get("ID"), "ID", 1)
        loc = entero(fila.get("LOCALIZACION"), "LOCALIZACION", 1)
        if equipo_id in ids or loc in localizaciones:
            raise ValueError("Catalogo invalido: ID o LOCALIZACION repetido.")
        ids.add(equipo_id)
        localizaciones.add(loc)
        nombre = str(fila.get("EQUIPO") or "").strip()
        if not nombre:
            raise ValueError(f"Catalogo invalido: equipo {loc} sin nombre.")
        puntos = entero(fila.get("PUNTOS") or 0, "PUNTOS")
        familia = fila.get("FAMILIA_COMPAT")
        equipos.append(dict(
            id=equipo_id,
            codeSys=entero(fila.get("CODE_SYS"), "CODE_SYS", 1),
            localizacion=loc,
            equipo=nombre,
            qrCode=str(fila.get("CODE_QR") or "").strip() or str(loc),
            puntos=puntos,
            ptEq=puntos,
            sistema=str(fila.get("sistema") or "").strip(),
            subsistema=str(fila.get("subsistema") or "").strip(),
            scada=str(fila.get("TAGNAME") or "").strip(),
            familiaCompat=None if familia is None else entero(familia, "FAMILIA_COMPAT"),
        ))
    if not equipos:
        raise ValueError("MariaDB devolvio un catalogo vacio; se cancela el APK.")
    return sorted(equipos, key=lambda equipo: equipo["localizacion"])


def literal_dart(value):
    # JSON escapa comillas, barras y controles; Dart ademas interpola '$'.
    return json.dumps(value, ensure_ascii=True).replace("$", r"\$")


def generar_dart(equipos, anterior=""):
    serializado = json.dumps(equipos, sort_keys=True, ensure_ascii=True)
    firma = hashlib.sha256(serializado.encode("utf-8")).hexdigest()
    if f"const String catalogoBaseSha256 = '{firma}';" in anterior:
        return anterior
    version = re.search(r"const int catalogoBaseVersion = (\d+);", anterior)
    nueva_version = int(version[1]) + 1 if version else 1
    fecha = datetime.now(timezone.utc).isoformat(timespec="seconds")
    lineas = [
        "// Generado por actualizar_catalogo_apk.py desde MariaDB. No editar a mano.",
        "// Solo para tablets vacias; el catalogo descargado por USB tiene prioridad.",
        "import '../models/models.dart';", "",
        f"const int catalogoBaseVersion = {nueva_version};",
        f"const int catalogoBaseCantidad = {len(equipos)};",
        f"const String catalogoBaseFechaUtc = '{fecha}';",
        f"const String catalogoBaseSha256 = '{firma}';", "",
        "// Nombre conservado por compatibilidad: contiene equipos REALES, no mocks.",
        "final List<Equipo> mockEquipos = [",
    ]
    for equipo in equipos:
        lineas.append("  const Equipo(")
        lineas.extend(f"    {campo}: {literal_dart(value)}," for campo, value in equipo.items())
        lineas.append("  ),")
    return "\n".join(lineas + ["];", ""])


def descargar_catalogo(uploader):
    if uploader.pymysql is None:
        raise RuntimeError("Falta pymysql. Instale requirements_tablet_uploader.txt.")
    maria = uploader.pymysql.connect(
        host=uploader.DB_HOST, port=uploader.DB_PORT,
        user=uploader.DB_USER, password=uploader.DB_PASS,
        database=uploader.DB_NAME, charset="utf8mb4",
        cursorclass=uploader.pymysql.cursors.DictCursor,
        connect_timeout=10, read_timeout=30, write_timeout=10,
        autocommit=False,
    )
    try:
        with maria.cursor() as cur:
            cur.execute("START TRANSACTION READ ONLY")
            cur.execute(SQL_CATALOGO)
            return normalizar_catalogo(cur.fetchall())
    finally:
        maria.close()


def actualizar_catalogo(equipos, destino=CATALOGO):
    anterior = destino.read_text(encoding="utf-8") if destino.exists() else ""
    contenido = generar_dart(equipos, anterior)
    if contenido != anterior:
        temporal = destino.with_suffix(".dart.tmp")
        temporal.write_text(contenido, encoding="utf-8", newline="\n")
        temporal.replace(destino)
    return len(equipos)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sin-dialogo", action="store_true",
                        help="Usar SCV_DB_PASSWORD del entorno, sin ventana de acceso.")
    args = parser.parse_args()
    import tablet_uploader as uploader
    try:
        if not uploader.DB_PASS:
            if args.sin_dialogo:
                raise RuntimeError("Falta la clave de MariaDB en el entorno local.")
            from abrir_subidor_seguro import request_credentials
            if not request_credentials():
                raise RuntimeError("Acceso cancelado: no se generara un APK desactualizado.")
        equipos = descargar_catalogo(uploader)
        cantidad = actualizar_catalogo(equipos)
        print(f"Catalogo verificado en MariaDB: {cantidad} equipos incluidos en el APK.", flush=True)
        return 0
    except Exception as exc:
        # No imprimir las credenciales ni cadenas de conexion en errores.
        if uploader.pymysql and isinstance(exc, uploader.pymysql.MySQLError):
            codigo = exc.args[0] if exc.args else "desconocido"
            mensaje = f"No se pudo leer MariaDB (codigo {codigo}). Revise la conexion y el acceso."
        else:
            mensaje = str(exc)
        print(f"ERROR: {mensaje} Se conserva el catalogo anterior; compilacion cancelada.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
