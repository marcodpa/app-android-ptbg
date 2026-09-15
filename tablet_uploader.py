"""Sube mediciones locales de la tablet SCV-PTBG a MariaDB por USB/ADB.

Flujo operativo:
1. Abrir este programa en la laptop del usuario.
2. Conectar la tablet por USB con depuracion habilitada.
3. Detectar tablet, leer pendientes, subir desde la laptop y confirmar.

La tablet no usa WiFi ni el API para sincronizar. La conexion a MariaDB sale
desde la laptop donde corre este programa.
"""

from __future__ import annotations

import os
import base64
import hashlib
import json
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Callable, Iterable

try:
    import pymysql
except ImportError:  # pragma: no cover - se informa en runtime al operador.
    pymysql = None

try:
    from black_start_report import build_black_start_pdf
except ImportError:  # pragma: no cover - se informa al imprimir.
    build_black_start_pdf = None

try:
    from compressor_checklist_report import build_compressor_checklist_pdf
except ImportError:  # pragma: no cover - se informa al imprimir.
    build_compressor_checklist_pdf = None

try:
    from equipment_report import build_equipment_report_pdf
except ImportError:  # pragma: no cover - se informa al generar el reporte.
    build_equipment_report_pdf = None

try:
    from official_form_report import build_official_report_from_db, fill_official_form
except ImportError:
    build_official_report_from_db = None
    fill_official_form = None

def cargar_env_local(ruta: Path | None = None) -> list[str]:
    """Lee el archivo .env que esta junto a este programa.

    La conexion a MariaDB sale de variables de entorno, y en una laptop de
    planta recien preparada no hay ninguna puesta: el programa arrancaba con
    la clave vacia y fallaba al conectar sin decir por que. Con esto basta
    con llenar el .env una vez —esta en .gitignore, no viaja al repositorio—
    y volver a abrir el programa.

    Lo que ya venga en el entorno real manda: el .env solo rellena huecos.
    Devuelve los nombres que cargo, nunca los valores.
    """
    archivo = ruta or (Path(__file__).resolve().parent / ".env")
    cargadas: list[str] = []
    try:
        if not archivo.is_file():
            return cargadas
        for linea in archivo.read_text(encoding="utf-8-sig").splitlines():
            limpia = linea.strip()
            if not limpia or limpia.startswith("#"):
                continue
            if limpia.lower().startswith("export "):
                limpia = limpia[7:].strip()
            if "=" not in limpia:
                continue
            nombre, _, valor = limpia.partition("=")
            nombre = nombre.strip()
            valor = valor.strip().strip('"').strip("'")
            if not nombre or not valor:
                continue
            if os.environ.get(nombre):
                continue
            os.environ[nombre] = valor
            cargadas.append(nombre)
    except Exception:
        # Un .env mal escrito no puede impedir que el programa abra: se sigue
        # con lo que haya en el entorno y el error de conexion lo dira.
        return cargadas
    return cargadas


ENV_CARGADAS = cargar_env_local()

DB_HOST = os.getenv("SCV_DB_HOST","172.16.200.2")
DB_PORT = int(os.getenv("SCV_DB_PORT", "3306"))
DB_USER = os.getenv("SCV_DB_USER", "admin")
DB_PASS = os.getenv("SCV_DB_PASSWORD", "")
DB_NAME = os.getenv("SCV_DB_NAME", "PTBG_DAT")

PACKAGE_NAME = "com.example.scv_ptbg"
REMOTE_DB = f"/data/data/{PACKAGE_NAME}/databases/scv_ptbg.db"
REMOTE_DB_JOURNAL = f"{REMOTE_DB}-journal"
REMOTE_PREFS = f"/data/data/{PACKAGE_NAME}/shared_prefs/FlutterSharedPreferences.xml"
REMOTE_USB_STATUS = f"/data/data/{PACKAGE_NAME}/files/usb_status.json"
REMOTE_USB_REQUEST = f"/data/data/{PACKAGE_NAME}/files/usb_sync_request.json"
REMOTE_USB_PRINT_REQUEST = f"/data/data/{PACKAGE_NAME}/files/usb_print_request.json"

FORMATOS_DIR = Path(r"\\172.16.200.11\Respaldo\AS\FORMATOS NUEVOS")
LOCAL_FORMATOS_DIR = Path(__file__).with_name("formatos_pdf_nuevos")
LEGACY_FORMATOS_DIR = Path(__file__).with_name("formatos_pdf")
PRINTER_SETTINGS_FILE = Path(__file__).with_name("printer_settings.json")
PRINT_REQUEST_HISTORY_FILE = Path(__file__).with_name("processed_print_requests.json")
PRINT_REQUEST_LOCK_FILE = Path(__file__).with_name("print_request.lock")
PRINT_REQUEST_DEDUP_SECONDS = 10 * 60
TEMPLATE_BASE_WIDTH = 595.3200073242188
TEMPLATE_BASE_HEIGHT = 841.9199829101562
LETTER_WIDTH = 612
LETTER_HEIGHT = 792
PRINT_TEMPLATE_BY_PT_EQ = {
    1: "Motor-Bomba(A).pdf",
    2: "Motor-Bomba(A).pdf",
    3: "Motor-Bomba(A).pdf",
    4: "Motor-Ventilador(Fin-Fan).pdf",
    5: "Motor-Ventilador(Vent).pdf",
    6: "Motor-Caja-Bomba.pdf",
    7: "Motor-Bomba(B).pdf",
    8: "Motor-Bomba(B).pdf",
    9: "Motor-Bomba(A).pdf",
}
PRINT_TEMPLATE_ALIASES = {
    "Motor-Bomba(A).pdf": ("Motor-Bomba(A).pdf", "Motor-Bomba(A) .pdf"),
    "Motor-Bomba(B).pdf": ("Motor-Bomba(B).pdf", "Motor-Bomba(B) .pdf"),
    "Motor-Caja-Bomba.pdf": ("Motor-Caja-Bomba.pdf",),
    "Motor-Ventilador(Fin-Fan).pdf": (
        "Motor-Ventilador(Fin-Fan).pdf",
        "Motor-Ventilador(Fin-Fan) .pdf",
    ),
    "Motor-Ventilador(Vent).pdf": ("Motor-Ventilador(Vent).pdf",),
}

MEASUREMENT_COLUMNS = tuple(
    f"{axis}{point}" for point in range(1, 10) for axis in ("H", "V", "A")
)
INSERT_COLUMNS = (
    # Identidad de la medicion: permite reintentar un envio sin duplicar.
    "UUID",
    "FECHA",
    "HORA",
    "SISTEMA",
    "LOCALIZACION",
    *MEASUREMENT_COLUMNS,
    "RMS",
    "OBSERVACIONES",
    "USUARIO",
    "CARGO",
    "MARCA",
    "MODELO",
    "SERIAL",
    "ODT",
)

INSERT_SQL = f"""
INSERT INTO MOT_VIBR_MUES
({",".join(INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(INSERT_COLUMNS))})
"""

TEMPERATURE_COLUMNS = tuple(f"T{point}" for point in range(1, 11))
TEMPERATURE_INSERT_COLUMNS = (
    "UUID",
    "FECHA",
    "HORA",
    "SISTEMA",
    "LOCALIZACION",
    *TEMPERATURE_COLUMNS,
    "OBSERVACIONES",
    "USUARIO",
    "CARGO",
    "MARCA",
    "MODELO",
    "SERIAL",
    "ODT",
)
TEMPERATURE_INSERT_SQL = f"""
INSERT INTO MOT_TEMP_MUES
({",".join(TEMPERATURE_INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(TEMPERATURE_INSERT_COLUMNS))})
"""

ALIGNMENT_COLUMNS = (
    "AMB_ANGULO_V", "AMB_ANGULO_H", "AMB_COMPENSACION_V", "AMB_COMPENSACION_H",
    "ACM_ANGULO_V", "ACM_ANGULO_H", "ACM_COMPENSACION_V", "ACM_COMPENSACION_H",
    "ACB_ANGULO_V", "ACB_ANGULO_H", "ACB_COMPENSACION_V", "ACB_COMPENSACION_H",
)
ALIGNMENT_INSERT_COLUMNS = (
    "UUID",
    "FECHA", "HORA", "SISTEMA", "LOCALIZACION", *ALIGNMENT_COLUMNS,
    "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
)
ALIGNMENT_INSERT_SQL = f"""
INSERT INTO MOT_ALN_REG
({",".join(ALIGNMENT_INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(ALIGNMENT_INSERT_COLUMNS))})
"""

LUBRICATION_COLUMNS = tuple(f"L{point}" for point in range(1, 10))
LUBRICATION_INSERT_COLUMNS = (
    "UUID",
    "FECHA", "HORA", "SISTEMA", "LOCALIZACION", *LUBRICATION_COLUMNS,
    "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
)
LUBRICATION_INSERT_SQL = f"""
INSERT INTO MOT_LUB_REG
({",".join(LUBRICATION_INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(LUBRICATION_INSERT_COLUMNS))})
"""

COUPLING_INSERT_COLUMNS = (
    "UUID",
    "FECHA", "HORA", "SISTEMA", "LOCALIZACION", "OBSERVACIONES",
    "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
    # Coupling e inserto se cambian por separado: puede tocarse uno, el otro o
    # los dos, asi que son dos banderas y no una sola respuesta.
    "COUPLING", "INSERTO", "MODELO_CPLG",
)
COUPLING_INSERT_SQL = f"""
INSERT INTO MOT_CPLG_REG
({','.join(COUPLING_INSERT_COLUMNS)})
VALUES ({','.join(['%s'] * len(COUPLING_INSERT_COLUMNS))})
"""

# Bitacora del administrador. Lo que el admin corrige o retro-fecha en la
# tablet sube a MOT_LOG_ADM para que la auditoria viva en la planta y no
# dependa de que alguien mire la tablet.
ADMIN_LOG_INSERT_COLUMNS = (
    "UUID",
    "FECHA", "HORA", "USUARIO", "CARGO", "ACCION", "SERVICIO",
    "LOCALIZACION", "UUID_MEDICION", "DETALLE", "TABLET",
)
ADMIN_LOG_INSERT_SQL = f"""
INSERT INTO MOT_LOG_ADM
({','.join(ADMIN_LOG_INSERT_COLUMNS)})
VALUES ({','.join(['%s'] * len(ADMIN_LOG_INSERT_COLUMNS))})
"""

# Ajuste de correa de ventiladores y fin-fan. Va a MOT_AJC_REG.
BELT_INSERT_COLUMNS = (
    "UUID",
    "FECHA", "HORA", "SISTEMA", "LOCALIZACION", "TENSION", "OBSERVACIONES",
    "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
)
BELT_INSERT_SQL = f"""
INSERT INTO MOT_AJC_REG
({','.join(BELT_INSERT_COLUMNS)})
VALUES ({','.join(['%s'] * len(BELT_INSERT_COLUMNS))})
"""

import separator_cleaning

WORK_ORDER_COLUMNS = (
    "ODT", "FECHA", "HORA", "EQUIPO", "UBICACION", "CODE_CONJUNTO",
    "VIBRACION", "TEMPERATURA", "ALINEACION", "LUBRICACION",
    "COUPLING_RPL", "CORREA_AJT", "REEMPLAZO", "LIMPIEZA_PLATO",
    "TABLET_ORIGEN",
)
WORK_ORDER_INSERT_SQL = f"""
INSERT INTO MOT_INDICE
({','.join(WORK_ORDER_COLUMNS)})
VALUES ({','.join(['%s'] * len(WORK_ORDER_COLUMNS))})
"""

REPLACEMENT_TABLES = {
    1: ("MOT_DATA", "Motor"),
    2: ("MOT_BOMB_DATA", "Bomba"),
    3: ("MOT_CAJA_DATA", "Caja"),
    4: ("MOT_VENT_DATA", "Ventilador"),
}

# Estatus que el tecnico puede fijar a mano desde la tablet. INSTALADO queda
# fuera a proposito: que una pieza este puesta en un equipo lo decide el
# reemplazo, nunca un cambio manual de estatus.
ESTADO_CHANGE_ALLOWED = ("DISPONIBLE", "AVERIADO", "DESECHADO")

# Estatus que lleva la pieza mientras su orden de reparacion esta abierta. No
# esta en ESTADO_CHANGE_ALLOWED a proposito: no lo puede fijar el tecnico a
# dedo, solo lo produce abrir una orden y solo cerrarla lo saca.
ESTADO_EN_REPARACION = "EN REPARACION"

# Con que estatus vuelve la pieza al inventario segun como salio del taller.
RESULTADOS_REPARACION = {
    "REPARADO": "DISPONIBLE",
    "NO REPARABLE": "DESECHADO",
    "SIN INTERVENCION": "AVERIADO",
}

# A donde se puede mandar una pieza. Lista cerrada para que el inventario no
# termine con veinte formas de escribir el mismo taller.
DESTINOS_REPARACION = (
    "TALLER ELECTRICO",
    "TALLER MECANICO",
    "TALLER EXTERNO",
    "ALMACEN PRINCIPAL",
    "ALMACEN DE MOTORES",
)


def fetch_current_equipment_components(
    localizacion: int,
    code_conjunto: int,
    points: int,
) -> dict[str, dict[str, str]]:
    """Lee la placa vigente de cada componente desde su tabla oficial."""
    labels = {1: "MOTOR", 2: "BOMBA", 3: "CAJA", 4: "VENT."}
    component_types = [1]
    if points == 6:
        component_types.extend([3, 2])
    elif points in {4, 5}:
        component_types.append(4)
    else:
        component_types.append(2)

    result: dict[str, dict[str, str]] = {}
    maria = connect_mariadb()
    try:
        with maria.cursor() as cursor:
            for component_type in component_types:
                table, _ = REPLACEMENT_TABLES[component_type]
                # Cada maestra guarda ahora una fila por pieza fisica, incluidas
                # las retiradas; sin ACTIVO = 1 el formato oficial impreso podria
                # llevar el serial de una pieza que ya salio del equipo.
                cursor.execute(
                    f"""
                    SELECT MARCA, MODELO, SERIAL
                    FROM `{table}`
                    WHERE UBICACION = %s AND CODE_CONJUNTO = %s AND ACTIVO = 1
                    LIMIT 1
                    """,
                    (localizacion, code_conjunto),
                )
                row = cursor.fetchone()
                if row:
                    result[labels[component_type]] = {
                        "brand": _replacement_text(row.get("MARCA")),
                        "model": _replacement_text(row.get("MODELO")),
                        "serial": _replacement_text(row.get("SERIAL")),
                    }
    finally:
        maria.close()
    return result


def apply_components_before_replacement(
    db_path: Path,
    localizacion: int,
    code_conjunto: int,
    odt: int | None,
    components: dict[str, dict[str, str]],
) -> dict[str, dict[str, str]]:
    """Para una ODT de reemplazo sustituye la placa vigente por la placa anterior."""
    if odt is None:
        return components
    labels = {1: "MOTOR", 2: "BOMBA", 3: "CAJA", 4: "VENT."}
    sqlite_conn = sqlite3.connect(db_path)
    sqlite_conn.row_factory = sqlite3.Row
    try:
        replacements = sqlite_conn.execute(
            """
            SELECT equipo, fecha, hora
            FROM REEMPLAZOS_LOCAL
            WHERE localizacion = ? AND odt = ?
            ORDER BY equipo
            """,
            (localizacion, odt),
        ).fetchall()
    finally:
        sqlite_conn.close()
    if not replacements:
        return components

    before = dict(components)
    maria = connect_mariadb()
    try:
        with maria.cursor() as cursor:
            for replacement in replacements:
                component_type = int(replacement["equipo"] or 0)
                label = labels.get(component_type)
                if not label:
                    continue
                cursor.execute(
                    """
                    SELECT MARCA, MODELO, SERIAL
                    FROM MOT_LOG_RPL
                    WHERE UBICACION = %s
                      AND CODE_CONJUNTO = %s
                      AND EQUIPO = %s
                      AND FECHA = %s
                      AND HORA = %s
                    ORDER BY ID DESC
                    LIMIT 1
                    """,
                    (
                        localizacion,
                        code_conjunto,
                        component_type,
                        replacement["fecha"],
                        replacement["hora"],
                    ),
                )
                old_row = cursor.fetchone()
                if old_row:
                    before[label] = {
                        "brand": _replacement_text(old_row.get("MARCA")),
                        "model": _replacement_text(old_row.get("MODELO")),
                        "serial": _replacement_text(old_row.get("SERIAL")),
                    }
    finally:
        maria.close()
    return before

MOTOR_TECHNICAL_FIELDS = (
    ("voltaje", "VOLTAJE"),
    ("corriente", "CORRIENTE"),
    ("rpm", "RPM"),
    ("sf", "SF"),
    ("hp", "HP"),
    ("frame", "FRAME"),
    ("brgs_drive", "BRGS_DRIVE"),
    ("brgs_opp", "BRGS_OPP"),
    ("ciclo", "CICLO"),
    ("arranque", "ARRANQUE"),
    ("ph", "PH"),
    ("tension", "TENSION"),
    ("lubricacion", "LUBRICACION"),
)


@dataclass(frozen=True)
class Device:
    serial: str
    state: str


@dataclass
class UploadSummary:
    total: int = 0
    uploaded: int = 0
    skipped: int = 0
    failed: int = 0
    messages: list[str] | None = None

    def __post_init__(self) -> None:
        if self.messages is None:
            self.messages = []

    def __post_init__(self) -> None:
        if self.messages is None:
            self.messages = []


def find_adb() -> str:
    executable = "adb.exe" if os.name == "nt" else "adb"
    candidates: list[Path] = []

    explicit = os.getenv("SCV_ADB_PATH")
    if explicit:
        candidates.append(Path(explicit).expanduser())

    for env_name in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        sdk_root = os.getenv(env_name)
        if sdk_root:
            candidates.append(Path(sdk_root) / "platform-tools" / executable)

    candidates.append(
        Path.home()
        / "AppData"
        / "Local"
        / "Android"
        / "Sdk"
        / "platform-tools"
        / executable
    )

    # Codex y las instalaciones portátiles guardan el SDK en .tools.
    # Se recorren los padres del proyecto para que funcione sin PATH global.
    script_path = Path(__file__).resolve()
    for parent in script_path.parents:
        candidates.append(
            parent / ".tools" / "android-sdk" / "platform-tools" / executable
        )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    found = shutil.which("adb")
    if found:
        return found
    raise FileNotFoundError(
        "No se encontro adb.exe. Configure SCV_ADB_PATH o instale "
        "Android Platform Tools."
    )


def _hidden_process_flags() -> int:
    """Evita que adb/PowerShell abran ventanas CMD al usar la interfaz GUI."""
    return subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def _hidden_startup_info() -> subprocess.STARTUPINFO | None:
    """Refuerzo para ocultar ventanas incluso en configuraciones antiguas de Windows."""
    if os.name != "nt":
        return None
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    info.wShowWindow = subprocess.SW_HIDE
    return info


def run_adb(args: Iterable[str], *, serial: str | None = None, timeout: int = 30) -> subprocess.CompletedProcess:
    cmd = [find_adb()]
    if serial:
        cmd += ["-s", serial]
    cmd += list(args)
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        creationflags=_hidden_process_flags(),
        startupinfo=_hidden_startup_info(),
    )


def list_devices() -> list[Device]:
    res = run_adb(["devices"])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or res.stdout.strip() or "ADB no respondio.")

    devices: list[Device] = []
    for line in res.stdout.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2:
            devices.append(Device(serial=parts[0], state=parts[1]))
    return devices


def select_ready_device(devices: list[Device]) -> Device:
    ready = [device for device in devices if device.state == "device"]
    if not ready:
        unauthorized = [device for device in devices if device.state == "unauthorized"]
        if unauthorized:
            serials = ", ".join(device.serial for device in unauthorized)
            raise RuntimeError(
                "La tablet esta conectada, pero Android no autorizo esta laptop "
                f"({serials}:unauthorized). Desbloquee la tablet, acepte "
                "'Permitir depuracion USB' y marque 'Permitir siempre desde esta computadora'."
            )
        states = ", ".join(f"{d.serial}:{d.state}" for d in devices) or "ninguna tablet"
        raise RuntimeError(f"No hay tablet lista por USB ({states}).")
    if len(ready) > 1:
        raise RuntimeError("Hay mas de una tablet conectada. Deje solo una para sincronizar.")
    return ready[0]


def tablet_connection_status(devices: list[Device]) -> tuple[str, str]:
    ready = [device for device in devices if device.state == "device"]
    if ready:
        return "ONLINE", ready[0].serial
    if any(device.state == "unauthorized" for device in devices):
        return "OFFLINE", "Tablet sin autorizar: acepte Permitir depuracion USB"
    if devices:
        states = ", ".join(f"{device.serial}:{device.state}" for device in devices)
        return "OFFLINE", states
    return "OFFLINE", "Tablet no conectada"


def pull_tablet_database(serial: str, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    local_db = target_dir / "scv_ptbg_tablet.db"

    cmd = [find_adb(), "-s", serial, "exec-out", "run-as", PACKAGE_NAME, "cat", REMOTE_DB]
    res = subprocess.run(
        cmd,
        capture_output=True,
        timeout=60,
        creationflags=_hidden_process_flags(),
        startupinfo=_hidden_startup_info(),
    )
    if res.returncode != 0:
        stderr = res.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            "No pude leer la base de la tablet. Verifique que la app instalada sea debug "
            f"y que la tablet este desbloqueada. {stderr}"
        )
    local_db.write_bytes(res.stdout)

    if not _looks_like_sqlite(local_db):
        raise RuntimeError("El archivo recibido de la tablet no parece una base SQLite valida.")
    return local_db


def push_tablet_database(serial: str, local_db: Path) -> None:
    remote_tmp = "/data/local/tmp/scv_ptbg.db"
    push = run_adb(["push", str(local_db), remote_tmp], serial=serial, timeout=60)
    if push.returncode != 0:
        raise RuntimeError(push.stderr.strip() or "No pude copiar la base actualizada a la tablet.")

    shell = (
        f"run-as {PACKAGE_NAME} sh -c "
        f"'cp {remote_tmp} {REMOTE_DB} && rm -f {REMOTE_DB_JOURNAL}'"
    )
    res = run_adb(["shell", shell], serial=serial, timeout=30)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "No pude actualizar la base en la tablet.")


def update_shared_prefs_xml(xml_text: str, values: dict[str, str]) -> str:
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        root = ET.Element("map")

    if root.tag != "map":
        root = ET.Element("map")

    existing = {
        child.attrib.get("name"): child
        for child in list(root)
        if child.tag == "string" and child.attrib.get("name")
    }
    for name, value in values.items():
        node = existing.get(name)
        if node is None:
            node = ET.SubElement(root, "string", {"name": name})
        node.text = value

    ET.indent(root, space="  ")
    body = ET.tostring(root, encoding="unicode")
    return "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n" + body


def parse_shared_prefs_xml(xml_text: str) -> dict[str, str]:
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return {}
    result: dict[str, str] = {}
    if root.tag != "map":
        return result
    for child in root:
        name = child.attrib.get("name")
        if not name:
            continue
        if child.tag == "string":
            result[name] = child.text or ""
        elif child.tag in {"boolean", "int", "long", "float"}:
            result[name] = child.attrib.get("value", "")
    return result


def read_tablet_operator(serial: str) -> tuple[str, str]:
    prefs = run_adb(
        ["exec-out", "run-as", PACKAGE_NAME, "cat", REMOTE_PREFS],
        serial=serial,
        timeout=15,
    )
    if prefs.returncode != 0:
        return "", ""
    data = parse_shared_prefs_xml(prefs.stdout)
    responsable = (
        data.get("flutter.responsable")
        or data.get("responsable")
        or data.get("flutter.username")
        or data.get("username")
        or ""
    ).strip()
    cargo = (
        data.get("flutter.cargo")
        or data.get("cargo")
        or data.get("flutter.rol")
        or data.get("rol")
        or ""
    ).strip()
    return responsable, cargo


def set_tablet_usb_status(
    serial: str,
    *,
    status: str,
    detail: str,
    tmp_dir: Path | None = None,
    request_id: str = "",
) -> None:
    now = datetime.now().isoformat(timespec="seconds")
    prefs = run_adb(
        ["exec-out", "run-as", PACKAGE_NAME, "cat", REMOTE_PREFS],
        serial=serial,
        timeout=15,
    )
    current = prefs.stdout if prefs.returncode == 0 else "<map />"
    updated = update_shared_prefs_xml(
        current,
        {
            "flutter.usb_sync_status": status,
            "flutter.usb_sync_serial": serial,
            "flutter.usb_sync_detail": detail,
            "flutter.usb_sync_last_seen": now,
            "flutter.usb_sync_request_id": request_id,
        },
    )

    work_dir = tmp_dir or Path(tempfile.mkdtemp(prefix="scv_ptbg_prefs_"))
    work_dir.mkdir(parents=True, exist_ok=True)
    local_prefs = work_dir / "FlutterSharedPreferences.xml"
    local_prefs.write_text(updated, encoding="utf-8")
    local_status = work_dir / "usb_status.json"
    local_status.write_text(
        json.dumps(
            {
                "status": status,
                "serial": serial,
                "detail": detail,
                "last_seen": now,
                "request_id": request_id,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    remote_tmp = "/data/local/tmp/FlutterSharedPreferences.xml"
    push = run_adb(["push", str(local_prefs), remote_tmp], serial=serial, timeout=15)
    if push.returncode != 0:
        raise RuntimeError(push.stderr.strip() or "No pude copiar el estado USB a la tablet.")
    shell = (
        f"run-as {PACKAGE_NAME} sh -c "
        f"'mkdir -p /data/data/{PACKAGE_NAME}/shared_prefs && "
        f"cp {remote_tmp} {REMOTE_PREFS}'"
    )
    res = run_adb(["shell", shell], serial=serial, timeout=15)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "No pude guardar el estado USB en la tablet.")

    remote_status_tmp = "/data/local/tmp/usb_status.json"
    push_status = run_adb(["push", str(local_status), remote_status_tmp], serial=serial, timeout=15)
    if push_status.returncode != 0:
        raise RuntimeError(push_status.stderr.strip() or "No pude copiar el estado USB a la tablet.")
    shell_status = (
        f"run-as {PACKAGE_NAME} sh -c "
        f"'mkdir -p /data/data/{PACKAGE_NAME}/files && "
        f"cp {remote_status_tmp} {REMOTE_USB_STATUS}'"
    )
    res_status = run_adb(["shell", shell_status], serial=serial, timeout=15)
    if res_status.returncode != 0:
        raise RuntimeError(res_status.stderr.strip() or "No pude guardar el archivo de estado USB.")


def read_tablet_usb_request(serial: str) -> dict | None:
    res = run_adb(
        ["exec-out", "run-as", PACKAGE_NAME, "cat", REMOTE_USB_REQUEST],
        serial=serial,
        timeout=10,
    )
    if res.returncode != 0 or not res.stdout.strip():
        return None
    try:
        data = json.loads(res.stdout.lstrip("\ufeff?ï»¿").strip())
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    if data.get("action") not in {"upload_pending", "download_data"}:
        return None
    return data


def clear_tablet_usb_request(serial: str) -> None:
    run_adb(
        ["shell", "run-as", PACKAGE_NAME, "rm", "-f", REMOTE_USB_REQUEST],
        serial=serial,
        timeout=10,
    )


def read_tablet_usb_print_request(serial: str) -> dict | None:
    res = run_adb(
        ["exec-out", "run-as", PACKAGE_NAME, "cat", REMOTE_USB_PRINT_REQUEST],
        serial=serial,
        timeout=10,
    )
    if res.returncode != 0 or not res.stdout.strip():
        return None
    try:
        data = json.loads(res.stdout.lstrip("\ufeff?Ã¯Â»Â¿").strip())
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    if data.get("action") not in {
        "print_pdf", "print_measurement", "equipment_report",
        "official_form_print", "compressor_checklist_print",
        "black_start_print",
    }:
        return None
    return data


def clear_tablet_usb_print_request(serial: str) -> None:
    run_adb(
        ["shell", "run-as", PACKAGE_NAME, "rm", "-f", REMOTE_USB_PRINT_REQUEST],
        serial=serial,
        timeout=10,
    )


def _print_request_key(request: dict) -> str:
    # Cada toque en la tablet genera un ID unico. Dos ODT o selecciones del
    # mismo equipo son solicitudes validas distintas; solo se considera
    # duplicado el reintento de exactamente el mismo ID.
    request_id = str(request.get("id") or "").strip()
    if request_id:
        return hashlib.sha1(f"request-id:{request_id}".encode("utf-8")).hexdigest()
    action = str(request.get("action") or "")
    if action == "equipment_report":
        payload_data = {
            "action": action,
            "id": request.get("id"),
            "localizacion": request.get("localizacion"),
            "report_type": request.get("report_type"),
        }
    elif action == "print_measurement":
        payload_data = {
            key: request.get(key)
            for key in (
                "action",
                "localizacion",
                "fecha",
                "hora",
                "tag",
                "pt_eq",
                "rms",
                "observaciones",
                "valores",
            )
        }
    else:
        payload_data = {
            "action": request.get("action"),
            "file_name": request.get("file_name"),
            "pdf_base64": request.get("pdf_base64"),
        }
    payload = json.dumps(payload_data, sort_keys=True, default=str, ensure_ascii=True)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


def _acquire_print_request_lock(max_age_seconds: int = 120) -> int | None:
    now = time.time()
    try:
        if PRINT_REQUEST_LOCK_FILE.exists():
            age = now - PRINT_REQUEST_LOCK_FILE.stat().st_mtime
            if age > max_age_seconds:
                PRINT_REQUEST_LOCK_FILE.unlink(missing_ok=True)
    except OSError:
        pass
    try:
        return os.open(str(PRINT_REQUEST_LOCK_FILE), os.O_CREAT | os.O_EXCL | os.O_RDWR)
    except FileExistsError:
        return None


def _release_print_request_lock(fd: int | None) -> None:
    if fd is not None:
        try:
            os.close(fd)
        except OSError:
            pass
    try:
        PRINT_REQUEST_LOCK_FILE.unlink(missing_ok=True)
    except OSError:
        pass


def _load_print_request_history() -> dict[str, float]:
    try:
        data = json.loads(PRINT_REQUEST_HISTORY_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    history: dict[str, float] = {}
    for key, value in data.items():
        try:
            history[str(key)] = float(value)
        except (TypeError, ValueError):
            continue
    return history


def _save_print_request_history(history: dict[str, float]) -> None:
    now = time.time()
    compact = {
        key: stamp
        for key, stamp in history.items()
        if now - stamp <= PRINT_REQUEST_DEDUP_SECONDS
    }
    PRINT_REQUEST_HISTORY_FILE.write_text(
        json.dumps(compact, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def _claim_print_request(request: dict) -> tuple[bool, str, int | None]:
    key = _print_request_key(request)
    lock_fd = _acquire_print_request_lock()
    if lock_fd is None:
        return False, key, None
    history = _load_print_request_history()
    now = time.time()
    last_seen = history.get(key)
    if last_seen is not None and now - last_seen <= PRINT_REQUEST_DEDUP_SECONDS:
        _save_print_request_history(history)
        return False, key, lock_fd
    history[key] = now
    _save_print_request_history(history)
    return True, key, lock_fd


def _looks_like_sqlite(path: Path) -> bool:
    with path.open("rb") as fh:
        return fh.read(16) == b"SQLite format 3\x00"


def fetch_pending_measurements(db_path: Path) -> list[dict]:
    return fetch_local_measurements(db_path, only_pending=True)


def fetch_local_measurements(db_path: Path, *, only_pending: bool = False) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        _ensure_local_measurement_identity_columns(conn)
        where = "WHERE COALESCE(sincronizado, 0) = 0" if only_pending else ""
        has_equipo_info = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='EQUIPO_INFO'"
        ).fetchone() is not None
        info_columns = (
            "i.marca AS info_marca, i.modelo AS info_modelo, i.serial AS info_serial"
            if has_equipo_info
            else "NULL AS info_marca, NULL AS info_modelo, NULL AS info_serial"
        )
        info_join = (
            "LEFT JOIN EQUIPO_INFO i ON i.localizacion = m.localizacion"
            if has_equipo_info
            else ""
        )
        rows = conn.execute(
            f"""
            SELECT
              m.*,
              {info_columns}
            FROM MEDICIONES_LOCAL m
            {info_join}
            {where}
            ORDER BY m.created_at ASC
            """
        ).fetchall()
        return [_normalize_local_row(dict(row)) for row in rows]
    finally:
        conn.close()


def _ensure_local_measurement_identity_columns(conn: sqlite3.Connection) -> None:
    for column in ("responsable", "cargo", "marca", "modelo", "serial"):
        try:
            conn.execute(f"ALTER TABLE MEDICIONES_LOCAL ADD COLUMN {column} TEXT")
        except sqlite3.OperationalError:
            pass
    try:
        conn.execute("ALTER TABLE MEDICIONES_LOCAL ADD COLUMN odt INTEGER")
    except sqlite3.OperationalError:
        pass
    conn.commit()


def _ensure_sqlite_columns(
    conn: sqlite3.Connection,
    table: str,
    columns: tuple[tuple[str, str], ...],
) -> None:
    existing = {str(row[1]).lower() for row in conn.execute(f"PRAGMA table_info({table})")}
    for name, declaration in columns:
        if name.lower() not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {declaration}")


def ensure_local_temperature_tables(conn: sqlite3.Connection) -> None:
    temperature_defs = ",\n          ".join(f"{column} REAL DEFAULT 0" for column in TEMPERATURE_COLUMNS)
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS TEMPERATURAS_LOCAL (
          uuid            TEXT PRIMARY KEY,
          localizacion    INTEGER,
          sistema         TEXT,
          puntos          INTEGER NOT NULL DEFAULT 0,
          fecha           TEXT,
          hora            TEXT,
          {temperature_defs},
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          odt             INTEGER,
          sincronizado    INTEGER DEFAULT 0,
          error_sync      TEXT,
          created_at      TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    _ensure_sqlite_columns(
        conn,
        "TEMPERATURAS_LOCAL",
        (
            *((column, "REAL DEFAULT 0") for column in TEMPERATURE_COLUMNS),
            ("observaciones", "TEXT"),
            ("responsable", "TEXT"),
            ("cargo", "TEXT"),
            ("marca", "TEXT"),
            ("modelo", "TEXT"),
            ("serial", "TEXT"),
            ("odt", "INTEGER"),
            ("sincronizado", "INTEGER DEFAULT 0"),
            ("error_sync", "TEXT"),
            ("created_at", "TEXT"),
        ),
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_TEMPERATURAS_PENDING
        ON TEMPERATURAS_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def _normalize_temperature_row(row: dict) -> dict:
    normalized = {
        "uuid": row.get("uuid"),
        # Tambien en mayusculas: las tuplas *_INSERT_COLUMNS leen asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": row.get("fecha") or row.get("FECHA"),
        "HORA": row.get("hora") or row.get("HORA"),
        "SISTEMA": row.get("sistema") or row.get("SISTEMA"),
        "LOCALIZACION": row.get("localizacion") or row.get("LOCALIZACION"),
        "OBSERVACIONES": row.get("observaciones") or row.get("OBSERVACIONES") or "",
        "USUARIO": (
            row.get("usuario")
            or row.get("USUARIO")
            or row.get("responsable")
            or row.get("RESPONSABLE")
            or ""
        ),
        "CARGO": row.get("cargo") or row.get("CARGO") or "",
        "MARCA": row.get("marca") or row.get("MARCA") or "",
        "MODELO": row.get("modelo") or row.get("MODELO") or "",
        "SERIAL": row.get("serial") or row.get("SERIAL") or "",
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }
    for column in TEMPERATURE_COLUMNS:
        value = row.get(column)
        normalized[column] = 0.0 if value is None else value
    return normalized


def fetch_pending_temperatures(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_local_temperature_tables(conn)
        rows = conn.execute(
            """
            SELECT *
            FROM TEMPERATURAS_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [_normalize_temperature_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_temperature_insert_values(row: dict) -> tuple:
    values = dict(row)
    for column in TEMPERATURE_COLUMNS:
        if values.get(column) is None:
            values[column] = 0.0
    return tuple(values.get(column) for column in TEMPERATURE_INSERT_COLUMNS)


def ensure_alignment_schema(conn: sqlite3.Connection) -> None:
    value_defs = ",\n          ".join(f"{column} REAL" for column in ALIGNMENT_COLUMNS)
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS ALINEACIONES_LOCAL (
          uuid            TEXT PRIMARY KEY,
          localizacion    INTEGER,
          sistema         TEXT,
          fecha           TEXT,
          hora            TEXT,
          {value_defs},
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          odt             INTEGER,
          sincronizado    INTEGER NOT NULL DEFAULT 0,
          error_sync      TEXT,
          created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    _ensure_sqlite_columns(
        conn,
        "ALINEACIONES_LOCAL",
        (
            *((column, "REAL") for column in ALIGNMENT_COLUMNS),
            ("puntos", "INTEGER NOT NULL DEFAULT 0"),
            ("observaciones", "TEXT"), ("responsable", "TEXT"), ("cargo", "TEXT"),
            ("marca", "TEXT"), ("modelo", "TEXT"), ("serial", "TEXT"),
            ("odt", "INTEGER"), ("sincronizado", "INTEGER NOT NULL DEFAULT 0"),
            ("error_sync", "TEXT"), ("created_at", "TEXT"),
        ),
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_ALINEACIONES_PENDING
        ON ALINEACIONES_LOCAL(sincronizado, created_at)
        """
    )
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS ALINEACIONES_REMOTAS (
          remote_key      TEXT PRIMARY KEY,
          localizacion    INTEGER,
          sistema         TEXT,
          puntos          INTEGER NOT NULL DEFAULT 0,
          fecha           TEXT,
          hora            TEXT,
          fecha_hora_iso  TEXT,
          {value_defs},
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          odt             INTEGER
        )
        """
    )
    _ensure_sqlite_columns(
        conn,
        "ALINEACIONES_REMOTAS",
        (
            ("sistema", "TEXT"), ("fecha", "TEXT"), ("hora", "TEXT"),
            ("puntos", "INTEGER NOT NULL DEFAULT 0"),
            ("fecha_hora_iso", "TEXT"), *((column, "REAL") for column in ALIGNMENT_COLUMNS),
            ("observaciones", "TEXT"), ("responsable", "TEXT"), ("cargo", "TEXT"),
            ("marca", "TEXT"), ("modelo", "TEXT"), ("serial", "TEXT"), ("odt", "INTEGER"),
        ),
    )
    conn.commit()


def ensure_lubrication_schema(conn: sqlite3.Connection) -> None:
    value_defs = ",\n          ".join(
        f"{column} REAL" for column in LUBRICATION_COLUMNS
    )
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS LUBRICACIONES_LOCAL (
          uuid TEXT PRIMARY KEY, localizacion INTEGER, sistema TEXT,
          fecha TEXT, hora TEXT, {value_defs},
          observaciones TEXT, responsable TEXT, cargo TEXT,
          marca TEXT, modelo TEXT, serial TEXT, odt INTEGER,
          sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_LUBRICACIONES_PENDING
        ON LUBRICACIONES_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def _normalize_lubrication_row(row: dict) -> dict:
    normalized = {
        "uuid": row.get("uuid"),
        # Tambien en mayusculas: las tuplas *_INSERT_COLUMNS leen asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": row.get("fecha") or row.get("FECHA"),
        "HORA": row.get("hora") or row.get("HORA"),
        "SISTEMA": row.get("sistema") or row.get("SISTEMA"),
        "LOCALIZACION": row.get("localizacion") or row.get("LOCALIZACION"),
        "OBSERVACIONES": row.get("observaciones") or row.get("OBSERVACIONES") or "",
        "USUARIO": row.get("usuario") or row.get("USUARIO")
        or row.get("responsable") or row.get("RESPONSABLE") or "",
        "CARGO": row.get("cargo") or row.get("CARGO") or "",
        "MARCA": row.get("marca") or row.get("MARCA") or "",
        "MODELO": row.get("modelo") or row.get("MODELO") or "",
        "SERIAL": row.get("serial") or row.get("SERIAL") or "",
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }
    for column in LUBRICATION_COLUMNS:
        normalized[column] = row.get(column)
    return normalized


def fetch_pending_lubrications(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_lubrication_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM LUBRICACIONES_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [_normalize_lubrication_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_lubrication_insert_values(row: dict) -> tuple:
    normalized = _normalize_lubrication_row(row)
    return tuple(normalized.get(column) for column in LUBRICATION_INSERT_COLUMNS)


def ensure_coupling_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS CAMBIOS_COUPLING_LOCAL (
          uuid TEXT PRIMARY KEY, localizacion INTEGER NOT NULL, sistema TEXT,
          fecha TEXT NOT NULL, hora TEXT NOT NULL, observaciones TEXT,
          responsable TEXT, cargo TEXT, marca TEXT, modelo TEXT, serial TEXT,
          odt INTEGER, sincronizado INTEGER NOT NULL DEFAULT 0,
          error_sync TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    # Las crea la app, pero se declaran aqui tambien para que una tablet con
    # base vieja no llegue sin ellas al subir.
    for column in (
        "coupling INTEGER NOT NULL DEFAULT 0",
        "inserto INTEGER NOT NULL DEFAULT 0",
        "modelo_cplg TEXT",
    ):
        try:
            conn.execute(
                f"ALTER TABLE CAMBIOS_COUPLING_LOCAL ADD COLUMN {column}"
            )
        except sqlite3.OperationalError:
            pass  # ya existe
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_COUPLING_PENDING
        ON CAMBIOS_COUPLING_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def _bandera(value: object) -> int:
    """1 o 0. La tablet manda enteros, pero admite texto por si acaso."""
    if isinstance(value, bool):
        return 1 if value else 0
    try:
        return 1 if int(value or 0) == 1 else 0
    except (TypeError, ValueError):
        return 1 if str(value).strip().lower() in {"1", "true", "si"} else 0


def _normalize_coupling_row(row: dict) -> dict:
    return {
        "uuid": row.get("uuid"),
        "COUPLING": _bandera(row.get("coupling") or row.get("COUPLING")),
        "INSERTO": _bandera(row.get("inserto") or row.get("INSERTO")),
        "MODELO_CPLG": _clean_text(
            row.get("modelo_cplg") or row.get("MODELO_CPLG")
        ),
        # Tambien en mayusculas: COUPLING_INSERT_COLUMNS lee asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": row.get("fecha") or row.get("FECHA"),
        "HORA": row.get("hora") or row.get("HORA"),
        "SISTEMA": row.get("sistema") or row.get("SISTEMA"),
        "LOCALIZACION": row.get("localizacion") or row.get("LOCALIZACION"),
        "OBSERVACIONES": row.get("observaciones") or row.get("OBSERVACIONES") or "",
        "USUARIO": row.get("usuario") or row.get("USUARIO")
        or row.get("responsable") or row.get("RESPONSABLE") or "",
        "CARGO": row.get("cargo") or row.get("CARGO") or "",
        "MARCA": row.get("marca") or row.get("MARCA") or "",
        "MODELO": row.get("modelo") or row.get("MODELO") or "",
        "SERIAL": row.get("serial") or row.get("SERIAL") or "",
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }


def fetch_pending_coupling_changes(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_coupling_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM CAMBIOS_COUPLING_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [_normalize_coupling_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_coupling_insert_values(row: dict) -> tuple:
    normalized = _normalize_coupling_row(row)
    return tuple(normalized.get(column) for column in COUPLING_INSERT_COLUMNS)


def ensure_admin_log_schema(conn: sqlite3.Connection) -> None:
    """La bitacora del administrador en la tablet.

    El subidor puede toparse con una tablet cuya app todavia no creo la tabla
    —o que traiga la primera version, sin las columnas de sincronizacion—, y
    sin esto la consulta de pendientes reventaria y frenaria el resto de la
    subida.
    """
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS EVENTOS_ADMIN (
          uuid          TEXT PRIMARY KEY,
          fecha         TEXT NOT NULL,
          hora          TEXT NOT NULL,
          usuario       TEXT NOT NULL,
          cargo         TEXT,
          accion        TEXT NOT NULL,
          servicio      TEXT,
          localizacion  INTEGER,
          uuid_medicion TEXT,
          detalle       TEXT,
          sincronizado  INTEGER NOT NULL DEFAULT 0,
          error_sync    TEXT,
          created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    existentes = {
        str(row[1]) for row in conn.execute("PRAGMA table_info(EVENTOS_ADMIN)")
    }
    for columna, definicion in (
        ("cargo", "TEXT"),
        ("sincronizado", "INTEGER NOT NULL DEFAULT 0"),
        ("error_sync", "TEXT"),
        ("created_at", "TEXT"),
    ):
        if columna not in existentes:
            conn.execute(
                f"ALTER TABLE EVENTOS_ADMIN ADD COLUMN {columna} {definicion}"
            )
    conn.commit()


def _normalize_admin_event_row(row: dict) -> dict:
    def texto(clave: str) -> str | None:
        valor = row.get(clave) or row.get(clave.upper())
        if valor is None:
            return None
        limpio = str(valor).strip()
        return limpio or None

    return {
        "uuid": row.get("uuid") or row.get("UUID"),
        # Tambien en mayusculas: ADMIN_LOG_INSERT_COLUMNS lee asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": texto("fecha"),
        "HORA": texto("hora"),
        "USUARIO": texto("usuario") or "",
        "CARGO": texto("cargo"),
        "ACCION": texto("accion") or "",
        "SERVICIO": texto("servicio"),
        "LOCALIZACION": (
            row.get("localizacion")
            if row.get("localizacion") is not None
            else row.get("LOCALIZACION")
        ),
        "UUID_MEDICION": texto("uuid_medicion"),
        # El detalle es el "antes → despues" y puede ser largo; la columna es
        # TEXT en MariaDB, pero se recorta por si acaso.
        "DETALLE": (texto("detalle") or "")[:2000] or None,
        "TABLET": texto("tablet"),
    }


def fetch_pending_admin_events(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_admin_log_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM EVENTOS_ADMIN
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY fecha ASC, hora ASC
            """
        ).fetchall()
        return [_normalize_admin_event_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_admin_event_insert_values(row: dict, tablet: str = "") -> tuple:
    normalized = _normalize_admin_event_row(row)
    if tablet and not normalized.get("TABLET"):
        normalized["TABLET"] = tablet
    return tuple(normalized.get(column) for column in ADMIN_LOG_INSERT_COLUMNS)


def mark_admin_event_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_admin_log_schema(conn)
        conn.execute(
            """
            UPDATE EVENTOS_ADMIN
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def admin_event_exists(cursor, row: dict) -> bool:
    """El UUID del evento es unico en MOT_LOG_ADM: con eso basta para no
    duplicar si una subida se corta a la mitad y se reintenta."""
    cursor.execute(
        "SELECT ID FROM MOT_LOG_ADM WHERE UUID = %s LIMIT 1",
        (row.get("UUID"),),
    )
    return cursor.fetchone() is not None


def ensure_belt_schema(conn: sqlite3.Connection) -> None:
    """La tabla puede no existir si la tablet trae un APK anterior."""
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS AJUSTES_CORREA_LOCAL (
          uuid TEXT PRIMARY KEY, localizacion INTEGER NOT NULL, sistema TEXT,
          fecha TEXT NOT NULL, hora TEXT NOT NULL,
          ajustada INTEGER NOT NULL DEFAULT 0, tension REAL,
          observaciones TEXT, responsable TEXT, cargo TEXT,
          marca TEXT, modelo TEXT, serial TEXT, odt INTEGER,
          sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.commit()


def _normalize_belt_row(row: dict) -> dict:
    def texto(clave: str) -> str:
        valor = row.get(clave) or row.get(clave.upper()) or ""
        return str(valor).strip()

    # La tension es el unico decimal: viaja como numero, no como texto, para
    # que MOT_AJC_REG.TENSION (DECIMAL 10,2) la reciba tal cual.
    tension = row.get("tension")
    if tension is None:
        tension = row.get("TENSION")
    try:
        tension = None if tension in (None, "") else float(tension)
    except (TypeError, ValueError):
        tension = None

    return {
        "uuid": row.get("uuid") or row.get("UUID"),
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": texto("fecha"),
        "HORA": texto("hora"),
        "SISTEMA": texto("sistema"),
        "LOCALIZACION": (
            row.get("localizacion")
            if row.get("localizacion") is not None
            else row.get("LOCALIZACION")
        ),
        "TENSION": tension,
        # El "se ajusto o no" queda dicho en la observacion: MOT_AJC_REG no
        # tiene columna para la bandera y perderla dejaria el registro mudo.
        "OBSERVACIONES": _texto_ajuste_correa(row),
        "USUARIO": texto("responsable") or texto("usuario"),
        "CARGO": texto("cargo"),
        "MARCA": texto("marca"),
        "MODELO": texto("modelo"),
        "SERIAL": texto("serial"),
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }


def _texto_ajuste_correa(row: dict) -> str:
    ajustada = row.get("ajustada")
    if ajustada is None:
        ajustada = row.get("AJUSTADA")
    encabezado = "CORREA AJUSTADA" if int(ajustada or 0) == 1 else "CORREA REVISADA, SIN AJUSTE"
    observacion = str(row.get("observaciones") or row.get("OBSERVACIONES") or "").strip()
    return f"{encabezado}. {observacion}".strip() if observacion else encabezado


def fetch_pending_belt_adjustments(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_belt_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM AJUSTES_CORREA_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [_normalize_belt_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_belt_insert_values(row: dict) -> tuple:
    normalized = _normalize_belt_row(row)
    return tuple(normalized.get(column) for column in BELT_INSERT_COLUMNS)


def mark_belt_result(
    db_path: Path, uuid: str, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_belt_schema(conn)
        conn.execute(
            "UPDATE AJUSTES_CORREA_LOCAL SET sincronizado = ?, error_sync = ? "
            "WHERE uuid = ?",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def belt_adjustment_exists(cursor, row: dict) -> bool:
    cursor.execute(
        "SELECT ID FROM MOT_AJC_REG WHERE UUID = %s LIMIT 1", (row.get("UUID"),)
    )
    return cursor.fetchone() is not None


def ensure_work_order_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS ORDENES_TRABAJO_LOCAL (
          odt INTEGER PRIMARY KEY, fecha TEXT NOT NULL, hora TEXT NOT NULL,
          equipo TEXT, ubicacion INTEGER NOT NULL, code_conjunto INTEGER,
          vibracion INTEGER NOT NULL DEFAULT 0,
          temperatura INTEGER NOT NULL DEFAULT 0,
          alineacion INTEGER NOT NULL DEFAULT 0,
          lubricacion INTEGER NOT NULL DEFAULT 0,
          coupling_rpl INTEGER NOT NULL DEFAULT 0,
          correa_ajt INTEGER NOT NULL DEFAULT 0,
          reemplazo INTEGER NOT NULL DEFAULT 0,
          sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """CREATE INDEX IF NOT EXISTS IDX_ORDENES_TRABAJO_PENDING
        ON ORDENES_TRABAJO_LOCAL(sincronizado, created_at)"""
    )
    columns = {str(r[1]).lower() for r in conn.execute('PRAGMA table_info(ORDENES_TRABAJO_LOCAL)')}
    if 'limpieza_plato' not in columns:
        conn.execute('ALTER TABLE ORDENES_TRABAJO_LOCAL ADD COLUMN limpieza_plato INTEGER NOT NULL DEFAULT 0')
    if 'tablet_origen' not in columns:
        conn.execute('ALTER TABLE ORDENES_TRABAJO_LOCAL ADD COLUMN tablet_origen TEXT')
    conn.commit()


def fetch_pending_work_orders(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_work_order_schema(conn)
        rows = conn.execute(
            """SELECT * FROM ORDENES_TRABAJO_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0 ORDER BY created_at ASC"""
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def normalize_tablet_origin(value) -> str | None:
    if value is None:
        return None
    origin = str(value).strip()
    if not origin:
        return None
    if len(origin) > 100:
        raise ValueError('TABLET_ORIGEN supera los 100 caracteres; no se truncara el identificador.')
    return origin


def build_work_order_values(row: dict) -> tuple:
    return (
        row.get("odt"), row.get("fecha"), row.get("hora"), row.get("equipo"),
        row.get("ubicacion"), row.get("code_conjunto"),
        int(row.get("vibracion") or 0), int(row.get("temperatura") or 0),
        int(row.get("alineacion") or 0), int(row.get("lubricacion") or 0),
        int(row.get("coupling_rpl") or 0), int(row.get("correa_ajt") or 0),
        int(row.get("reemplazo") or 0),
        int(row.get("limpieza_plato") or 0),
        normalize_tablet_origin(row.get("tablet_origen")),
    )


def remap_local_odt(db_path: Path, old_odt: int, new_odt: int) -> None:
    conn = sqlite3.connect(db_path)
    try:
        tables = (
            "MEDICIONES_LOCAL", "TEMPERATURAS_LOCAL", "ALINEACIONES_LOCAL",
            "LUBRICACIONES_LOCAL", "CAMBIOS_COUPLING_LOCAL", "REEMPLAZOS_LOCAL",
            "LIMPIEZAS_PLATO_LOCAL",
            "AJUSTES_CORREA_LOCAL", "CHECKLIST_COMPRESOR_LOCAL",
            "CHECKLIST_BLACK_START_LOCAL",
        )
        for table in tables:
            exists = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                (table,),
            ).fetchone()
            if not exists:
                continue
            columns = {str(r[1]).lower() for r in conn.execute(f"PRAGMA table_info({table})")}
            if "odt" in columns:
                conn.execute(f"UPDATE {table} SET odt=? WHERE odt=?", (new_odt, old_odt))
        conn.execute(
            "UPDATE ORDENES_TRABAJO_LOCAL SET odt=? WHERE odt=?",
            (new_odt, old_odt),
        )
        conn.commit()
    finally:
        conn.close()


def _normalize_alignment_row(row: dict) -> dict:
    normalized = {
        "uuid": row.get("uuid"),
        # Tambien en mayusculas: las tuplas *_INSERT_COLUMNS leen asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": row.get("fecha") or row.get("FECHA"),
        "HORA": row.get("hora") or row.get("HORA"),
        "SISTEMA": row.get("sistema") or row.get("SISTEMA"),
        "LOCALIZACION": row.get("localizacion") or row.get("LOCALIZACION"),
        "OBSERVACIONES": row.get("observaciones") or row.get("OBSERVACIONES") or "",
        "USUARIO": row.get("usuario") or row.get("USUARIO") or row.get("responsable") or row.get("RESPONSABLE") or "",
        "CARGO": row.get("cargo") or row.get("CARGO") or "",
        "MARCA": row.get("marca") or row.get("MARCA") or "",
        "MODELO": row.get("modelo") or row.get("MODELO") or "",
        "SERIAL": row.get("serial") or row.get("SERIAL") or "",
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }
    for column in ALIGNMENT_COLUMNS:
        normalized[column] = row.get(column)
    return normalized


def fetch_pending_alignments(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_alignment_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM ALINEACIONES_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [_normalize_alignment_row(dict(row)) for row in rows]
    finally:
        conn.close()


def build_alignment_insert_values(row: dict) -> tuple:
    normalized = _normalize_alignment_row(row)
    return tuple(normalized.get(column) for column in ALIGNMENT_INSERT_COLUMNS)


def ensure_local_replacement_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS REEMPLAZOS_LOCAL (
          uuid            TEXT PRIMARY KEY,
          operation_uuid  TEXT NOT NULL,
          localizacion    INTEGER NOT NULL,
          code_conjunto   INTEGER NOT NULL,
          equipo          INTEGER NOT NULL,
          marca           TEXT NOT NULL,
          modelo          TEXT NOT NULL,
          serial          TEXT NOT NULL,
          actualizar_especificaciones INTEGER NOT NULL DEFAULT 0,
          voltaje         TEXT,
          corriente       TEXT,
          rpm             TEXT,
          sf              TEXT,
          hp              TEXT,
          frame           TEXT,
          brgs_drive      TEXT,
          brgs_opp        TEXT,
          ciclo           TEXT,
          arranque        TEXT,
          ph              TEXT,
          tension         TEXT,
          lubricacion     TEXT,
          odt             INTEGER,
          fecha           TEXT NOT NULL,
          hora            TEXT NOT NULL,
          sincronizado    INTEGER DEFAULT 0,
          error_sync      TEXT,
          created_at      TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    for column in (
        "actualizar_especificaciones INTEGER NOT NULL DEFAULT 0",
        "voltaje TEXT",
        "corriente TEXT",
        "rpm TEXT",
        "sf TEXT",
        "hp TEXT",
        "frame TEXT",
        "brgs_drive TEXT",
        "brgs_opp TEXT",
        "ciclo TEXT",
        "arranque TEXT",
        "ph TEXT",
        "tension TEXT",
        "lubricacion TEXT",
        "odt INTEGER",
        # Que se dano, con que estatus queda la pieza retirada y a donde va.
        # Las crea la app, pero se declaran aqui tambien para que una tablet
        # con base vieja no llegue sin ellas al subir.
        "motivo TEXT",
        "estado_saliente TEXT",
        "sitio_saliente TEXT",
    ):
        try:
            conn.execute(f"ALTER TABLE REEMPLAZOS_LOCAL ADD COLUMN {column}")
        except sqlite3.OperationalError:
            pass
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_REEMPLAZOS_PENDING
        ON REEMPLAZOS_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def fetch_pending_replacements(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_local_replacement_table(conn)
        rows = conn.execute(
            """
            SELECT *
            FROM REEMPLAZOS_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC, operation_uuid ASC, equipo ASC
            """
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def ensure_estado_changes_schema(conn: sqlite3.Connection) -> None:
    """Crea la tabla de cambios de estatus si la tablet no la trae todavia.

    El subidor puede toparse con una tablet cuya app aun no creo la tabla; sin
    este CREATE la consulta de pendientes reventaria y frenaria el resto de la
    sincronizacion.
    """
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS CAMBIOS_ESTADO_LOCAL (
          uuid          TEXT PRIMARY KEY,
          tipo          INTEGER NOT NULL,
          serial        TEXT NOT NULL,
          estado        TEXT NOT NULL,
          localizacion  TEXT,
          observaciones TEXT,
          usuario       TEXT,
          cargo         TEXT,
          fecha         TEXT NOT NULL,
          hora          TEXT NOT NULL,
          sincronizado  INTEGER NOT NULL DEFAULT 0,
          error_sync    TEXT,
          created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_CAMBIOS_ESTADO_PENDING
        ON CAMBIOS_ESTADO_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def fetch_pending_estado_changes(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_estado_changes_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM CAMBIOS_ESTADO_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def ensure_ordenes_reparacion_schema(conn: sqlite3.Connection) -> None:
    """Crea la cola local de ordenes de reparacion si la tablet no la trae.

    Igual que con los cambios de estatus: el subidor puede toparse con una
    tablet cuya app aun no creo la tabla, y sin este CREATE la consulta de
    pendientes reventaria y frenaria el resto de la sincronizacion.
    """
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS ORDENES_REPARACION_LOCAL (
          uuid              TEXT PRIMARY KEY,
          tipo              INTEGER NOT NULL,
          serial            TEXT NOT NULL,
          marca             TEXT,
          modelo            TEXT,
          ubicacion_origen  INTEGER,
          destino           TEXT,
          motivo            TEXT,
          fecha_salida      TEXT,
          hora_salida       TEXT,
          usuario_salida    TEXT,
          cargo_salida      TEXT,
          odt               INTEGER,
          estado_orden      TEXT NOT NULL DEFAULT 'ABIERTA',
          fecha_retorno     TEXT,
          hora_retorno      TEXT,
          usuario_cierre    TEXT,
          cargo_cierre      TEXT,
          trabajo_realizado TEXT,
          resultado         TEXT,
          ubicacion_final   TEXT,
          observaciones     TEXT,
          sincronizado      INTEGER NOT NULL DEFAULT 0,
          error_sync        TEXT,
          created_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS IDX_ORDENES_REPARACION_PENDING
        ON ORDENES_REPARACION_LOCAL(sincronizado, created_at)
        """
    )
    conn.commit()


def fetch_pending_ordenes_reparacion(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_ordenes_reparacion_schema(conn)
        rows = conn.execute(
            """
            SELECT * FROM ORDENES_REPARACION_LOCAL
            WHERE COALESCE(sincronizado, 0) = 0
            ORDER BY created_at ASC
            """
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def pending_rows_for_display(db_path: Path) -> list[dict]:
    rows = fetch_pending_measurements(db_path)
    for temperature in fetch_pending_temperatures(db_path):
        measured = [
            f"{column}={temperature[column]:g} °C"
            for column in TEMPERATURE_COLUMNS
            if float(temperature.get(column) or 0) != 0
        ]
        rows.append(
            {
                "LOCALIZACION": temperature.get("LOCALIZACION"),
                "FECHA": temperature.get("FECHA"),
                "HORA": temperature.get("HORA"),
                "RMS": None,
                "OBSERVACIONES": "Temperatura: " + (", ".join(measured) or "sin lecturas"),
            }
        )
    for alignment in fetch_pending_alignments(db_path):
        values = [
            f"{column}={alignment[column]:g}"
            for column in ALIGNMENT_COLUMNS
            if alignment.get(column) is not None
        ]
        rows.append(
            {
                "LOCALIZACION": alignment.get("LOCALIZACION"),
                "FECHA": alignment.get("FECHA"),
                "HORA": alignment.get("HORA"),
                "RMS": None,
                "OBSERVACIONES": "Alineacion: " + (", ".join(values) or "sin valores"),
            }
        )
    for coupling in fetch_pending_coupling_changes(db_path):
        rows.append(
            {
                "LOCALIZACION": coupling.get("LOCALIZACION"),
                "FECHA": coupling.get("FECHA"),
                "HORA": coupling.get("HORA"),
                "RMS": None,
                "OBSERVACIONES": "Cambio de coupling confirmado: "
                + (coupling.get("OBSERVACIONES") or "sin observaciones"),
            }
        )
    for replacement in fetch_pending_replacements(db_path):
        table_info = REPLACEMENT_TABLES.get(int(replacement.get("equipo") or 0))
        label = table_info[1] if table_info else "Componente"
        rows.append(
            {
                "LOCALIZACION": replacement.get("localizacion"),
                "FECHA": replacement.get("fecha"),
                "HORA": replacement.get("hora"),
                "RMS": None,
                "OBSERVACIONES": (
                    f"Reemplazo {label}: {replacement.get('marca')} "
                    f"{replacement.get('modelo')} / {replacement.get('serial')}"
                ),
            }
        )
    return rows


def _normalize_local_row(row: dict) -> dict:
    normalized = {
        "uuid": row.get("uuid"),
        # Tambien en mayusculas: las tuplas *_INSERT_COLUMNS leen asi las claves.
        "UUID": row.get("uuid") or row.get("UUID"),
        "FECHA": row.get("fecha") or row.get("FECHA"),
        "HORA": row.get("hora") or row.get("HORA"),
        "SISTEMA": row.get("sistema") or row.get("SISTEMA"),
        "LOCALIZACION": row.get("localizacion") or row.get("LOCALIZACION"),
        "RMS": row.get("RMS") if row.get("RMS") is not None else row.get("rms"),
        "OBSERVACIONES": row.get("observaciones") or row.get("OBSERVACIONES"),
        "USUARIO": (
            row.get("usuario")
            or row.get("USUARIO")
            or row.get("responsable")
            or row.get("RESPONSABLE")
            or ""
        ),
        "CARGO": row.get("cargo") or row.get("CARGO") or "",
        "MARCA": row.get("marca") or row.get("MARCA") or row.get("info_marca") or "",
        "MODELO": row.get("modelo") or row.get("MODELO") or row.get("info_modelo") or "",
        "SERIAL": row.get("serial") or row.get("SERIAL") or row.get("info_serial") or "",
        "ODT": row.get("odt") if row.get("odt") is not None else row.get("ODT"),
    }
    for column in MEASUREMENT_COLUMNS:
        normalized[column] = row.get(column)
    return normalized


def build_insert_values(row: dict) -> tuple:
    return tuple(row.get(column) for column in INSERT_COLUMNS)


def parse_measurement_datetime(fecha: object, hora: object) -> datetime:
    f = str(fecha or "").strip()
    h = str(hora or "").strip() or "00:00:00"
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%d/%m/%Y %H:%M:%S",
        "%d/%m/%Y %H:%M",
        "%d/%m/%y %H:%M:%S",
        "%d/%m/%y %H:%M",
    ):
        try:
            return datetime.strptime(f"{f} {h}", fmt)
        except ValueError:
            pass
    return datetime.fromtimestamp(0)


def _sqlite_value(value: object) -> object:
    if isinstance(value, Decimal):
        return float(value)
    return value


def _remote_measurement_key(row: dict) -> str:
    row_id = row.get("ID")
    if row_id not in (None, ""):
        return f"ID:{row_id}"
    return f"LOC:{row.get('LOCALIZACION')}|{row.get('FECHA')}|{row.get('HORA')}"


def _ensure_remote_measurement_tables(conn: sqlite3.Connection) -> None:
    measure_cols = ",\n        ".join(f"{col} REAL" for col in MEASUREMENT_COLUMNS)
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS MEDICIONES_REMOTAS (
          remote_key      TEXT PRIMARY KEY,
          id_remoto       INTEGER,
          localizacion    INTEGER NOT NULL,
          equipo          TEXT,
          tagname         TEXT,
          fecha           TEXT,
          hora            TEXT,
          fecha_hora_iso  TEXT,
          {measure_cols},
          RMS             REAL,
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          updated_at      TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    for column in ("responsable", "cargo", "marca", "modelo", "serial"):
        try:
            conn.execute(f"ALTER TABLE MEDICIONES_REMOTAS ADD COLUMN {column} TEXT")
        except sqlite3.OperationalError:
            pass
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS ULTIMA_LECTURA (
          localizacion    INTEGER PRIMARY KEY,
          fecha           TEXT,
          hora            TEXT,
          fecha_hora_iso  TEXT,
          {measure_cols},
          RMS             REAL
        )
        """
    )


def sync_latest_measurements_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            cur.execute(
                """
                SELECT
                    m.*,
                    e.EQUIPO AS equipo,
                    e.TAGNAME AS tagname
                FROM MOT_VIBR_MUES m
                LEFT JOIN MOT_EQUIPO e ON e.LOCALIZACION = m.LOCALIZACION
                """
            )
            rows = cur.fetchall()
    finally:
        maria.close()

    latest: dict[int, dict] = {}
    for row in rows:
        loc = int(row.get("LOCALIZACION") or 0)
        if loc <= 0:
            continue
        dt = parse_measurement_datetime(row.get("FECHA"), row.get("HORA"))
        row["_fecha_hora_iso"] = dt.isoformat(timespec="seconds")
        current = latest.get(loc)
        if current is None:
            latest[loc] = row
            continue
        current_dt = parse_measurement_datetime(current.get("FECHA"), current.get("HORA"))
        if dt > current_dt or (
            dt == current_dt and int(row.get("ID") or 0) > int(current.get("ID") or 0)
        ):
            latest[loc] = row

    conn = sqlite3.connect(db_path)
    try:
        _ensure_remote_measurement_tables(conn)
        conn.execute("DELETE FROM MEDICIONES_REMOTAS")
        conn.execute("DELETE FROM ULTIMA_LECTURA")

        remote_sql = f"""
            INSERT OR REPLACE INTO MEDICIONES_REMOTAS
            (remote_key, id_remoto, localizacion, equipo, tagname, fecha, hora,
             fecha_hora_iso, {",".join(MEASUREMENT_COLUMNS)}, RMS, observaciones,
             responsable, cargo, marca, modelo, serial)
            VALUES ({",".join(["?"] * (8 + len(MEASUREMENT_COLUMNS) + 7))})
        """
        ultima_sql = f"""
            INSERT OR REPLACE INTO ULTIMA_LECTURA
            (localizacion, fecha, hora, fecha_hora_iso,
             {",".join(MEASUREMENT_COLUMNS)}, RMS)
            VALUES ({",".join(["?"] * (4 + len(MEASUREMENT_COLUMNS) + 1))})
        """

        for row in rows:
            conn.execute(
                remote_sql,
                (
                    _remote_measurement_key(row),
                    _sqlite_value(row.get("ID")),
                    _sqlite_value(row.get("LOCALIZACION")),
                    row.get("equipo") or "",
                    row.get("tagname") or "",
                    row.get("FECHA") or "",
                    row.get("HORA") or "",
                    row.get("_fecha_hora_iso")
                    or parse_measurement_datetime(row.get("FECHA"), row.get("HORA")).isoformat(
                        timespec="seconds"
                    ),
                    *(_sqlite_value(row.get(col)) for col in MEASUREMENT_COLUMNS),
                    _sqlite_value(row.get("RMS")),
                    row.get("OBSERVACIONES") or "",
                    row.get("USUARIO") or row.get("RESPONSABLE") or "",
                    row.get("CARGO") or "",
                    row.get("MARCA") or "",
                    row.get("MODELO") or "",
                    row.get("SERIAL") or "",
                ),
            )

        for row in latest.values():
            conn.execute(
                ultima_sql,
                (
                    _sqlite_value(row.get("LOCALIZACION")),
                    row.get("FECHA") or "",
                    row.get("HORA") or "",
                    row.get("_fecha_hora_iso"),
                    *(_sqlite_value(row.get(col)) for col in MEASUREMENT_COLUMNS),
                    _sqlite_value(row.get("RMS")),
                ),
            )

        conn.commit()
        log(
            f"Ultimas mediciones actualizadas desde MariaDB: "
            f"{len(latest)} equipos, {len(rows)} filas historicas."
        )
        return len(latest)
    finally:
        conn.close()


def _ensure_remote_temperature_tables(conn: sqlite3.Connection) -> None:
    temperature_defs = ",\n          ".join(f"{column} REAL DEFAULT 0" for column in TEMPERATURE_COLUMNS)
    admin_defs = (
        ("sistema", "TEXT"),
        ("observaciones", "TEXT"),
        ("responsable", "TEXT"),
        ("cargo", "TEXT"),
        ("marca", "TEXT"),
        ("modelo", "TEXT"),
        ("serial", "TEXT"),
        ("odt", "INTEGER"),
    )
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS TEMPERATURAS_REMOTAS (
          remote_key      TEXT PRIMARY KEY,
          localizacion    INTEGER NOT NULL,
          sistema         TEXT,
          fecha           TEXT,
          hora            TEXT,
          fecha_hora_iso  TEXT,
          {temperature_defs},
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          odt             INTEGER
        )
        """
    )
    _ensure_sqlite_columns(
        conn,
        "TEMPERATURAS_REMOTAS",
        (
            ("sistema", "TEXT"),
            ("fecha_hora_iso", "TEXT"),
            *((column, "REAL DEFAULT 0") for column in TEMPERATURE_COLUMNS),
            *admin_defs,
        ),
    )
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS ULTIMA_TEMPERATURA (
          localizacion    INTEGER PRIMARY KEY,
          sistema         TEXT,
          fecha           TEXT,
          hora            TEXT,
          fecha_hora_iso  TEXT,
          {temperature_defs},
          observaciones   TEXT,
          responsable     TEXT,
          cargo           TEXT,
          marca           TEXT,
          modelo          TEXT,
          serial          TEXT,
          odt             INTEGER
        )
        """
    )
    _ensure_sqlite_columns(
        conn,
        "ULTIMA_TEMPERATURA",
        (
            ("sistema", "TEXT"),
            ("fecha", "TEXT"),
            ("hora", "TEXT"),
            ("fecha_hora_iso", "TEXT"),
            *((column, "REAL DEFAULT 0") for column in TEMPERATURE_COLUMNS),
            *admin_defs[1:],
        ),
    )


def _remote_temperature_key(row: dict) -> str:
    row_id = row.get("ID")
    if row_id not in (None, ""):
        return f"ID:{row_id}"
    return f"LOC:{row.get('LOCALIZACION')}|{row.get('FECHA')}|{row.get('HORA')}"


def sync_latest_temperatures_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    maria = connect_mariadb()
    try:
        with maria.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM MOT_TEMP_MUES
                ORDER BY COALESCE(STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
                                  STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')) DESC, ID DESC
                LIMIT 500
                """
            )
            history_rows = cursor.fetchall()
            cursor.execute(
                """
                SELECT ranked.*
                FROM (
                    SELECT
                        measurement.*,
                        ROW_NUMBER() OVER (
                            PARTITION BY LOCALIZACION
                            ORDER BY COALESCE(STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
                                              STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')) DESC, ID DESC
                        ) AS chronological_rank
                    FROM MOT_TEMP_MUES measurement
                ) ranked
                WHERE chronological_rank = 1
                """
            )
            latest_remote_rows = cursor.fetchall()
    finally:
        maria.close()

    remote_by_key = {
        _remote_temperature_key(row): row
        for row in (*history_rows, *latest_remote_rows)
    }
    rows = list(remote_by_key.values())
    latest: dict[int, dict] = {}
    for row in latest_remote_rows:
        loc = int(row.get("LOCALIZACION") or 0)
        if loc <= 0:
            continue
        measured_at = parse_measurement_datetime(row.get("FECHA"), row.get("HORA"))
        row["_fecha_hora_iso"] = measured_at.isoformat(timespec="seconds")
        current = latest.get(loc)
        if current is None:
            latest[loc] = row
            continue
        current_at = parse_measurement_datetime(current.get("FECHA"), current.get("HORA"))
        if measured_at > current_at or (
            measured_at == current_at
            and int(row.get("ID") or 0) > int(current.get("ID") or 0)
        ):
            latest[loc] = row

    common_columns = (
        "localizacion", "sistema", "fecha", "hora", "fecha_hora_iso",
        *TEMPERATURE_COLUMNS,
        "observaciones", "responsable", "cargo", "marca", "modelo", "serial", "odt",
    )
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        _ensure_remote_temperature_tables(conn)
        ensure_local_temperature_tables(conn)
        local_rows = [
            dict(row)
            for row in conn.execute(
                "SELECT * FROM TEMPERATURAS_LOCAL ORDER BY created_at ASC"
            ).fetchall()
        ]
        for local_row in local_rows:
            loc = int(local_row.get("localizacion") or 0)
            if loc <= 0:
                continue
            local_at = parse_measurement_datetime(
                local_row.get("fecha"), local_row.get("hora")
            )
            local_row["_fecha_hora_iso"] = local_at.isoformat(timespec="seconds")
            current = latest.get(loc)
            if current is None:
                latest[loc] = local_row
                continue
            current_at = parse_measurement_datetime(
                current.get("FECHA") or current.get("fecha"),
                current.get("HORA") or current.get("hora"),
            )
            is_pending = int(local_row.get("sincronizado") or 0) == 0
            if local_at > current_at or (local_at == current_at and is_pending):
                latest[loc] = local_row

        conn.execute("DELETE FROM TEMPERATURAS_REMOTAS")
        conn.execute("DELETE FROM ULTIMA_TEMPERATURA")
        remote_columns = ("remote_key", *common_columns)
        remote_sql = (
            f"INSERT OR REPLACE INTO TEMPERATURAS_REMOTAS ({','.join(remote_columns)}) "
            f"VALUES ({','.join(['?'] * len(remote_columns))})"
        )
        latest_sql = (
            f"INSERT OR REPLACE INTO ULTIMA_TEMPERATURA ({','.join(common_columns)}) "
            f"VALUES ({','.join(['?'] * len(common_columns))})"
        )

        def row_values(row: dict) -> tuple:
            normalized = _normalize_temperature_row(row)
            return (
                _sqlite_value(normalized.get("LOCALIZACION")),
                normalized.get("SISTEMA") or "",
                normalized.get("FECHA") or "",
                normalized.get("HORA") or "",
                row.get("_fecha_hora_iso")
                or parse_measurement_datetime(
                    normalized.get("FECHA"), normalized.get("HORA")
                ).isoformat(timespec="seconds"),
                *(_sqlite_value(normalized.get(column)) for column in TEMPERATURE_COLUMNS),
                normalized.get("OBSERVACIONES") or "",
                normalized.get("USUARIO") or "",
                normalized.get("CARGO") or "",
                normalized.get("MARCA") or "",
                normalized.get("MODELO") or "",
                normalized.get("SERIAL") or "",
                _sqlite_value(normalized.get("ODT")),
            )

        for row in rows:
            conn.execute(remote_sql, (_remote_temperature_key(row), *row_values(row)))
        for row in latest.values():
            conn.execute(latest_sql, row_values(row))
        conn.commit()
        log(
            "Temperaturas actualizadas desde MariaDB: "
            f"{len(latest)} equipos, {len(rows)} filas historicas."
        )
        return len(latest)
    finally:
        conn.close()


def sync_lubrication_history_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    """Baja el historial de lubricacion (MOT_LUB_REG) a LUBRICACIONES_REMOTAS.

    Era el unico servicio sin bajada por USB: la tabla remota solo se llenaba
    por la API WiFi, asi que en una tablet solo-USB el historial de
    lubricacion de los reportes salia vacio aunque MariaDB lo tuviera.
    """
    maria = connect_mariadb()
    try:
        with maria.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM MOT_LUB_REG
                ORDER BY COALESCE(STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
                                  STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')) DESC, ID DESC
                LIMIT 500
                """
            )
            rows = cursor.fetchall()
    finally:
        maria.close()

    conn = sqlite3.connect(db_path)
    try:
        # Mismo esquema que crea la app (db_helper._createLubricationTables).
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS LUBRICACIONES_REMOTAS (
              remote_key     TEXT PRIMARY KEY,
              localizacion   INTEGER NOT NULL,
              sistema        TEXT,
              fecha          TEXT,
              hora           TEXT,
              fecha_hora_iso TEXT,
              L1 REAL, L2 REAL, L3 REAL, L4 REAL, L5 REAL,
              L6 REAL, L7 REAL, L8 REAL, L9 REAL,
              observaciones  TEXT,
              responsable    TEXT,
              cargo          TEXT,
              marca          TEXT,
              modelo         TEXT,
              serial         TEXT,
              odt            INTEGER,
              updated_at     TEXT DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute("DELETE FROM LUBRICACIONES_REMOTAS")
        columnas = (
            "remote_key", "localizacion", "sistema", "fecha", "hora",
            "fecha_hora_iso", *LUBRICATION_COLUMNS,
            "observaciones", "responsable", "cargo",
            "marca", "modelo", "serial", "odt",
        )
        sql = (
            f"INSERT OR REPLACE INTO LUBRICACIONES_REMOTAS "
            f"({','.join(columnas)}) VALUES ({','.join(['?'] * len(columnas))})"
        )
        for row in rows:
            normalized = _normalize_lubrication_row(dict(row))
            iso = parse_measurement_datetime(
                normalized.get("FECHA"), normalized.get("HORA")
            ).isoformat(timespec="seconds")
            conn.execute(sql, (
                f"ID:{row.get('ID')}" if row.get("ID") not in (None, "")
                else f"LOC:{normalized.get('LOCALIZACION')}|"
                     f"{normalized.get('FECHA')}|{normalized.get('HORA')}",
                _sqlite_value(normalized.get("LOCALIZACION")),
                normalized.get("SISTEMA") or "",
                normalized.get("FECHA") or "",
                normalized.get("HORA") or "",
                iso,
                *(_sqlite_value(normalized.get(c)) for c in LUBRICATION_COLUMNS),
                normalized.get("OBSERVACIONES") or "",
                normalized.get("USUARIO") or "",
                normalized.get("CARGO") or "",
                normalized.get("MARCA") or "",
                normalized.get("MODELO") or "",
                normalized.get("SERIAL") or "",
                _sqlite_value(normalized.get("ODT")),
            ))
        conn.commit()
        log(f"Lubricaciones actualizadas desde MariaDB: {len(rows)} filas.")
        return len(rows)
    finally:
        conn.close()


def _remote_alignment_key(row: dict) -> str:
    if row.get("ID") not in (None, ""):
        return f"ID:{row.get('ID')}"
    return "|".join(str(part or "") for part in _alignment_measurement_signature(row))


def sync_alignment_history_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    maria = connect_mariadb()
    try:
        with maria.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM MOT_ALN_REG
                ORDER BY COALESCE(STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
                                  STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')) DESC, ID DESC
                LIMIT 500
                """
            )
            rows = cursor.fetchall()
    finally:
        maria.close()

    columns = (
        "remote_key", "localizacion", "sistema", "puntos", "fecha", "hora", "fecha_hora_iso",
        *ALIGNMENT_COLUMNS,
        "observaciones", "responsable", "cargo", "marca", "modelo", "serial", "odt",
    )
    conn = sqlite3.connect(db_path)
    try:
        ensure_alignment_schema(conn)
        conn.execute("DELETE FROM ALINEACIONES_REMOTAS")
        sql = (
            f"INSERT OR REPLACE INTO ALINEACIONES_REMOTAS ({','.join(columns)}) "
            f"VALUES ({','.join(['?'] * len(columns))})"
        )
        for row in rows:
            normalized = _normalize_alignment_row(row)
            puntos = 6 if any(
                normalized.get(column) is not None
                for column in ALIGNMENT_COLUMNS
                if column.startswith(("ACM_", "ACB_"))
            ) else 1
            conn.execute(
                sql,
                (
                    _remote_alignment_key(row),
                    _sqlite_value(normalized.get("LOCALIZACION")),
                    normalized.get("SISTEMA") or "",
                    puntos,
                    normalized.get("FECHA") or "",
                    normalized.get("HORA") or "",
                    parse_measurement_datetime(
                        normalized.get("FECHA"), normalized.get("HORA")
                    ).isoformat(timespec="seconds"),
                    *(_sqlite_value(normalized.get(column)) for column in ALIGNMENT_COLUMNS),
                    normalized.get("OBSERVACIONES") or "",
                    normalized.get("USUARIO") or "",
                    normalized.get("CARGO") or "",
                    normalized.get("MARCA") or "",
                    normalized.get("MODELO") or "",
                    normalized.get("SERIAL") or "",
                    _sqlite_value(normalized.get("ODT")),
                ),
            )
        conn.commit()
        log(f"Alineaciones historicas actualizadas desde MariaDB: {len(rows)} filas.")
        return len(rows)
    finally:
        conn.close()


def mark_local_result(db_path: Path, uuid: str, *, synced: bool, error: str | None = None) -> None:
    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            """
            UPDATE MEDICIONES_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_temperature_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_local_temperature_tables(conn)
        conn.execute(
            """
            UPDATE TEMPERATURAS_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_alignment_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_alignment_schema(conn)
        conn.execute(
            """
            UPDATE ALINEACIONES_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_lubrication_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_lubrication_schema(conn)
        conn.execute(
            """
            UPDATE LUBRICACIONES_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_coupling_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_coupling_schema(conn)
        conn.execute(
            """
            UPDATE CAMBIOS_COUPLING_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE uuid = ?
            """,
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_work_order_result(
    db_path: Path, odt: int, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_work_order_schema(conn)
        conn.execute(
            """UPDATE ORDENES_TRABAJO_LOCAL
            SET sincronizado=?, error_sync=? WHERE odt=?""",
            (1 if synced else 0, None if synced else error, odt),
        )
        conn.commit()
    finally:
        conn.close()


def mark_estado_change_result(
    db_path: Path, uuid: str, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_estado_changes_schema(conn)
        conn.execute(
            """UPDATE CAMBIOS_ESTADO_LOCAL
            SET sincronizado=?, error_sync=? WHERE uuid=?""",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def mark_orden_reparacion_result(
    db_path: Path, uuid: str, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_ordenes_reparacion_schema(conn)
        conn.execute(
            """UPDATE ORDENES_REPARACION_LOCAL
            SET sincronizado=?, error_sync=? WHERE uuid=?""",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def connect_mariadb():
    if pymysql is None:
        raise RuntimeError("Falta pymysql. Instale con: pip install pymysql")
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
        charset="utf8mb4",
        autocommit=False,
    )


def sync_equipo_info_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("ALTER TABLE EQUIPOS ADD COLUMN SUBSISTEMA TEXT")
    except sqlite3.OperationalError:
        pass
    try:
        # La app tambien la crea, pero el uploader puede correr contra una
        # tablet cuyo APK todavia no la conoce y el UPDATE de abajo fallaria.
        conn.execute("ALTER TABLE EQUIPOS ADD COLUMN FAMILIA_COMPAT INTEGER")
    except sqlite3.OperationalError:
        pass
    _ensure_sqlite_columns(
        conn,
        "EQUIPO_INFO",
        (
            ("brgs_drive", "TEXT"), ("brgs_opp", "TEXT"),
            ("lubricacion", "TEXT"), ("motores_lub", "TEXT"),
            ("cant_mot_lub", "REAL"), ("elec_mot_lub", "REAL"),
            ("man_mot_lub", "REAL"), ("elemento_lub", "TEXT"),
            ("cant_elem_lub", "REAL"), ("elec_elem_lub", "REAL"),
            ("man_elem_lub", "REAL"),
        ),
    )
    conn.commit()

    try:
        localizaciones = [
            int(row["LOCALIZACION"])
            for row in conn.execute(
                """
                SELECT DISTINCT LOCALIZACION
                FROM EQUIPOS
                WHERE LOCALIZACION IS NOT NULL AND LOCALIZACION > 0
                ORDER BY LOCALIZACION
                """
            )
        ]
        if not localizaciones:
            log("Catalogo tecnico: la tablet no tiene equipos locales.")
            return 0

        maria = connect_mariadb()
        try:
            # Antes de nada, traer los equipos que la planta tiene y la tablet
            # no. Sin esto la bajada era ciega a lo nuevo: partia de las
            # localizaciones que la tablet YA conocia y le pedia a MariaDB sus
            # datos, asi que un equipo dado de alta en la planta no entraba
            # nunca por mas veces que se sincronizara.
            with maria.cursor() as cur:
                cur.execute(
                    """
                    SELECT
                        e.ID, e.CODE_SYS, e.EQUIPO, e.LOCALIZACION,
                        e.CODE_QR, e.PUNTOS, e.TAGNAME,
                        e.NAME_SYS_2 AS subsistema,
                        e.FAMILIA_COMPAT,
                        s.SISTEMA AS sistema
                    FROM MOT_EQUIPO e
                    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
                    ORDER BY e.LOCALIZACION
                    """
                )
                catalogo = cur.fetchall() or []

            nuevos = 0
            conocidas = set(localizaciones)
            for fila in catalogo:
                try:
                    loc = int(fila.get("LOCALIZACION") or 0)
                except (TypeError, ValueError):
                    continue
                if loc <= 0 or loc in conocidas:
                    continue
                puntos = int(fila.get("PUNTOS") or 0)
                conn.execute(
                    """
                    INSERT OR REPLACE INTO EQUIPOS
                        (ID, CODE_SYS, EQUIPO, LOCALIZACION, QR_CODE, PUNTOS,
                         PT_EQ, SISTEMA, SUBSISTEMA, SCADA, FAMILIA_COMPAT)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        fila.get("ID"),
                        fila.get("CODE_SYS"),
                        _repair_text(str(fila.get("EQUIPO") or "").strip()),
                        loc,
                        _repair_text(str(fila.get("CODE_QR") or "").strip())
                        or str(loc),
                        puntos,
                        puntos,
                        _repair_text(str(fila.get("sistema") or "").strip()),
                        _repair_text(str(fila.get("subsistema") or "").strip()),
                        _repair_text(str(fila.get("TAGNAME") or "").strip()),
                        fila.get("FAMILIA_COMPAT"),
                    ),
                )
                localizaciones.append(loc)
                conocidas.add(loc)
                nuevos += 1
            if nuevos:
                conn.commit()
                log(f"Equipos nuevos bajados de la planta: {nuevos}")
            localizaciones.sort()

            placeholders = ",".join(["%s"] * len(localizaciones))
            with maria.cursor() as cur:
                # MOT_DATA guarda tambien los motores retirados de cada
                # ubicacion. El destino es INSERT OR REPLACE con localizacion
                # como clave, asi que sin ACTIVO = 1 ganaria una fila
                # cualquiera y la tablet mostraria una placa vieja sin avisar.
                cur.execute(
                    f"""
                    SELECT
                        UBICACION AS localizacion,
                        MARCA AS marca,
                        SERIAL AS serial,
                        MODELO AS modelo,
                        HP AS hp,
                        ARRANQUE AS start,
                        VOLTAJE AS volts,
                        CORRIENTE AS fla,
                        SF AS sf,
                        CICLO AS hz,
                        RPM AS rpm,
                        BRGS_DRIVE AS brgs_drive,
                        BRGS_OPP AS brgs_opp,
                        LUBRICACION AS lubricacion,
                        MOTORES_LUB AS motores_lub,
                        CANT_MOT_LUB AS cant_mot_lub,
                        ELEC_MOT_LUB AS elec_mot_lub,
                        MAN_MOT_LUB AS man_mot_lub,
                        ELEMENTO_LUB AS elemento_lub,
                        CANT_ELEM_LUB AS cant_elem_lub,
                        ELEC_ELEM_LUB AS elec_elem_lub,
                        MAN_ELEM_LUB AS man_elem_lub
                    FROM MOT_DATA
                    WHERE UBICACION IN ({placeholders}) AND ACTIVO = 1
                    """,
                    tuple(localizaciones),
                )
                rows = cur.fetchall()
                cur.execute(
                    f"""
                    SELECT
                        LOCALIZACION AS localizacion,
                        s.SISTEMA AS sistema,
                        e.NAME_SYS_2 AS subsistema,
                        e.FAMILIA_COMPAT AS familia_compat
                    FROM MOT_EQUIPO e
                    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
                    WHERE e.LOCALIZACION IN ({placeholders})
                    """,
                    tuple(localizaciones),
                )
                subsystem_rows = cur.fetchall()
        finally:
            maria.close()

        conn.executemany(
            """
            INSERT OR REPLACE INTO EQUIPO_INFO
            (localizacion, marca, serial, modelo, hp, start, volts, fla, sf, hz, rpm,
             brgs_drive, brgs_opp, lubricacion, motores_lub, cant_mot_lub,
             elec_mot_lub, man_mot_lub, elemento_lub, cant_elem_lub,
             elec_elem_lub, man_elem_lub)
            VALUES
            (:localizacion, :marca, :serial, :modelo, :hp, :start, :volts, :fla, :sf, :hz, :rpm,
             :brgs_drive, :brgs_opp, :lubricacion, :motores_lub, :cant_mot_lub,
             :elec_mot_lub, :man_mot_lub, :elemento_lub, :cant_elem_lub,
             :elec_elem_lub, :man_elem_lub)
            """,
            rows,
        )
        conn.commit()
        conn.executemany(
            """
            UPDATE EQUIPOS
            SET
              SISTEMA = COALESCE(:sistema, SISTEMA),
              SUBSISTEMA = :subsistema,
              -- Manda la planta: si alli le corrigieron la familia al equipo,
              -- la tablet tiene que quedarse con esa y no con la que tenia.
              FAMILIA_COMPAT = :familia_compat
            WHERE LOCALIZACION = :localizacion
            """,
            subsystem_rows,
        )
        conn.commit()
        count = len(rows)
        log(f"Catalogo tecnico actualizado desde MOT_DATA: {count} equipos.")
        return count
    finally:
        conn.close()


def sync_users_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            cur.execute(
                """
                SELECT ID AS id, USUARIO AS usuario, CARGO AS cargo,
                       COALESCE(ROL, '') AS rol
                FROM MDB_USERS
                WHERE COALESCE(TRIM(USUARIO), '') <> ''
                ORDER BY USUARIO
                """
            )
            rows = cur.fetchall()
    finally:
        maria.close()

    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS USUARIOS (
              id       INTEGER PRIMARY KEY,
              usuario  TEXT UNIQUE,
              cargo    TEXT,
              rol      TEXT
            )
            """
        )
        # Una tablet con el APK anterior no tiene la columna del rol.
        try:
            conn.execute("ALTER TABLE USUARIOS ADD COLUMN rol TEXT")
        except sqlite3.OperationalError:
            pass
        conn.execute("DELETE FROM USUARIOS")
        conn.executemany(
            """
            INSERT OR REPLACE INTO USUARIOS (id, usuario, cargo, rol)
            VALUES (:id, :usuario, :cargo, :rol)
            """,
            rows,
        )
        conn.commit()
        log(f"Usuarios actualizados desde MDB_USERS: {len(rows)} usuarios.")
        return len(rows)
    finally:
        conn.close()


def remote_measurement_exists(cursor, row: dict) -> bool:
    cursor.execute(
        """
        SELECT ID
        FROM MOT_VIBR_MUES
        WHERE LOCALIZACION = %s
          AND FECHA = %s
          AND HORA = %s
        LIMIT 1
        """,
        (row.get("LOCALIZACION"), row.get("FECHA"), row.get("HORA")),
    )
    return cursor.fetchone() is not None


def temperature_measurement_exists(cursor, row: dict) -> bool:
    selected_columns = (
        *TEMPERATURE_COLUMNS,
        "SISTEMA",
        "OBSERVACIONES",
        "USUARIO",
        "CARGO",
        "MARCA",
        "MODELO",
        "SERIAL",
        "ODT",
    )
    cursor.execute(
        f"""
        SELECT {','.join(selected_columns)}
        FROM MOT_TEMP_MUES
        WHERE LOCALIZACION = %s
          AND FECHA = %s
          AND HORA = %s
        """,
        (row.get("LOCALIZACION"), row.get("FECHA"), row.get("HORA")),
    )
    expected = _temperature_measurement_signature(row)
    return any(
        _temperature_measurement_signature(candidate) == expected
        for candidate in cursor.fetchall()
    )


def _temperature_measurement_signature(row: dict) -> tuple:
    temperatures: list[Decimal] = []
    for column in TEMPERATURE_COLUMNS:
        try:
            value = Decimal(str(row.get(column) if row.get(column) is not None else 0))
            temperatures.append(value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
        except (InvalidOperation, ValueError):
            temperatures.append(Decimal("0.00"))

    def normalized_text(*names: str) -> str:
        for name in names:
            value = row.get(name)
            if value not in (None, ""):
                return str(value).strip()
        return ""

    return (
        *temperatures,
        normalized_text("SISTEMA", "sistema"),
        normalized_text("OBSERVACIONES", "observaciones"),
        normalized_text("USUARIO", "usuario", "RESPONSABLE", "responsable"),
        normalized_text("CARGO", "cargo"),
        normalized_text("MARCA", "marca"),
        normalized_text("MODELO", "modelo"),
        normalized_text("SERIAL", "serial"),
        normalized_text("ODT", "odt"),
    )


def _alignment_measurement_signature(row: dict) -> tuple:
    def normalized_number(value: object) -> Decimal | None:
        if value is None or str(value).strip() == "":
            return None
        try:
            return Decimal(str(value).replace(",", ".")).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP
            )
        except (InvalidOperation, ValueError):
            return None

    def normalized_text(*names: str) -> str | None:
        for name in names:
            value = row.get(name)
            if value is not None:
                return " ".join(str(value).split()).casefold()
        return None

    return (
        normalized_text("LOCALIZACION", "localizacion"),
        normalized_text("FECHA", "fecha"),
        normalized_text("HORA", "hora"),
        *(normalized_number(row.get(column)) for column in ALIGNMENT_COLUMNS),
        normalized_text("SISTEMA", "sistema"),
        normalized_text("OBSERVACIONES", "observaciones"),
        normalized_text("USUARIO", "usuario", "RESPONSABLE", "responsable"),
        normalized_text("CARGO", "cargo"),
        normalized_text("MARCA", "marca"),
        normalized_text("MODELO", "modelo"),
        normalized_text("SERIAL", "serial"),
        normalized_text("ODT", "odt"),
    )


def alignment_measurement_exists(cursor, row: dict) -> bool:
    selected_columns = (
        "LOCALIZACION", "FECHA", "HORA", "SISTEMA", *ALIGNMENT_COLUMNS,
        "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
    )
    cursor.execute(
        f"""
        SELECT {','.join(selected_columns)}
        FROM MOT_ALN_REG
        WHERE LOCALIZACION = %s AND FECHA = %s AND HORA = %s
        """,
        (row.get("LOCALIZACION"), row.get("FECHA"), row.get("HORA")),
    )
    expected = _alignment_measurement_signature(row)
    return any(
        _alignment_measurement_signature(candidate) == expected
        for candidate in cursor.fetchall()
    )


def coupling_change_exists(cursor, row: dict) -> bool:
    cursor.execute(
        """
        SELECT ID FROM MOT_CPLG_REG
        WHERE LOCALIZACION = %s AND FECHA = %s AND HORA = %s
        LIMIT 1
        """,
        (row.get("LOCALIZACION"), row.get("FECHA"), row.get("HORA")),
    )
    return cursor.fetchone() is not None


def _uuid_bitacora(row: dict) -> str | None:
    """UUID que va a MOT_LOG_RPL.UUID, que es CHAR(36).

    Se prefiere `operation_uuid` porque identifica la operacion de reemplazo y
    mide exactamente 36. Si faltara, se recorta lo que haya: mas vale un
    identificador truncado que perder el registro entero por un 1406.
    """
    for clave in ("operation_uuid", "uuid"):
        texto = _replacement_text(row.get(clave))
        if texto:
            return texto[:36]
    return None


def _replacement_int(value: object) -> int | None:
    """ODT y demas enteros que pueden venir vacios desde la tablet."""
    texto = _replacement_text(value)
    if not texto:
        return None
    try:
        return int(float(texto))
    except (TypeError, ValueError):
        return None


def _replacement_text(value: object) -> str:
    return str(value or "").strip()


def _table_has_column(cursor, table: str, column: str) -> bool:
    """Dice si la maestra ya tiene esa columna.

    Las maestras estan desplegadas en varios servidores y no todas llevan aun
    LOCALIZACION (taller/almacen). Sin esta comprobacion el UPDATE de la pieza
    saliente reventaria y tumbaria la transaccion completa del reemplazo.
    """
    cursor.execute(
        """
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
          AND UPPER(COLUMN_NAME) = %s
        """,
        (table, column.upper()),
    )
    return cursor.fetchone() is not None


def apply_replacement_row(
    cursor,
    row: dict,
    *,
    usuario: str = "",
    cargo: str = "",
) -> str:
    equipment_type = int(row.get("equipo") or 0)
    table_info = REPLACEMENT_TABLES.get(equipment_type)
    if table_info is None:
        raise ValueError(f"Tipo de equipo invalido: {equipment_type}")

    table, label = table_info
    localizacion = int(row.get("localizacion") or 0)
    code_conjunto = int(row.get("code_conjunto") or 0)
    marca = _replacement_text(row.get("marca"))
    modelo = _replacement_text(row.get("modelo"))
    serial = _replacement_text(row.get("serial"))
    fecha = _replacement_text(row.get("fecha"))
    hora = _replacement_text(row.get("hora"))
    if localizacion <= 0 or code_conjunto <= 0:
        raise ValueError("UBICACION y CODE_CONJUNTO deben ser mayores que cero")
    if not marca or not modelo or not serial:
        raise ValueError(f"Marca, modelo y serial son obligatorios para {label}")

    update_technical_specs = (
        equipment_type == 1
        and str(row.get("actualizar_especificaciones") or "0").strip().lower()
        in {"1", "true", "si", "yes"}
    )
    selected_columns = ["MARCA", "MODELO", "SERIAL"]
    new_values_by_column = {
        "MARCA": marca,
        "MODELO": modelo,
        "SERIAL": serial,
    }
    if update_technical_specs:
        for local_column, remote_column in MOTOR_TECHNICAL_FIELDS:
            selected_columns.append(remote_column)
            new_values_by_column[remote_column] = _replacement_text(
                row.get(local_column)
            )

    # Que hace el tecnico con la pieza que sale: en que estado la deja y a que
    # taller o almacen la manda. Si la app es vieja y no los envia, la pieza se
    # da por buena y sin sitio asignado.
    estado_saliente = (
        _replacement_text(row.get("estado_saliente")).upper() or "DISPONIBLE"
    )
    sitio_saliente = _replacement_text(row.get("sitio_saliente")) or None
    tiene_localizacion = _table_has_column(cursor, table, "LOCALIZACION")

    def instalar_pieza_entrante() -> str:
        """Da de alta o reactiva la fila de la pieza que entra.

        La identidad de la pieza es el SERIAL, nunca la posicion: por eso se
        busca primero. Si esa pieza ya estuvo en planta se reutiliza su fila,
        de modo que jamas haya dos filas con el mismo serial.
        """
        cursor.execute(
            f"""
            SELECT ID
            FROM `{table}`
            WHERE UPPER(TRIM(SERIAL)) = %s
            ORDER BY ACTIVO DESC, ID ASC
            LIMIT 1
            FOR UPDATE
            """,
            (serial.upper(),),
        )
        existente = cursor.fetchone()
        if not existente:
            # Pieza nueva para la planta: este insert es su alta.
            insert_columns = [
                "FECHA",
                "HORA",
                *selected_columns,
                "UBICACION",
                "CODE_CONJUNTO",
                "ACTIVO",
                "ESTADO",
            ]
            insert_values = [
                fecha,
                hora,
                *(new_values_by_column[column] for column in selected_columns),
                localizacion,
                code_conjunto,
                1,
                "INSTALADO",
            ]
            cursor.execute(
                f"""
                INSERT INTO `{table}`
                  ({", ".join(insert_columns)})
                VALUES ({", ".join(["%s"] * len(insert_columns))})
                """,
                tuple(insert_values),
            )
            return "created"

        assignments = [
            "FECHA = %s",
            "HORA = %s",
            "UBICACION = %s",
            "CODE_CONJUNTO = %s",
            "ACTIVO = 1",
            "ESTADO = %s",
        ]
        update_values = [fecha, hora, localizacion, code_conjunto, "INSTALADO"]
        for column in selected_columns:
            assignments.append(f"`{column}` = %s")
            update_values.append(new_values_by_column[column])
        if tiene_localizacion:
            # Vuelve a un equipo, asi que ya no esta en ningun taller ni almacen.
            assignments.append("LOCALIZACION = NULL")
        update_values.append(existente["ID"])
        cursor.execute(
            f"UPDATE `{table}` SET {', '.join(assignments)} WHERE ID = %s",
            tuple(update_values),
        )
        return "updated"

    # FECHA se lee ademas de la placa: es cuando se instalo la pieza que sale,
    # y junto a la fecha de retiro da el tiempo que estuvo en servicio.
    cursor.execute(
        f"""
        SELECT ID, FECHA AS FECHA_INSTALADA, {", ".join(selected_columns)}
        FROM `{table}`
        WHERE UBICACION = %s AND CODE_CONJUNTO = %s AND ACTIVO = 1
        LIMIT 1
        FOR UPDATE
        """,
        (localizacion, code_conjunto),
    )
    current = cursor.fetchone()
    if not current:
        # La posicion esta vacia: no hay nada que retirar ni que anotar en la
        # bitacora, solo se instala la pieza.
        return instalar_pieza_entrante()

    current_values = tuple(
        _replacement_text(current.get(key)).upper()
        for key in selected_columns
    )
    new_values = tuple(
        new_values_by_column[key].upper() for key in selected_columns
    )
    if current_values == new_values:
        return "skipped"

    # La bitacora guarda la pieza que SALE con todo su contexto: quien lo hizo,
    # bajo que ODT, que se daño, en que estado quedo y a donde fue. Antes solo
    # se escribian las 8 primeras y el resto quedaba en NULL, asi que el
    # historial no servia para auditar nada.
    cursor.execute(
        """
        INSERT INTO MOT_LOG_RPL
          (FECHA, HORA, MARCA, MODELO, SERIAL, EQUIPO, UBICACION, CODE_CONJUNTO,
           ODT, USUARIO, CARGO, MOTIVO, LOCALIZACION, ESTADO,
           FECHA_INSTALACION, OBSERVACIONES, UUID)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            fecha,
            hora,
            current.get("MARCA"),
            current.get("MODELO"),
            current.get("SERIAL"),
            equipment_type,
            localizacion,
            code_conjunto,
            _replacement_int(row.get("odt")),
            _replacement_text(row.get("usuario")) or usuario or None,
            _replacement_text(row.get("cargo")) or cargo or None,
            _replacement_text(row.get("motivo")) or None,
            sitio_saliente,
            estado_saliente,
            _replacement_text(current.get("FECHA_INSTALADA")) or None,
            _replacement_text(row.get("observaciones")) or None,
            # operation_uuid, no uuid: la app le agrega un sufijo por
            # componente al uuid de la fila ("...-1", "...-2"), asi que mide 38
            # y no cabe en el CHAR(36) de la bitacora. Ademas el evento que se
            # registra es la operacion de reemplazo, no cada componente suelto.
            _uuid_bitacora(row),
        ),
    )

    if _replacement_text(current.get("SERIAL")).upper() == serial.upper():
        # Mismo serial: no hubo permuta, el tecnico corrigio la placa o las
        # especificaciones. Se edita la misma fila; retirarla y crear otra
        # duplicaria el serial, que es justo lo que el modelo prohibe.
        assignments = ["FECHA = %s", "HORA = %s"]
        update_values = [fecha, hora]
        for column in selected_columns:
            assignments.append(f"`{column}` = %s")
            update_values.append(new_values_by_column[column])
        update_values.append(current["ID"])
        cursor.execute(
            f"UPDATE `{table}` SET {', '.join(assignments)} WHERE ID = %s",
            tuple(update_values),
        )
        return "updated"

    # Permuta real. La pieza que sale conserva su fila como historico: solo se
    # desactiva y se le anota el destino. No se le tocan FECHA ni HORA porque
    # son las de su instalacion, y la salida ya quedo en MOT_LOG_RPL.
    assignments = ["ACTIVO = 0", "ESTADO = %s"]
    update_values = [estado_saliente]
    if tiene_localizacion:
        assignments.append("LOCALIZACION = %s")
        update_values.append(sitio_saliente)
    update_values.append(current["ID"])
    cursor.execute(
        f"UPDATE `{table}` SET {', '.join(assignments)} WHERE ID = %s",
        tuple(update_values),
    )
    return instalar_pieza_entrante()


def apply_estado_change(cursor, row: dict) -> str:
    """Aplica en la maestra un cambio de estatus hecho a mano en la tablet.

    Es un movimiento de inventario, no una permuta: por eso no escribe nada en
    MOT_LOG_RPL, que es la bitacora de reemplazos.
    """
    tipo = int(row.get("tipo") or 0)
    table_info = REPLACEMENT_TABLES.get(tipo)
    if table_info is None:
        raise ValueError(f"Tipo de pieza invalido: {tipo}")

    table, label = table_info
    serial = _replacement_text(row.get("serial"))
    estado = _replacement_text(row.get("estado")).upper()
    localizacion = _replacement_text(row.get("localizacion")) or None
    fecha = _replacement_text(row.get("fecha"))
    hora = _replacement_text(row.get("hora"))
    if not serial:
        raise ValueError(f"El serial es obligatorio para cambiar el estatus de {label}")
    if estado not in ESTADO_CHANGE_ALLOWED:
        raise ValueError(
            f"Estatus invalido para {label} {serial}: '{estado or '(vacio)'}'. "
            f"Solo se admite {', '.join(ESTADO_CHANGE_ALLOWED)}"
        )

    # La identidad de la pieza es el SERIAL. Se prefiere la fila activa por si
    # quedo alguna fila vieja del mismo serial, para no juzgar el caso con un
    # historico y terminar cambiandole el estatus a una pieza que si esta puesta.
    cursor.execute(
        f"""
        SELECT ID, ACTIVO, UBICACION, ESTADO
        FROM `{table}`
        WHERE UPPER(TRIM(SERIAL)) = %s
        ORDER BY ACTIVO DESC, ID DESC
        LIMIT 1
        FOR UPDATE
        """,
        (serial.upper(),),
    )
    current = cursor.fetchone()
    if not current:
        # No se da de alta desde aqui: un alta sin reemplazo dejaria una pieza
        # sin equipo ni historia, y el serial podria venir de un tipeo malo.
        raise ValueError(
            f"No existe ningun {label} con serial {serial} en {table}; "
            "registre primero el reemplazo que la puso en planta"
        )

    if int(current.get("ACTIVO") or 0) == 1:
        # Pieza instalada: se respeta lo que diga el reemplazo. Cambiarle el
        # estatus aqui la dejaria marcada como averiada o desechada mientras
        # sigue montada en el equipo.
        raise ValueError(
            f"{label} {serial} esta instalado en la ubicacion "
            f"{current.get('UBICACION')}; registre el reemplazo que lo retira "
            "antes de cambiarle el estatus"
        )

    assignments = ["ESTADO = %s", "FECHA = %s", "HORA = %s"]
    update_values: list[object] = [estado, fecha, hora]
    # No todas las maestras llevan LOCALIZACION (taller/almacen); sin comprobarlo
    # el UPDATE reventaria en los servidores que aun no la tienen.
    if localizacion is not None and _table_has_column(cursor, table, "LOCALIZACION"):
        assignments.append("LOCALIZACION = %s")
        update_values.append(localizacion)
    update_values.append(current["ID"])
    cursor.execute(
        f"UPDATE `{table}` SET {', '.join(assignments)} WHERE ID = %s",
        tuple(update_values),
    )
    return "updated"


def _aplicar_estatus_orden(
    cursor,
    *,
    table: str,
    pieza_id: object,
    estado: str,
    localizacion: str | None,
    fecha: str,
    hora: str,
) -> None:
    """Escribe en la maestra el estatus que impone la orden de reparacion.

    Nunca toca ACTIVO ni UBICACION: que una pieza este montada en un equipo lo
    decide solo el reemplazo. Una orden manda la pieza al taller, no la
    desinstala del equipo.
    """
    assignments = ["ESTADO = %s", "FECHA = %s", "HORA = %s"]
    update_values: list[object] = [estado, fecha, hora]
    # No todas las maestras desplegadas llevan LOCALIZACION (taller/almacen);
    # sin comprobarlo el UPDATE reventaria y tumbaria toda la transaccion.
    if localizacion is not None and _table_has_column(cursor, table, "LOCALIZACION"):
        assignments.append("LOCALIZACION = %s")
        update_values.append(localizacion)
    update_values.append(pieza_id)
    cursor.execute(
        f"UPDATE `{table}` SET {', '.join(assignments)} WHERE ID = %s",
        tuple(update_values),
    )


def apply_orden_reparacion(cursor, row: dict) -> str:
    """Sube a MOT_ORD_REP una orden creada sin señal y ajusta la maestra.

    La tablet puede haber abierto Y cerrado la orden antes de ver un cable, asi
    que la fila local trae el estado final: por eso es un UPSERT por UUID y no
    un simple INSERT. El UUID es la identidad de la orden; reintentar la subida
    no puede crear una segunda orden para la misma salida de la misma pieza.

    No escribe en MOT_LOG_RPL: esa es la bitacora de permutas y mandar una
    pieza al taller no es una permuta.
    """
    tipo = int(row.get("tipo") or 0)
    table_info = REPLACEMENT_TABLES.get(tipo)
    if table_info is None:
        raise ValueError(f"Tipo de pieza invalido: {tipo}")

    table, label = table_info
    orden_uuid = _replacement_text(row.get("uuid"))
    serial = _replacement_text(row.get("serial"))
    destino = _replacement_text(row.get("destino")).upper()
    estado_orden = _replacement_text(row.get("estado_orden")).upper() or "ABIERTA"
    if not orden_uuid:
        raise ValueError("La orden de reparacion no trae UUID")
    if not serial:
        raise ValueError(f"El serial es obligatorio para la orden de {label}")
    if destino not in DESTINOS_REPARACION:
        raise ValueError(
            f"Destino invalido para {label} {serial}: '{destino or '(vacio)'}'. "
            f"Solo se admite {', '.join(DESTINOS_REPARACION)}"
        )
    if estado_orden not in {"ABIERTA", "CERRADA"}:
        raise ValueError(
            f"Estado de orden invalido para {label} {serial}: '{estado_orden}'"
        )

    resultado = _replacement_text(row.get("resultado")).upper()
    estado_final = ""
    if estado_orden == "CERRADA":
        if resultado not in RESULTADOS_REPARACION:
            raise ValueError(
                f"Resultado invalido al cerrar la orden de {label} {serial}: "
                f"'{resultado or '(vacio)'}'. Solo se admite "
                f"{', '.join(sorted(RESULTADOS_REPARACION))}"
            )
        estado_final = RESULTADOS_REPARACION[resultado]

    # La pieza se valida ANTES de tocar MOT_ORD_REP: si la orden es invalida no
    # queda ni la mitad escrita en la base, aunque el commit sea por fila.
    cursor.execute(
        f"""
        SELECT ID, ACTIVO, UBICACION, ESTADO
        FROM `{table}`
        WHERE UPPER(TRIM(SERIAL)) = %s
        ORDER BY ACTIVO DESC, ID DESC
        LIMIT 1
        FOR UPDATE
        """,
        (serial.upper(),),
    )
    pieza = cursor.fetchone()
    if not pieza:
        # No se da de alta desde aqui: un alta sin reemplazo dejaria una pieza
        # sin equipo ni historia, y el serial podria venir de un tipeo malo.
        raise ValueError(
            f"No existe ningun {label} con serial {serial} en {table}; "
            "registre primero el reemplazo que la puso en planta"
        )
    if int(pieza.get("ACTIVO") or 0) == 1:
        # Pieza instalada: no puede estar en el taller y montada a la vez.
        # Retirarla es trabajo del reemplazo, no de una orden de reparacion.
        raise ValueError(
            f"{label} {serial} esta instalado en la ubicacion "
            f"{pieza.get('UBICACION')}; registre el reemplazo que lo retira "
            "antes de mandarlo a reparacion"
        )

    fecha_salida = _replacement_text(row.get("fecha_salida"))
    hora_salida = _replacement_text(row.get("hora_salida"))
    fecha_retorno = _replacement_text(row.get("fecha_retorno"))
    hora_retorno = _replacement_text(row.get("hora_retorno"))
    ubicacion_final = _replacement_text(row.get("ubicacion_final")) or None

    campos = (
        "EQUIPO", "SERIAL", "MARCA", "MODELO", "UBICACION_ORIGEN", "DESTINO",
        "MOTIVO", "FECHA_SALIDA", "HORA_SALIDA", "USUARIO_SALIDA",
        "CARGO_SALIDA", "ODT", "ESTADO_ORDEN", "FECHA_RETORNO", "HORA_RETORNO",
        "USUARIO_CIERRE", "CARGO_CIERRE", "TRABAJO", "RESULTADO",
        "UBICACION_FINAL", "OBSERVACIONES",
    )
    valores = (
        str(tipo),
        serial,
        _replacement_text(row.get("marca")) or None,
        _replacement_text(row.get("modelo")) or None,
        _replacement_int(row.get("ubicacion_origen")),
        destino,
        _replacement_text(row.get("motivo")) or None,
        fecha_salida or None,
        hora_salida or None,
        _replacement_text(row.get("usuario_salida")) or None,
        _replacement_text(row.get("cargo_salida")) or None,
        _replacement_int(row.get("odt")),
        estado_orden,
        fecha_retorno or None,
        hora_retorno or None,
        _replacement_text(row.get("usuario_cierre")) or None,
        _replacement_text(row.get("cargo_cierre")) or None,
        _replacement_text(row.get("trabajo_realizado")) or None,
        resultado or None,
        ubicacion_final,
        _replacement_text(row.get("observaciones")) or None,
    )

    cursor.execute(
        "SELECT ID FROM MOT_ORD_REP WHERE UUID = %s LIMIT 1 FOR UPDATE",
        (orden_uuid,),
    )
    existente = cursor.fetchone()
    if existente:
        # La orden ya subio antes (por ejemplo abierta) y ahora llega cerrada:
        # se actualiza en sitio para no duplicar la salida de la pieza.
        asignaciones = ", ".join(f"{campo} = %s" for campo in campos)
        cursor.execute(
            f"UPDATE MOT_ORD_REP SET {asignaciones} WHERE ID = %s",
            (*valores, existente["ID"]),
        )
        outcome = "updated"
    else:
        marcas = ", ".join(["%s"] * (len(campos) + 1))
        cursor.execute(
            f"INSERT INTO MOT_ORD_REP (UUID, {', '.join(campos)}) VALUES ({marcas})",
            (orden_uuid, *valores),
        )
        outcome = "created"

    if estado_orden == "ABIERTA":
        # Mientras la orden vive, la pieza esta EN REPARACION y su sitio es el
        # taller al que se mando: el inventario debe poder decir donde esta sin
        # tener que abrir la orden.
        _aplicar_estatus_orden(
            cursor,
            table=table,
            pieza_id=pieza["ID"],
            estado=ESTADO_EN_REPARACION,
            localizacion=destino,
            fecha=fecha_salida,
            hora=hora_salida,
        )
    else:
        _aplicar_estatus_orden(
            cursor,
            table=table,
            pieza_id=pieza["ID"],
            estado=estado_final,
            localizacion=ubicacion_final,
            fecha=fecha_retorno or fecha_salida,
            hora=hora_retorno or hora_salida,
        )
    return outcome


def mark_replacement_operation_result(
    db_path: Path,
    operation_uuid: str,
    *,
    synced: bool,
    error: str | None = None,
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_local_replacement_table(conn)
        conn.execute(
            """
            UPDATE REEMPLAZOS_LOCAL
            SET sincronizado = ?, error_sync = ?
            WHERE operation_uuid = ?
            """,
            (1 if synced else 0, None if synced else error, operation_uuid),
        )
        conn.commit()
    finally:
        conn.close()


def upload_pending_replacements(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_replacements(db_path)
    summary = UploadSummary(total=len(rows))
    if not rows:
        log("No hay reemplazos pendientes.")
        return summary

    grouped: dict[str, list[dict]] = {}
    for row in rows:
        grouped.setdefault(str(row.get("operation_uuid") or row.get("uuid")), []).append(row)

    try:
        db = connect_mariadb()
    except Exception as exc:
        summary.failed = len(rows)
        message = f"No se pudo conectar a MariaDB para subir reemplazos: {exc}"
        summary.messages.append(message)
        log(message)
        return summary

    try:
        with db.cursor() as cursor:
            for operation_uuid, operation_rows in grouped.items():
                try:
                    outcomes = [
                        apply_replacement_row(
                            cursor,
                            row,
                            usuario=default_responsable,
                            cargo=default_cargo,
                        )
                        for row in operation_rows
                    ]
                    db.commit()
                    mark_replacement_operation_result(
                        db_path,
                        operation_uuid,
                        synced=True,
                    )
                    uploaded = sum(outcome != "skipped" for outcome in outcomes)
                    skipped = len(outcomes) - uploaded
                    summary.uploaded += uploaded
                    summary.skipped += skipped
                    message = (
                        f"Reemplazo confirmado: operacion {operation_uuid}, "
                        f"{uploaded} guardados, {skipped} ya existentes"
                    )
                    summary.messages.append(message)
                    log(message)
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_replacement_operation_result(
                        db_path,
                        operation_uuid,
                        synced=False,
                        error=error[:500],
                    )
                    summary.failed += len(operation_rows)
                    message = f"Error subiendo reemplazo {operation_uuid}: {error}"
                    summary.messages.append(message)
                    log(message)
    finally:
        db.close()
    return summary


def upload_estado_changes(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_estado_changes(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Cambios de estatus pendientes: {len(rows)}")
    if not rows:
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_estado_change_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir cambios de estatus: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                label = (
                    f"{uuid} tipo-{row.get('tipo')} "
                    f"serial {row.get('serial')} -> {row.get('estado')}"
                )
                # Cada cambio va con su propio commit/rollback: son movimientos
                # independientes y una pieza rechazada no debe tumbar a las demas.
                try:
                    apply_estado_change(cursor, row)
                    db.commit()
                    mark_estado_change_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Cambio de estatus aplicado: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_estado_change_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo cambio de estatus {label}: {error}")
    finally:
        db.close()
    return summary


EQUIPOS_NUEVOS_TABLE = "EQUIPOS_NUEVOS_LOCAL"


def ensure_equipos_nuevos_schema(conn: sqlite3.Connection) -> None:
    """La tabla puede no existir si la tablet trae un APK anterior."""
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {EQUIPOS_NUEVOS_TABLE} (
            uuid            TEXT PRIMARY KEY,
            localizacion    INTEGER NOT NULL UNIQUE,
            equipo          TEXT NOT NULL,
            code_sys        INTEGER NOT NULL,
            sistema         TEXT,
            subsistema      TEXT,
            tagname         TEXT,
            code_qr         TEXT,
            pt_eq           INTEGER NOT NULL,
            code_conjunto   INTEGER,
            familia_compat  INTEGER,
            marca           TEXT, modelo TEXT, serial TEXT, hp TEXT,
            arranque        TEXT, voltaje TEXT, corriente TEXT, sf TEXT,
            ciclo           TEXT, ph TEXT, rpm TEXT, frame TEXT,
            brgs_drive      TEXT, brgs_opp TEXT,
            lubricacion     TEXT, motores_lub TEXT,
            cant_mot_lub    REAL, elec_mot_lub REAL, man_mot_lub REAL,
            elemento_lub    TEXT,
            cant_elem_lub   REAL, elec_elem_lub REAL, man_elem_lub REAL,
            sin_lubricacion INTEGER NOT NULL DEFAULT 0,
            piezas_json     TEXT,
            usuario         TEXT, cargo TEXT,
            fecha           TEXT NOT NULL, hora TEXT NOT NULL,
            sincronizado    INTEGER NOT NULL DEFAULT 0,
            error_sync      TEXT,
            created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.commit()


def fetch_pending_equipos_nuevos(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_equipos_nuevos_schema(conn)
        rows = conn.execute(
            f"SELECT * FROM {EQUIPOS_NUEVOS_TABLE} "
            "WHERE sincronizado = 0 ORDER BY created_at ASC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def mark_equipo_nuevo_result(
    db_path: Path,
    uuid: str,
    *,
    synced: bool,
    error: str | None = None,
    localizacion: int | None = None,
) -> None:
    """Marca el resultado y, si hubo que renumerar, corrige la localizacion.

    La renumeracion tiene que bajar a la tablet: el equipo ya se ve en su lista
    con el numero viejo, y si no se actualiza quedaria apuntando a una
    LOCALIZACION que en la planta es de otro equipo.
    """
    conn = sqlite3.connect(db_path)
    try:
        ensure_equipos_nuevos_schema(conn)
        if synced and localizacion is not None:
            anterior = conn.execute(
                f"SELECT localizacion FROM {EQUIPOS_NUEVOS_TABLE} WHERE uuid=?",
                (uuid,),
            ).fetchone()
            previa = int(anterior[0]) if anterior else None
            if previa is not None and previa != localizacion:
                conn.execute(
                    f"UPDATE {EQUIPOS_NUEVOS_TABLE} SET localizacion=? WHERE uuid=?",
                    (localizacion, uuid),
                )
                for tabla, columna in (
                    ("EQUIPOS", "LOCALIZACION"),
                    ("EQUIPO_INFO", "localizacion"),
                ):
                    try:
                        conn.execute(
                            f"UPDATE {tabla} SET {columna}=? WHERE {columna}=?",
                            (localizacion, previa),
                        )
                    except sqlite3.OperationalError:
                        pass
        conn.execute(
            f"UPDATE {EQUIPOS_NUEVOS_TABLE} "
            "SET sincronizado=?, error_sync=? WHERE uuid=?",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def _mot_equipo_tiene_familia(cursor) -> bool:
    """FAMILIA_COMPAT puede no existir todavia en la planta."""
    cursor.execute(
        """
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'MOT_EQUIPO'
          AND UPPER(COLUMN_NAME) = 'FAMILIA_COMPAT'
        """
    )
    return cursor.fetchone() is not None


def _instalar_pieza_maestra(
    cursor,
    *,
    table: str,
    serial: str,
    marca: str,
    modelo: str,
    localizacion: int,
    code_conjunto: int,
    fecha: str,
    hora: str,
) -> None:
    """Deja una pieza montada en un equipo, dandola de alta si no existia.

    Misma regla que el reemplazo: la identidad de la pieza es el SERIAL, nunca
    la posicion. Si ya hay una fila con ese serial se reutiliza, para que jamas
    haya dos filas de la misma pieza fisica.
    """
    if not serial or not marca or not modelo:
        raise ValueError(
            f"Marca, modelo y serial son obligatorios para la pieza de {table}"
        )

    cursor.execute(
        f"""
        SELECT ID FROM `{table}`
        WHERE UPPER(TRIM(SERIAL)) = %s
        ORDER BY ACTIVO DESC, ID ASC LIMIT 1
        """,
        (serial.upper(),),
    )
    existente = cursor.fetchone()

    if not existente:
        cursor.execute(
            f"""
            INSERT INTO `{table}`
                (FECHA, HORA, MARCA, MODELO, SERIAL, UBICACION,
                 CODE_CONJUNTO, ACTIVO, ESTADO)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 1, 'INSTALADO')
            """,
            (fecha, hora, marca, modelo, serial, localizacion, code_conjunto),
        )
        return

    # La pieza ya existia en la planta: se reactiva en esta posicion. Pasa
    # cuando se registra un equipo armado con piezas que estaban en almacen.
    asignaciones = [
        "FECHA = %s", "HORA = %s", "MARCA = %s", "MODELO = %s",
        "UBICACION = %s", "CODE_CONJUNTO = %s",
        "ACTIVO = 1", "ESTADO = 'INSTALADO'",
    ]
    valores = [fecha, hora, marca, modelo, localizacion, code_conjunto]
    if _table_has_column(cursor, table, "LOCALIZACION"):
        # Esta montada en un equipo, asi que ya no esta en taller ni almacen.
        asignaciones.append("LOCALIZACION = NULL")
    valores.append(existente["ID"])
    cursor.execute(
        f"UPDATE `{table}` SET {', '.join(asignaciones)} WHERE ID = %s",
        tuple(valores),
    )


def apply_equipo_nuevo(cursor, row: dict) -> int:
    """Da de alta el equipo y devuelve la LOCALIZACION que quedo en la planta.

    Se reparte en tres sitios: la identidad en MOT_EQUIPO, la placa del motor
    en MOT_DATA y cada pieza restante en su maestra. Todas las piezas entran
    con ACTIVO = 1 porque estan montadas en el equipo desde el dia uno.
    """
    localizacion = int(row.get("localizacion") or 0)
    if localizacion <= 0:
        raise RuntimeError("El equipo no trae LOCALIZACION.")

    # Si otra tablet ya uso el numero, se corre al siguiente libre. Es el mismo
    # criterio que las ODT: el que llega primero se queda con el numero.
    cursor.execute(
        "SELECT LOCALIZACION FROM MOT_EQUIPO WHERE LOCALIZACION=%s LIMIT 1",
        (localizacion,),
    )
    if cursor.fetchone():
        cursor.execute("SELECT COALESCE(MAX(LOCALIZACION),0) AS m FROM MOT_EQUIPO")
        maximo = int((cursor.fetchone() or {}).get("m") or 0)
        localizacion = max(maximo + 1, localizacion + 1)

    columnas = [
        "CODE_SYS", "EQUIPO", "LOCALIZACION",
        "NAME_SYS_1", "NAME_SYS_2", "CODE_QR", "PUNTOS", "TAGNAME",
    ]
    valores = [
        int(row.get("code_sys") or 0),
        _repair_text(str(row.get("equipo") or "").strip()),
        localizacion,
        _repair_text(str(row.get("sistema") or "").strip()),
        _repair_text(str(row.get("subsistema") or "").strip()),
        _repair_text(str(row.get("code_qr") or "").strip()),
        int(row.get("pt_eq") or 0),
        _repair_text(str(row.get("tagname") or "").strip()),
    ]
    # Familia de compatibilidad. Todo equipo tiene una, incluso el que hoy no
    # comparte piezas con nadie: manana puede entrar su gemelo —el de la otra
    # turbina— y tiene que haber una familia a la que sumarlo.
    #
    # El 0 significa "abrele una familia propia". El numero se calcula aqui y
    # no en la tablet porque esta es la unica que ve la planta entera: una
    # tablet sin sincronizar propondria un numero ya usado por otra.
    if _mot_equipo_tiene_familia(cursor):
        try:
            familia = int(row.get("familia_compat") or 0)
        except (TypeError, ValueError):
            familia = 0
        if familia <= 0:
            cursor.execute(
                "SELECT COALESCE(MAX(FAMILIA_COMPAT), 0) AS m FROM MOT_EQUIPO"
            )
            familia = int((cursor.fetchone() or {}).get("m") or 0) + 1
        columnas.append("FAMILIA_COMPAT")
        valores.append(familia)

    cursor.execute(
        f"INSERT INTO MOT_EQUIPO ({', '.join(columnas)}) "
        f"VALUES ({', '.join(['%s'] * len(columnas))})",
        tuple(valores),
    )

    # Placa del motor. Es la unica pieza con ficha completa, igual que en el
    # reemplazo: las otras maestras no tienen estas columnas.
    def _t(clave: str) -> str:
        return _repair_text(str(row.get(clave) or "").strip())

    def _n(clave):
        valor = row.get(clave)
        return None if valor in (None, "") else valor

    cursor.execute(
        """
        INSERT INTO MOT_DATA (
            FECHA, HORA, MARCA, MODELO, SERIAL, VOLTAJE, CORRIENTE, RPM, SF, HP,
            FRAME, BRGS_DRIVE, BRGS_OPP, CICLO, UBICACION, CODE_CONJUNTO,
            ARRANQUE, PH, TENSION, LUBRICACION, MOTORES_LUB, CANT_MOT_LUB,
            ELEC_MOT_LUB, MAN_MOT_LUB, ELEMENTO_LUB, CANT_ELEM_LUB,
            ELEC_ELEM_LUB, MAN_ELEM_LUB, ACTIVO
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s,
            %s, %s, 1
        )
        """,
        (
            str(row.get("fecha") or ""), str(row.get("hora") or ""),
            _t("marca"), _t("modelo"), _t("serial"),
            _t("voltaje"), _t("corriente"), _t("rpm"), _t("sf"), _t("hp"),
            _t("frame"), _t("brgs_drive"), _t("brgs_opp"), _t("ciclo"),
            localizacion, int(row.get("code_conjunto") or 0),
            _t("arranque"), _t("ph"),
            # TENSION y VOLTAJE son el mismo dato con dos nombres: la app lee
            # uno como alias del otro, asi que se escriben iguales.
            _t("voltaje"),
            _t("lubricacion"), _t("motores_lub"),
            _n("cant_mot_lub"), _n("elec_mot_lub"), _n("man_mot_lub"),
            _t("elemento_lub"),
            _n("cant_elem_lub"), _n("elec_elem_lub"), _n("man_elem_lub"),
        ),
    )

    # Bomba, caja o ventilador. Se reutiliza el mismo instalador del reemplazo
    # para que una pieza registrada al crear el equipo sea indistinguible de
    # una instalada despues.
    piezas = []
    crudo = row.get("piezas_json") or ""
    if crudo:
        try:
            decodificado = json.loads(crudo)
            if isinstance(decodificado, list):
                piezas = [p for p in decodificado if isinstance(p, dict)]
        except (ValueError, TypeError):
            piezas = []

    for pieza in piezas:
        tipo = int(pieza.get("tipo") or 0)
        destino = REPLACEMENT_TABLES.get(tipo)
        if not destino:
            continue
        tabla = destino[0] if isinstance(destino, tuple) else destino
        _instalar_pieza_maestra(
            cursor,
            table=tabla,
            serial=_repair_text(str(pieza.get("serial") or "").strip()),
            marca=_repair_text(str(pieza.get("marca") or "").strip()),
            modelo=_repair_text(str(pieza.get("modelo") or "").strip()),
            localizacion=localizacion,
            code_conjunto=int(row.get("code_conjunto") or 0),
            fecha=str(row.get("fecha") or ""),
            hora=str(row.get("hora") or ""),
        )

    return localizacion


CHECKLIST_COMPRESOR_TABLE = "CHECKLIST_COMPRESOR_LOCAL"


def ensure_checklist_compresor_schema(conn: sqlite3.Connection) -> None:
    """La tabla puede no existir si la tablet trae un APK anterior."""
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS CHECKLIST_COMPRESOR_LOCAL (
            uuid            TEXT PRIMARY KEY,
            localizacion    INTEGER NOT NULL,
            equipo          TEXT, subsistema TEXT, tag TEXT,
            fecha           TEXT NOT NULL, hora TEXT NOT NULL,
            h_inicio        TEXT, h_fin TEXT,
            n_horas         INTEGER, n_arranques INTEGER,
            act1            INTEGER NOT NULL DEFAULT 0,
            act1_obs        TEXT,
            act2            INTEGER NOT NULL DEFAULT 0,
            act2_obs        TEXT,
            act3            INTEGER NOT NULL DEFAULT 0,
            act3_obs        TEXT,
            act4            INTEGER NOT NULL DEFAULT 0,
            act4_obs        TEXT,
            act5            INTEGER NOT NULL DEFAULT 0,
            act5_obs        TEXT,
            act6            INTEGER NOT NULL DEFAULT 0,
            act6_obs        TEXT,
            act7            INTEGER NOT NULL DEFAULT 0,
            act7_obs        TEXT,
            act8            INTEGER NOT NULL DEFAULT 0,
            act8_obs        TEXT,
            act9            INTEGER NOT NULL DEFAULT 0,
            act9_obs        TEXT,
            act10            INTEGER NOT NULL DEFAULT 0,
            act10_obs        TEXT,
            act11            INTEGER NOT NULL DEFAULT 0,
            act11_obs        TEXT,
            mtto_lub_uf      TEXT,
            mtto_lub_uh      TEXT,
            mtto_lub_obs     TEXT,
            mtto_inh_uf      TEXT,
            mtto_inh_uh      TEXT,
            mtto_inh_obs     TEXT,
            mtto_air_uf      TEXT,
            mtto_air_uh      TEXT,
            mtto_air_obs     TEXT,
            mtto_ace_uf      TEXT,
            mtto_ace_uh      TEXT,
            mtto_ace_obs     TEXT,
            usuario         TEXT, cargo TEXT, odt INTEGER,
            sincronizado    INTEGER NOT NULL DEFAULT 0,
            error_sync      TEXT,
            created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.commit()


def fetch_pending_checklists_compresor(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_checklist_compresor_schema(conn)
        rows = conn.execute(
            f"SELECT * FROM {CHECKLIST_COMPRESOR_TABLE} "
            "WHERE sincronizado = 0 ORDER BY created_at ASC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def mark_checklist_compresor_result(
    db_path: Path, uuid: str, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_checklist_compresor_schema(conn)
        conn.execute(
            f"UPDATE {CHECKLIST_COMPRESOR_TABLE} "
            "SET sincronizado=?, error_sync=? WHERE uuid=?",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def sync_compressor_checklists_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    """Baja el historial de check lists de los compresores.

    La pantalla del check list muestra "la ultima vez" que se hizo cada tarea
    de mantenimiento leyendo el historial local. Si ese historial solo viviera
    en la tablet, una limpieza del catalogo (ya paso) o una tablet nueva lo
    borraria y el tecnico volveria a llenar el control de memoria. Por eso la
    descarga trae de MOT_COMP_CHKL tambien las planillas anteriores: la ultima
    puede no tener ninguna tarea realizada. Cada fila se marca como
    sincronizado para que no intente subirse de vuelta.

    Los pendientes locales no se tocan. Los ya sincronizados se actualizan
    con las correcciones de la planta; no se crean mantenimientos nuevos.
    """
    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            cur.execute(
                """
                SELECT t.*
                FROM MOT_COMP_CHKL t
                ORDER BY t.ID
                """
            )
            rows = cur.fetchall()
    finally:
        maria.close()

    conn = sqlite3.connect(db_path)
    try:
        ensure_checklist_compresor_schema(conn)
        insertados = 0
        for row in rows:
            def _v(nombre):
                valor = row.get(nombre)
                return valor if valor is not None else row.get(nombre.lower())

            uuid = str(_v("UUID") or "").strip()
            if not uuid:
                continue
            valores = {
                "uuid": uuid,
                "localizacion": _v("LOCALIZACION"),
                "equipo": _v("EQUIPO"),
                "subsistema": _v("SUBSISTEMA"),
                "tag": _v("TAG"),
                "fecha": str(_v("FECHA") or ""),
                "hora": str(_v("HORA") or ""),
                "h_inicio": _v("H_INICIO"),
                "h_fin": _v("H_FIN"),
                "n_horas": _v("N_HORAS"),
                "n_arranques": _v("N_ARRANQUES"),
                "usuario": _v("USUARIO"),
                "cargo": _v("CARGO"),
                "odt": _v("ODT"),
                "sincronizado": 1,
            }
            for i in range(1, 12):
                valores[f"act{i}"] = _v(f"ACT{i}") or 0
                valores[f"act{i}_obs"] = _v(f"ACT{i}_OBS")
            for c in ("lub", "inh", "air", "ace"):
                valores[f"mtto_{c}_uf"] = _v(f"MTTO_{c.upper()}_UF")
                valores[f"mtto_{c}_uh"] = _v(f"MTTO_{c.upper()}_UH")
                valores[f"mtto_{c}_obs"] = _v(f"MTTO_{c.upper()}_OBS")
            # Un check list ya sincronizado se REEMPLAZA con lo que diga la
            # planta: si alla corrigieron una fecha de mantenimiento mal
            # escrita, la tablet tiene que enterarse. Con INSERT OR IGNORE la
            # correccion nunca llegaba y el mecanico seguia viendo el dato
            # viejo para siempre.
            #
            # Lo pendiente de subir NO se toca: todavia no existe en la
            # planta y pisarlo seria perder trabajo de campo.
            pendiente = conn.execute(
                f"SELECT 1 FROM {CHECKLIST_COMPRESOR_TABLE} "
                "WHERE uuid = ? AND COALESCE(sincronizado, 0) = 0",
                (uuid,),
            ).fetchone()
            if pendiente:
                continue
            columnas = ", ".join(valores)
            marcadores = ", ".join("?" * len(valores))
            cursor = conn.execute(
                f"INSERT OR REPLACE INTO {CHECKLIST_COMPRESOR_TABLE} "
                f"({columnas}) VALUES ({marcadores})",
                tuple(valores.values()),
            )
            insertados += cursor.rowcount
        conn.commit()
        log(
            "Check lists de compresores bajados de la planta: "
            f"{insertados} planillas actualizadas de {len(rows)} registros."
        )
        return insertados
    finally:
        conn.close()


def sync_purge_deleted_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    """Borra de la tablet lo que ya no existe en MariaDB.

    Las bajadas eran solo upsert: si alguien borraba a mano una medicion o un
    equipo en la planta, la tablet lo seguia mostrando para siempre. Tras esta
    purga la descarga deja la tablet como espejo de la base.

    La regla de oro: NADA con sincronizado = 0 se toca. Un trabajo capturado
    en campo que aun no subio no esta en MariaDB por definicion, y borrarlo
    seria perder trabajo real. Solo se purga lo ya sincronizado (su copia
    vive en la planta) y los catalogos, que son de la planta.

    Cada bloque va por su cuenta: si una tabla falla, el resto se purga igual.
    """
    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            def columna(sql: str, campo: str, numerico: bool = False) -> set:
                cur.execute(sql)
                valores = set()
                for row in cur.fetchall():
                    valor = row.get(campo)
                    if valor is None:
                        continue
                    texto = str(valor).strip()
                    if numerico:
                        # pymysql puede entregar Decimal('48.0') o 48.0 segun
                        # el tipo de la columna; el lado local es INTEGER y su
                        # CAST da '48'. Sin este canon, '48.0' != '48' y la
                        # purga borraria equipos VIVOS.
                        try:
                            flotante = float(texto)
                            if flotante == int(flotante):
                                texto = str(int(flotante))
                        except ValueError:
                            pass
                    if texto:
                        valores.add(texto)
                return valores

            locs_planta = columna(
                "SELECT LOCALIZACION FROM MOT_EQUIPO "
                "WHERE LOCALIZACION IS NOT NULL",
                "LOCALIZACION",
                numerico=True,
            )
            uuids = {}
            for nombre, tabla in (
                ("vibracion", "MOT_VIBR_MUES"),
                ("temperatura", "MOT_TEMP_MUES"),
                ("alineacion", "MOT_ALN_REG"),
                ("lubricacion", "MOT_LUB_REG"),
                ("coupling", "MOT_CPLG_REG"),
                ("correa", "MOT_AJC_REG"),
                ("checklist", "MOT_COMP_CHKL"),
                ("black_start", "MOT_BLKS_CHKL"),
            ):
                try:
                    uuids[nombre] = columna(
                        f"SELECT UUID FROM {tabla} WHERE UUID IS NOT NULL",
                        "UUID",
                    )
                except Exception as exc:
                    log(f"Purga: no pude leer {tabla}: {exc}")
            # Los seriales se juntan en un solo conjunto, asi que UNA tabla
            # ilegible lo deja incompleto y borraria piezas vivas del tipo que
            # no se pudo leer. Si algo falla, la purga de piezas se omite
            # entera esta vez.
            seriales = set()
            seriales_completos = True
            for tabla in (*CATALOG_TABLES.values(), "MOT_LOG_RPL"):
                try:
                    seriales |= columna(
                        f"SELECT SERIAL FROM `{tabla}` "
                        "WHERE SERIAL IS NOT NULL AND TRIM(SERIAL) <> ''",
                        "SERIAL",
                    )
                except Exception as exc:
                    seriales_completos = False
                    log(f"Purga: no pude leer seriales de {tabla}: {exc}")
    finally:
        maria.close()

    if not locs_planta:
        # Una lectura vacia del maestro huele a fallo, no a planta sin
        # equipos: mejor no borrar nada.
        log("Purga cancelada: MOT_EQUIPO llego vacio.")
        return 0

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    total = 0

    def purga(descripcion: str, sql: str, params: tuple = ()) -> None:
        nonlocal total
        try:
            borradas = conn.execute(sql, params).rowcount
            conn.commit()
            if borradas:
                total += borradas
                log(f"Purga: {borradas} {descripcion} que ya no estan en MariaDB.")
        except Exception as exc:
            log(f"Purga: fallo en {descripcion}: {exc}")

    def tabla_viva(valores: set) -> None:
        # Una tabla temporal aguanta cualquier volumen; un NOT IN (?, ?, ...)
        # revienta el limite de parametros de SQLite con historiales grandes.
        conn.execute("DROP TABLE IF EXISTS _PURGA_VIVOS")
        conn.execute("CREATE TEMP TABLE _PURGA_VIVOS (valor TEXT PRIMARY KEY)")
        conn.executemany(
            "INSERT OR IGNORE INTO _PURGA_VIVOS VALUES (?)",
            [(valor,) for valor in valores],
        )

    try:
        # Equipos: se protegen los dados de alta en campo que aun no suben.
        try:
            protegidas = {
                str(row["localizacion"]).strip()
                for row in conn.execute(
                    "SELECT localizacion FROM EQUIPOS_NUEVOS_LOCAL "
                    "WHERE COALESCE(sincronizado, 0) = 0"
                )
            }
        except Exception:
            protegidas = set()
        tabla_viva(locs_planta | protegidas)
        purga(
            "equipos",
            "DELETE FROM EQUIPOS WHERE CAST(LOCALIZACION AS TEXT) "
            "NOT IN (SELECT valor FROM _PURGA_VIVOS)",
        )
        purga(
            "fichas tecnicas",
            "DELETE FROM EQUIPO_INFO WHERE CAST(localizacion AS TEXT) "
            "NOT IN (SELECT valor FROM _PURGA_VIVOS)",
        )

        for descripcion, tabla, clave in (
            ("mediciones de vibracion", "MEDICIONES_LOCAL", "vibracion"),
            ("temperaturas", "TEMPERATURAS_LOCAL", "temperatura"),
            ("alineaciones", "ALINEACIONES_LOCAL", "alineacion"),
            ("lubricaciones", "LUBRICACIONES_LOCAL", "lubricacion"),
            ("cambios de coupling", "CAMBIOS_COUPLING_LOCAL", "coupling"),
            ("ajustes de correa", "AJUSTES_CORREA_LOCAL", "correa"),
            ("check lists de compresor", "CHECKLIST_COMPRESOR_LOCAL", "checklist"),
            ("check lists de black start", "CHECKLIST_BLACK_START_LOCAL", "black_start"),
        ):
            existentes = uuids.get(clave)
            if existentes is None:
                continue
            tabla_viva(existentes)
            purga(
                descripcion,
                f"DELETE FROM {tabla} WHERE COALESCE(sincronizado, 0) = 1 "
                "AND COALESCE(TRIM(uuid), '') <> '' "
                "AND uuid NOT IN (SELECT valor FROM _PURGA_VIVOS)",
            )

        # Con una sola maestra ilegible el conjunto queda incompleto y
        # borraria piezas vivas de ese tipo: mejor no purgar esta vez.
        if seriales and seriales_completos:
            tabla_viva(seriales)
            purga(
                "piezas del inventario",
                "DELETE FROM CATALOGO_COMPONENTES WHERE serial "
                "NOT IN (SELECT valor FROM _PURGA_VIVOS)",
            )
        return total
    finally:
        conn.close()


def apply_checklist_compresor(cursor, row: dict) -> None:
    """Inserta el check list de un compresor en MOT_COMP_CHKL.

    Se deduplica por UUID: si la misma tablet reintenta una subida a medias, el
    check list no se duplica en la planta.
    """
    uuid = str(row.get("uuid") or "").strip()
    if uuid:
        cursor.execute(
            "SELECT ID FROM MOT_COMP_CHKL WHERE UUID = %s LIMIT 1", (uuid,)
        )
        if cursor.fetchone():
            return

    def _t(clave):
        return _repair_text(str(row.get(clave) or "").strip())

    def _i(clave):
        try:
            return int(row.get(clave) or 0)
        except (TypeError, ValueError):
            return 0

    valores = [
        _t("fecha"), _t("hora"), _t("equipo"), _i("localizacion"),
        _t("subsistema"), _t("tag"), _t("h_inicio"), _t("h_fin"),
        _i("n_horas"), _i("n_arranques"),
    ]
    for i in range(1, 12):
        valores.append(_i(f"act{i}"))
        valores.append(_t(f"act{i}_obs"))
    for c in ("lub", "inh", "air", "ace"):
        valores.append(_t(f"mtto_{c}_uf"))
        valores.append(_t(f"mtto_{c}_uh"))
        valores.append(_t(f"mtto_{c}_obs"))
    valores += [_t("usuario"), _t("cargo"), row.get("odt"), uuid]

    columnas = (
        "FECHA, HORA, EQUIPO, LOCALIZACION, SUBSISTEMA, TAG, H_INICIO, H_FIN, "
        "N_HORAS, N_ARRANQUES, "
        "ACT1, ACT1_OBS, ACT2, ACT2_OBS, ACT3, ACT3_OBS, ACT4, ACT4_OBS, ACT5, ACT5_OBS, ACT6, ACT6_OBS, ACT7, ACT7_OBS, ACT8, ACT8_OBS, ACT9, ACT9_OBS, ACT10, ACT10_OBS, ACT11, ACT11_OBS, "
        "MTTO_LUB_UF, MTTO_LUB_UH, MTTO_LUB_OBS, MTTO_INH_UF, MTTO_INH_UH, MTTO_INH_OBS, MTTO_AIR_UF, MTTO_AIR_UH, MTTO_AIR_OBS, MTTO_ACE_UF, MTTO_ACE_UH, MTTO_ACE_OBS, "
        "USUARIO, CARGO, ODT, UUID"
    )
    marcadores = ", ".join(["%s"] * len(valores))
    cursor.execute(
        f"INSERT INTO MOT_COMP_CHKL ({columnas}) VALUES ({marcadores})",
        tuple(valores),
    )


def upload_checklists_compresor(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_checklists_compresor(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Check list de compresores pendientes: {len(rows)}")
    if not rows:
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_checklist_compresor_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir check list: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                etiqueta = f"{row.get('equipo')} {row.get('fecha')}"
                try:
                    apply_checklist_compresor(cursor, row)
                    db.commit()
                    mark_checklist_compresor_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Check list subido: {etiqueta}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_checklist_compresor_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo check list {etiqueta}: {error}")
    finally:
        db.close()
    return summary


BLACK_START_TABLE = "CHECKLIST_BLACK_START_LOCAL"

# Columnas de MOT_BLKS_CHKL en el orden en que se insertan.
BLACK_START_PARAMETROS = ['trabajo_hrs', 'refrigerante_lvl', 'combustible_lvl', 'aceite_lvl', 'voltaje_bat', 'amperaje_bat']
BLACK_START_COMPONENTES = ['filtro_aceite', 'filtro_aire', 'panel_control', 'correa']


def ensure_black_start_schema(conn: sqlite3.Connection) -> None:
    """La tabla puede no existir si la tablet trae un APK anterior."""
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS CHECKLIST_BLACK_START_LOCAL (
            uuid              TEXT PRIMARY KEY,
            fecha             TEXT NOT NULL,
            hora              TEXT NOT NULL,
            trabajo_hrs       TEXT, refrigerante_lvl TEXT,
            combustible_lvl   TEXT, aceite_lvl TEXT,
            voltaje_bat       TEXT, amperaje_bat TEXT,
            filtro_aceite     INTEGER NOT NULL DEFAULT 0,
            filtro_aire       INTEGER NOT NULL DEFAULT 0,
            panel_control     INTEGER NOT NULL DEFAULT 0,
            correa            INTEGER NOT NULL DEFAULT 0,
            observaciones     TEXT, usuario TEXT, cargo TEXT, odt INTEGER,
            sincronizado      INTEGER NOT NULL DEFAULT 0,
            error_sync        TEXT,
            created_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.commit()


def fetch_pending_black_start(db_path: Path) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        ensure_black_start_schema(conn)
        rows = conn.execute(
            f"SELECT * FROM {BLACK_START_TABLE} "
            "WHERE sincronizado = 0 ORDER BY created_at ASC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def mark_black_start_result(
    db_path: Path, uuid: str, *, synced: bool, error: str | None = None
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        ensure_black_start_schema(conn)
        conn.execute(
            f"UPDATE {BLACK_START_TABLE} "
            "SET sincronizado=?, error_sync=? WHERE uuid=?",
            (1 if synced else 0, None if synced else error, uuid),
        )
        conn.commit()
    finally:
        conn.close()


def apply_black_start(cursor, row: dict) -> None:
    """Inserta el check list del black start en MOT_BLKS_CHKL.

    Se deduplica por UUID: si una subida a medias se reintenta, el check list
    no queda dos veces en la planta.
    """
    uuid = str(row.get("uuid") or "").strip()
    if uuid:
        cursor.execute(
            "SELECT ID FROM MOT_BLKS_CHKL WHERE UUID = %s LIMIT 1", (uuid,)
        )
        if cursor.fetchone():
            return

    def _t(clave):
        return _repair_text(str(row.get(clave) or "").strip())

    valores = [_t("fecha"), _t("hora")]
    valores += [_t(c) for c in BLACK_START_PARAMETROS]
    for c in BLACK_START_COMPONENTES:
        try:
            valores.append(int(row.get(c) or 0))
        except (TypeError, ValueError):
            valores.append(0)
    valores += [_t("observaciones"), _t("usuario"), _t("cargo"),
                row.get("odt"), uuid]

    marcadores = ", ".join(["%s"] * len(valores))
    cursor.execute(
        "INSERT INTO MOT_BLKS_CHKL (FECHA, HORA, TRABAJO_HRS, REFRIGERANTE_LVL, COMBUSTIBLE_LVL, ACEITE_LVL, VOLTAJE_BAT, AMPERAJE_BAT, FILTRO_ACEITE, FILTRO_AIRE, PANEL_CONTROL, CORREA, OBSERVACIONES, USUARIO, CARGO, ODT, UUID) "
        f"VALUES ({marcadores})",
        tuple(valores),
    )


def upload_black_start(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_black_start(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Check list de black start pendientes: {len(rows)}")
    if not rows:
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_black_start_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir black start: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                etiqueta = f"black start {row.get('fecha')}"
                try:
                    apply_black_start(cursor, row)
                    db.commit()
                    mark_black_start_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Check list subido: {etiqueta}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_black_start_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo {etiqueta}: {error}")
    finally:
        db.close()
    return summary


def upload_equipos_nuevos(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_equipos_nuevos(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Equipos nuevos pendientes: {len(rows)}")
    if not rows:
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_equipo_nuevo_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir equipos nuevos: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                etiqueta = f"{row.get('equipo')} LOC-{row.get('localizacion')}"
                # Cada equipo con su commit: uno rechazado no debe tumbar a los
                # demas ni dejar media alta escrita.
                try:
                    final = apply_equipo_nuevo(cursor, row)
                    db.commit()
                    mark_equipo_nuevo_result(
                        db_path, uuid, synced=True, localizacion=final
                    )
                    summary.uploaded += 1
                    if final != int(row.get("localizacion") or 0):
                        log(
                            f"Equipo dado de alta: {etiqueta} -> quedo como "
                            f"LOC-{final} (el numero anterior ya estaba usado)."
                        )
                    else:
                        log(f"Equipo dado de alta: {etiqueta}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_equipo_nuevo_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error dando de alta {etiqueta}: {error}")
    finally:
        db.close()
    return summary


def upload_ordenes_reparacion(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_ordenes_reparacion(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Ordenes de reparacion pendientes: {len(rows)}")
    if not rows:
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_orden_reparacion_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir ordenes de reparacion: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                label = (
                    f"{uuid} tipo-{row.get('tipo')} "
                    f"serial {row.get('serial')} -> {row.get('estado_orden')}"
                )
                # Cada orden va con su propio commit/rollback: son movimientos
                # independientes y una pieza rechazada no debe tumbar a las demas.
                try:
                    apply_orden_reparacion(cursor, row)
                    db.commit()
                    mark_orden_reparacion_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Orden de reparacion aplicada: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_orden_reparacion_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo orden de reparacion {label}: {error}")
    finally:
        db.close()
    return summary


def merge_upload_summaries(*summaries: UploadSummary) -> UploadSummary:
    merged = UploadSummary()
    for summary in summaries:
        merged.total += summary.total
        merged.uploaded += summary.uploaded
        merged.skipped += summary.skipped
        merged.failed += summary.failed
        merged.messages.extend(summary.messages or [])
    return merged


def upload_measurement_rows(
    db_path: Path,
    rows: list[dict],
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    summary = UploadSummary(total=len(rows))
    if not rows:
        log("No hay mediciones para subir.")
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        summary.failed = len(rows)
        msg = f"No se pudo conectar a MariaDB para subir mediciones: {exc}"
        summary.messages.append(msg)
        log(msg)
        return summary

    try:
        with db.cursor() as cur:
            for row in rows:
                if not row.get("USUARIO"):
                    row["USUARIO"] = default_responsable
                if not row.get("CARGO"):
                    row["CARGO"] = default_cargo
                uuid = row["uuid"]
                label = f"{uuid} LOC-{row['LOCALIZACION']} {row['FECHA']} {row['HORA']}"
                try:
                    if remote_measurement_exists(cur, row):
                        mark_local_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        msg = f"Ya existia en MariaDB: {label}"
                        summary.messages.append(msg)
                        log(msg)
                        continue

                    cur.execute(INSERT_SQL, build_insert_values(row))
                    db.commit()
                    mark_local_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    msg = f"Subida confirmada: {label}"
                    summary.messages.append(msg)
                    log(msg)
                except Exception as exc:
                    db.rollback()
                    err = str(exc)
                    mark_local_result(db_path, uuid, synced=False, error=err[:500])
                    summary.failed += 1
                    msg = f"Error subiendo {label}: {err}"
                    summary.messages.append(msg)
                    log(msg)
    finally:
        db.close()
    return summary


def upload_pending(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    pending = fetch_pending_measurements(db_path)
    if not pending:
        log("No hay mediciones pendientes.")
    return upload_measurement_rows(
        db_path,
        pending,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )


def upload_temperature_rows(
    db_path: Path,
    rows: list[dict],
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    summary = UploadSummary(total=len(rows))
    if not rows:
        log("No hay mediciones de temperatura para subir.")
        return summary

    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_temperature_result(
                db_path, str(row.get("uuid") or ""), synced=False, error=error[:500]
            )
        message = f"No se pudo conectar a MariaDB para subir temperaturas: {error}"
        summary.messages.append(message)
        log(message)
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                if not row.get("USUARIO"):
                    row["USUARIO"] = default_responsable
                if not row.get("CARGO"):
                    row["CARGO"] = default_cargo
                uuid = str(row.get("uuid") or "")
                label = f"{uuid} LOC-{row['LOCALIZACION']} {row['FECHA']} {row['HORA']}"
                try:
                    if temperature_measurement_exists(cursor, row):
                        mark_temperature_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        message = f"Temperatura ya existente en MariaDB: {label}"
                        summary.messages.append(message)
                        log(message)
                        continue
                    cursor.execute(TEMPERATURE_INSERT_SQL, build_temperature_insert_values(row))
                    db.commit()
                    mark_temperature_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    message = f"Temperatura subida: {label}"
                    summary.messages.append(message)
                    log(message)
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_temperature_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    message = f"Error subiendo temperatura {label}: {error}"
                    summary.messages.append(message)
                    log(message)
    finally:
        db.close()
    return summary


def upload_pending_temperatures(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    pending = fetch_pending_temperatures(db_path)
    log(f"Mediciones de temperatura pendientes: {len(pending)}")
    return upload_temperature_rows(
        db_path,
        pending,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )


def upload_alignment_rows(
    db_path: Path,
    rows: list[dict],
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    summary = UploadSummary(total=len(rows))
    if not rows:
        log("No hay alineaciones pendientes.")
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_alignment_result(db_path, str(row.get("uuid") or ""), synced=False, error=error[:500])
        message = f"No se pudo conectar a MariaDB para subir alineaciones: {error}"
        summary.messages.append(message)
        log(message)
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                if not row.get("USUARIO"):
                    row["USUARIO"] = default_responsable
                if not row.get("CARGO"):
                    row["CARGO"] = default_cargo
                uuid = str(row.get("uuid") or "")
                label = f"{uuid} LOC-{row.get('LOCALIZACION')} {row.get('FECHA')} {row.get('HORA')}"
                try:
                    if alignment_measurement_exists(cursor, row):
                        mark_alignment_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        message = f"Alineacion ya existente en MariaDB: {label}"
                        summary.messages.append(message)
                        log(message)
                        continue
                    cursor.execute(ALIGNMENT_INSERT_SQL, build_alignment_insert_values(row))
                    db.commit()
                    mark_alignment_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    message = f"Alineacion subida: {label}"
                    summary.messages.append(message)
                    log(message)
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_alignment_result(db_path, uuid, synced=False, error=error[:500])
                    summary.failed += 1
                    message = f"Error subiendo alineacion {label}: {error}"
                    summary.messages.append(message)
                    log(message)
    finally:
        db.close()
    return summary


def upload_pending_alignments(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    pending = fetch_pending_alignments(db_path)
    log(f"Alineaciones pendientes: {len(pending)}")
    return upload_alignment_rows(
        db_path,
        pending,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )


def upload_lubrication_rows(
    db_path: Path,
    rows: list[dict],
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    summary = UploadSummary(total=len(rows))
    if not rows:
        log("No hay lubricaciones pendientes.")
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_lubrication_result(
                db_path, str(row.get("uuid") or ""),
                synced=False, error=error[:500],
            )
        summary.messages.append(error)
        return summary
    try:
        with db.cursor() as cursor:
            for row in rows:
                row["USUARIO"] = row.get("USUARIO") or default_responsable
                row["CARGO"] = row.get("CARGO") or default_cargo
                uuid = str(row.get("uuid") or "")
                label = (
                    f"{uuid} LOC-{row.get('LOCALIZACION')} "
                    f"{row.get('FECHA')} {row.get('HORA')}"
                )
                try:
                    cursor.execute(
                        """
                        SELECT ID FROM MOT_LUB_REG
                        WHERE LOCALIZACION = %s AND FECHA = %s AND HORA = %s
                        LIMIT 1
                        """,
                        (row.get("LOCALIZACION"), row.get("FECHA"), row.get("HORA")),
                    )
                    if cursor.fetchone() is not None:
                        mark_lubrication_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        log(f"Lubricacion ya existente: {label}")
                        continue
                    cursor.execute(
                        LUBRICATION_INSERT_SQL,
                        build_lubrication_insert_values(row),
                    )
                    db.commit()
                    mark_lubrication_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Lubricacion subida: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_lubrication_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo lubricacion {label}: {error}")
    finally:
        db.close()
    return summary


def upload_pending_lubrications(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    pending = fetch_pending_lubrications(db_path)
    log(f"Lubricaciones pendientes: {len(pending)}")
    return upload_lubrication_rows(
        db_path,
        pending,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )


def upload_pending_coupling_changes(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_coupling_changes(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Cambios de coupling pendientes: {len(rows)}")
    if not rows:
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_coupling_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir cambios de coupling: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                if not row.get("USUARIO"):
                    row["USUARIO"] = default_responsable
                if not row.get("CARGO"):
                    row["CARGO"] = default_cargo
                uuid = str(row.get("uuid") or "")
                label = (
                    f"{uuid} LOC-{row.get('LOCALIZACION')} "
                    f"{row.get('FECHA')} {row.get('HORA')}"
                )
                try:
                    if coupling_change_exists(cursor, row):
                        mark_coupling_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        log(f"Cambio de coupling ya existente: {label}")
                        continue
                    cursor.execute(COUPLING_INSERT_SQL, build_coupling_insert_values(row))
                    db.commit()
                    mark_coupling_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Cambio de coupling subido: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_coupling_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo cambio de coupling {label}: {error}")
    finally:
        db.close()
    return summary


def upload_pending_belt_adjustments(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_belt_adjustments(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Ajustes de correa pendientes: {len(rows)}")
    if not rows:
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_belt_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir ajustes de correa: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                if not row.get("USUARIO"):
                    row["USUARIO"] = default_responsable
                if not row.get("CARGO"):
                    row["CARGO"] = default_cargo
                uuid = str(row.get("uuid") or "")
                label = (
                    f"LOC-{row.get('LOCALIZACION')} "
                    f"{row.get('FECHA')} {row.get('HORA')}"
                )
                try:
                    if belt_adjustment_exists(cursor, row):
                        mark_belt_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        log(f"Ajuste de correa ya existente: {label}")
                        continue
                    cursor.execute(
                        BELT_INSERT_SQL, build_belt_insert_values(row)
                    )
                    db.commit()
                    mark_belt_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Ajuste de correa subido: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_belt_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo ajuste de correa {label}: {error}")
    finally:
        db.close()
    return summary


def upload_pending_admin_events(
    db_path: Path,
    *,
    tablet: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    """Sube la bitacora del administrador a MOT_LOG_ADM.

    Va aparte del resto de los trabajos a proposito: un evento no es una
    medicion, no se puede editar desde la tablet y solo lo genera el admin.
    Si falla, queda pendiente y se reintenta en la siguiente conexion.
    """
    rows = fetch_pending_admin_events(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Eventos del administrador pendientes: {len(rows)}")
    if not rows:
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_admin_event_result(
                db_path, str(row.get("uuid") or ""), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        log(f"No se pudo conectar para subir eventos del administrador: {error}")
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                uuid = str(row.get("uuid") or "")
                label = (
                    f"{row.get('ACCION')} {row.get('SERVICIO') or ''} "
                    f"LOC-{row.get('LOCALIZACION')} "
                    f"{row.get('FECHA')} {row.get('HORA')}"
                ).strip()
                try:
                    if admin_event_exists(cursor, row):
                        mark_admin_event_result(db_path, uuid, synced=True)
                        summary.skipped += 1
                        log(f"Evento del administrador ya existente: {label}")
                        continue
                    cursor.execute(
                        ADMIN_LOG_INSERT_SQL,
                        build_admin_event_insert_values(row, tablet),
                    )
                    db.commit()
                    mark_admin_event_result(db_path, uuid, synced=True)
                    summary.uploaded += 1
                    log(f"Evento del administrador subido: {label}")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_admin_event_result(
                        db_path, uuid, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo evento {label}: {error}")
    finally:
        db.close()
    return summary


def upload_pending_work_orders(
    db_path: Path,
    *,
    log: Callable[[str], None] = print,
) -> UploadSummary:
    rows = fetch_pending_work_orders(db_path)
    summary = UploadSummary(total=len(rows))
    log(f"Ordenes de trabajo pendientes: {len(rows)}")
    if not rows:
        return summary
    try:
        db = connect_mariadb()
    except Exception as exc:
        error = str(exc)
        summary.failed = len(rows)
        for row in rows:
            mark_work_order_result(
                db_path, int(row.get("odt") or 0), synced=False,
                error=error[:500],
            )
        summary.messages.append(error)
        return summary

    try:
        with db.cursor() as cursor:
            for row in rows:
                odt = int(row.get("odt") or 0)
                try:
                    origin = normalize_tablet_origin(row.get('tablet_origen'))
                    cursor.execute("SELECT * FROM MOT_INDICE WHERE ODT=%s LIMIT 1", (odt,))
                    existing = cursor.fetchone()
                    if existing:
                        same_order = (
                            int(existing.get("UBICACION") or 0) == int(row.get("ubicacion") or 0)
                            and str(existing.get("FECHA") or "") == str(row.get("fecha") or "")
                            and str(existing.get("HORA") or "") == str(row.get("hora") or "")
                        )
                        existing_origin = normalize_tablet_origin(existing.get('TABLET_ORIGEN'))
                        if same_order and (origin is None) != (existing_origin is None):
                            # Unknown provenance is not proof of identity. Never
                            # overwrite history with the currently connected tablet.
                            raise RuntimeError(
                                f'ODT {odt}: origen de tablet ambiguo; requiere revision '
                                'antes de subir los servicios. No se modifico el origen.'
                            )
                        same_order = same_order and origin == existing_origin
                        if same_order:
                            cursor.execute('UPDATE MOT_INDICE SET LIMPIEZA_PLATO=%s WHERE ODT=%s',
                                           (int(row.get('limpieza_plato') or 0), odt))
                            db.commit()
                            mark_work_order_result(db_path, odt, synced=True)
                            summary.skipped += 1
                            log(f"ODT {odt} ya existente en MOT_INDICE. Tablet origen: {origin or 'Sin identificar (registro anterior)' }.")
                            continue
                        cursor.execute("SELECT COALESCE(MAX(ODT), 0) AS max_odt FROM MOT_INDICE")
                        maximum = int((cursor.fetchone() or {}).get("max_odt") or 0)
                        new_odt = max(maximum + 1, odt + 1)
                        local = sqlite3.connect(db_path)
                        try:
                            local_max = local.execute(
                                'SELECT COALESCE(MAX(odt), 0) FROM ORDENES_TRABAJO_LOCAL'
                            ).fetchone()[0]
                        finally:
                            local.close()
                        new_odt = max(new_odt, int(local_max) + 1)
                        if new_odt > 2147483647:
                            raise RuntimeError("No hay rango INT disponible para generar otra ODT")
                        remap_local_odt(db_path, odt, new_odt)
                        log(f"ODT {odt} ya usada; reasignada de forma segura a {new_odt}.")
                        row["odt"] = new_odt
                        odt = new_odt
                    cursor.execute(WORK_ORDER_INSERT_SQL, build_work_order_values(row))
                    db.commit()
                    mark_work_order_result(db_path, odt, synced=True)
                    summary.uploaded += 1
                    log(f"ODT subida a MOT_INDICE: {odt}. Tablet origen: {origin or 'Sin identificar (registro anterior)' }.")
                except Exception as exc:
                    db.rollback()
                    error = str(exc)
                    mark_work_order_result(
                        db_path, odt, synced=False, error=error[:500]
                    )
                    summary.failed += 1
                    summary.messages.append(error)
                    log(f"Error subiendo ODT {odt}: {error}")
    finally:
        db.close()
    return summary


def upload_pending_plate_cleanings(db_path: Path, *, log=print) -> UploadSummary:
    return UploadSummary(**separator_cleaning.upload(db_path, connect_mariadb, log))


def sync_plate_cleanings_from_mariadb(db_path: Path, *, log=print):
    return separator_cleaning.download(db_path, connect_mariadb, log)


def upload_pending_work(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    tablet: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    # Los equipos nuevos van primero: todo lo demas puede referirse a una
    # LOCALIZACION que solo existe si el equipo ya se dio de alta.
    equipo_nuevo_summary = upload_equipos_nuevos(db_path, log=log)
    work_order_summary = upload_pending_work_orders(db_path, log=log)
    if work_order_summary.failed:
        log('Servicios retenidos: hay ODT pendientes con errores. Corrija y reintente; '
            'no se enviaran servicios asociados a una ODT sin confirmar.')
        return merge_upload_summaries(equipo_nuevo_summary, work_order_summary)
    # An ODT may be remapped above; every service must use the final number.
    checklist_summary = upload_checklists_compresor(db_path, log=log)
    black_start_summary = upload_black_start(db_path, log=log)
    plate_summary = upload_pending_plate_cleanings(db_path, log=log)
    log(f'Resumen limpiezas de plato: {plate_summary.uploaded} subidas, '
        f'{plate_summary.skipped} existentes, {plate_summary.failed} errores.')
    measurement_summary = upload_pending(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    replacement_summary = upload_pending_replacements(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    # Va despues de los reemplazos a proposito: si en la misma visita el tecnico
    # retiro la pieza y luego le cambio el estatus, el reemplazo ya la dejo
    # inactiva y el cambio de estatus deja de rebotar por "esta instalada".
    estado_summary = upload_estado_changes(db_path, log=log)
    # Despues de los cambios de estatus por la misma razon que estos van
    # despues de los reemplazos: la orden manda la pieza al taller partiendo de
    # una pieza ya retirada, y si el tecnico hizo todo en la misma visita el
    # orden cronologico es reemplazo -> estatus -> orden.
    orden_reparacion_summary = upload_ordenes_reparacion(db_path, log=log)
    temperature_summary = upload_pending_temperatures(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    alignment_summary = upload_pending_alignments(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    lubrication_summary = upload_pending_lubrications(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    coupling_summary = upload_pending_coupling_changes(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    correa_summary = upload_pending_belt_adjustments(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    # La bitacora del admin va al final: describe correcciones sobre trabajos
    # que para este punto ya subieron, asi el evento nunca llega antes que
    # aquello que corrige.
    admin_summary = upload_pending_admin_events(
        db_path, tablet=tablet, log=log,
    )
    log(
        "Resumen temperaturas: "
        f"{temperature_summary.uploaded} subidas, "
        f"{temperature_summary.skipped} existentes, "
        f"{temperature_summary.failed} errores."
    )
    log(
        "Resumen alineaciones: "
        f"{alignment_summary.uploaded} subidas, "
        f"{alignment_summary.skipped} existentes, "
        f"{alignment_summary.failed} errores."
    )
    log(
        "Resumen lubricaciones: "
        f"{lubrication_summary.uploaded} subidas, "
        f"{lubrication_summary.skipped} existentes, "
        f"{lubrication_summary.failed} errores."
    )
    log(
        "Resumen coupling: "
        f"{coupling_summary.uploaded} subidos, "
        f"{coupling_summary.skipped} existentes, "
        f"{coupling_summary.failed} errores."
    )
    log(
        "Resumen cambios de estatus: "
        f"{estado_summary.uploaded} aplicados, "
        f"{estado_summary.failed} errores."
    )
    log(
        "Resumen ordenes de reparacion: "
        f"{orden_reparacion_summary.uploaded} aplicadas, "
        f"{orden_reparacion_summary.failed} errores."
    )
    log(
        "Resumen equipos nuevos: "
        f"{equipo_nuevo_summary.uploaded} dados de alta, "
        f"{equipo_nuevo_summary.failed} errores."
    )
    log(
        "Resumen check list de compresores: "
        f"{checklist_summary.uploaded} subidos, "
        f"{checklist_summary.failed} errores."
    )
    log(
        "Resumen check list de black start: "
        f"{black_start_summary.uploaded} subidos, "
        f"{black_start_summary.failed} errores."
    )
    log(
        "Resumen ajustes de correa: "
        f"{correa_summary.uploaded} subidos, "
        f"{correa_summary.skipped} existentes, "
        f"{correa_summary.failed} errores."
    )
    log(
        "Resumen eventos del administrador: "
        f"{admin_summary.uploaded} subidos, "
        f"{admin_summary.skipped} existentes, "
        f"{admin_summary.failed} errores."
    )
    return merge_upload_summaries(
        equipo_nuevo_summary,
        checklist_summary,
        black_start_summary,
        work_order_summary,
        plate_summary,
        measurement_summary,
        replacement_summary,
        estado_summary,
        orden_reparacion_summary,
        temperature_summary,
        alignment_summary,
        lubrication_summary,
        coupling_summary,
        correa_summary,
        admin_summary,
    )


def perform_usb_upload_for_device(
    device: Device,
    tmp_dir: Path,
    log: Callable[[str], None] = print,
    request_id: str = "",
) -> UploadSummary:
    log(f"Tablet detectada: {device.serial}")

    set_tablet_usb_status(
        device.serial,
        status="SYNCING",
        detail="Subiendo mediciones a MariaDB...",
        tmp_dir=tmp_dir,
        request_id=request_id,
    )
    local_db = pull_tablet_database(device.serial, tmp_dir)
    default_responsable, default_cargo = read_tablet_operator(device.serial)
    try:
        sync_equipo_info_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Catalogo tecnico no actualizado: {exc}")
    try:
        sync_users_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Usuarios no actualizados: {exc}")
    pending = fetch_pending_measurements(local_db)
    pending_temperatures = fetch_pending_temperatures(local_db)
    pending_alignments = fetch_pending_alignments(local_db)
    pending_lubrications = fetch_pending_lubrications(local_db)
    pending_replacements = fetch_pending_replacements(local_db)
    pending_estado_changes = fetch_pending_estado_changes(local_db)
    pending_ordenes_reparacion = fetch_pending_ordenes_reparacion(local_db)
    pending_coupling = fetch_pending_coupling_changes(local_db)
    pending_work_orders = fetch_pending_work_orders(local_db)
    all_local = fetch_local_measurements(local_db, only_pending=False)
    log(f"Mediciones pendientes encontradas: {len(pending)}")
    log(f"Temperaturas pendientes encontradas: {len(pending_temperatures)}")
    log(f"Alineaciones pendientes encontradas: {len(pending_alignments)}")
    log(f"Lubricaciones pendientes encontradas: {len(pending_lubrications)}")
    log(f"Componentes de reemplazo pendientes: {len(pending_replacements)}")
    log(f"Cambios de estatus pendientes: {len(pending_estado_changes)}")
    log(f"Ordenes de reparacion pendientes: {len(pending_ordenes_reparacion)}")
    log(f"Cambios de coupling pendientes: {len(pending_coupling)}")
    log(f"Ordenes de trabajo pendientes: {len(pending_work_orders)}")
    log(f"Mediciones locales en tablet: {len(all_local)}")
    summary = upload_pending_work(
        local_db,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        tablet=device.serial,
        log=log,
    )
    try:
        sync_latest_measurements_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Ultimas mediciones no actualizadas: {exc}")
    try:
        sync_latest_temperatures_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Temperaturas historicas no actualizadas: {exc}")
    try:
        sync_alignment_history_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Alineaciones historicas no actualizadas: {exc}")
    try:
        sync_lubrication_history_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Lubricaciones historicas no actualizadas: {exc}")
    try:
        sync_equipo_info_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Catalogo tecnico no actualizado: {exc}")
    try:
        sync_users_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Usuarios no actualizados: {exc}")
    # Lo borrado a mano en la planta se va tambien de la tablet. Va en
    # toda ruta que baje datos y empuje la base: si solo estuviera en
    # la descarga, subir pendientes devolveria los datos viejos.
    try:
        sync_purge_deleted_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Purga de borrados no aplicada: {exc}")
    push_tablet_database(device.serial, local_db)
    set_tablet_usb_status(
        device.serial,
        status="DONE" if summary.failed == 0 else "ERROR",
        detail=(
            f"Proceso terminado: {summary.uploaded} subidas, "
            f"{summary.skipped} ya existentes, {summary.failed} errores"
        ),
        tmp_dir=tmp_dir,
        request_id=request_id,
    )
    log(
        "Proceso terminado: "
        f"{summary.uploaded} subidas, {summary.skipped} ya existentes, {summary.failed} con error."
    )
    return summary


def run_usb_upload(log: Callable[[str], None] = print) -> UploadSummary:
    devices = list_devices()
    device = select_ready_device(devices)

    with tempfile.TemporaryDirectory(prefix="scv_ptbg_") as tmp:
        return perform_usb_upload_for_device(device, Path(tmp), log=log)


CATALOG_TABLES = {
    1: "MOT_DATA",
    2: "MOT_BOMB_DATA",
    3: "MOT_CAJA_DATA",
    4: "MOT_VENT_DATA",
}


def sync_ordenes_reparacion_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    """Baja a la tablet las ordenes de reparacion de toda la planta.

    Sin esto cada tablet solo veia las ordenes que ella misma creo: si un
    mecanico se lleva un motor al taller, el resto no se entera ni le cuenta en
    el pendiente. Las ordenes son de la planta, no del aparato.

    Se traen todas las ABIERTAS y las CERRADAS recientes. Las cerradas viejas
    ya no cambian nada operativo y solo harian crecer la base de la tablet.
    """
    corte = (datetime.now() - timedelta(days=90)).strftime("%Y-%m-%d")

    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            cur.execute(
                """
                SELECT UUID, EQUIPO, SERIAL, MARCA, MODELO, UBICACION_ORIGEN,
                       DESTINO, MOTIVO, FECHA_SALIDA, HORA_SALIDA,
                       USUARIO_SALIDA, CARGO_SALIDA, ODT, ESTADO_ORDEN,
                       FECHA_RETORNO, HORA_RETORNO, USUARIO_CIERRE,
                       CARGO_CIERRE, TRABAJO, RESULTADO,
                       UBICACION_FINAL, OBSERVACIONES
                FROM MOT_ORD_REP
                WHERE UUID IS NOT NULL AND TRIM(UUID) <> ''
                  AND (UPPER(TRIM(COALESCE(ESTADO_ORDEN, 'ABIERTA'))) <> 'CERRADA'
                       OR COALESCE(FECHA_RETORNO, FECHA_SALIDA) >= %s)
                """,
                (corte,),
            )
            filas = cur.fetchall() or []
    finally:
        maria.close()

    registros = []
    for row in filas:
        uuid_orden = _clean_text(row.get("UUID"))
        if not uuid_orden:
            continue
        try:
            tipo = int(str(row.get("EQUIPO") or "0").strip() or 0)
        except (TypeError, ValueError):
            tipo = 0
        registros.append({
            "uuid": uuid_orden,
            "tipo": tipo,
            "serial": _clean_text(row.get("SERIAL")) or "",
            "marca": _clean_text(row.get("MARCA")),
            "modelo": _clean_text(row.get("MODELO")),
            "ubicacion_origen": row.get("UBICACION_ORIGEN"),
            "destino": _clean_text(row.get("DESTINO")) or "",
            "motivo": _clean_text(row.get("MOTIVO")),
            "fecha_salida": _clean_text(row.get("FECHA_SALIDA")) or "",
            "hora_salida": _clean_text(row.get("HORA_SALIDA")) or "",
            "usuario_salida": _clean_text(row.get("USUARIO_SALIDA")),
            "cargo_salida": _clean_text(row.get("CARGO_SALIDA")),
            "odt": row.get("ODT"),
            "estado_orden": (_clean_text(row.get("ESTADO_ORDEN")) or "ABIERTA").upper(),
            "fecha_retorno": _clean_text(row.get("FECHA_RETORNO")),
            "hora_retorno": _clean_text(row.get("HORA_RETORNO")),
            "usuario_cierre": _clean_text(row.get("USUARIO_CIERRE")),
            "cargo_cierre": _clean_text(row.get("CARGO_CIERRE")),
            "trabajo_realizado": _clean_text(row.get("TRABAJO")),
            "resultado": _clean_text(row.get("RESULTADO")),
            "ubicacion_final": _clean_text(row.get("UBICACION_FINAL")),
            "observaciones": _clean_text(row.get("OBSERVACIONES")),
        })

    conn = sqlite3.connect(db_path)
    try:
        ensure_ordenes_reparacion_schema(conn)
        # Las filas locales sin subir no se tocan: son trabajo del tecnico que
        # todavia no llego al servidor y pisarlas seria perderlo.
        pendientes = {
            fila[0]
            for fila in conn.execute(
                "SELECT uuid FROM ORDENES_REPARACION_LOCAL WHERE sincronizado = 0"
            )
        }
        entrantes = [r for r in registros if r["uuid"] not in pendientes]
        conn.executemany(
            """
            INSERT OR REPLACE INTO ORDENES_REPARACION_LOCAL
              (uuid, tipo, serial, marca, modelo, ubicacion_origen, destino,
               motivo, fecha_salida, hora_salida, usuario_salida, cargo_salida,
               odt, estado_orden, fecha_retorno, hora_retorno, usuario_cierre,
               cargo_cierre, trabajo_realizado, resultado, ubicacion_final,
               observaciones, sincronizado, error_sync)
            VALUES (:uuid, :tipo, :serial, :marca, :modelo, :ubicacion_origen,
                    :destino, :motivo, :fecha_salida, :hora_salida,
                    :usuario_salida, :cargo_salida, :odt, :estado_orden,
                    :fecha_retorno, :hora_retorno, :usuario_cierre,
                    :cargo_cierre, :trabajo_realizado, :resultado,
                    :ubicacion_final, :observaciones, 1, NULL)
            """,
            entrantes,
        )
        conn.commit()
    finally:
        conn.close()

    abiertas = sum(1 for r in entrantes if r["estado_orden"] != "CERRADA")
    log(
        f"Ordenes de reparacion actualizadas: {len(entrantes)} "
        f"({abiertas} abiertas). Se conservaron {len(pendientes)} sin enviar."
    )
    return len(entrantes)


def sync_component_catalog_from_mariadb(
    db_path: Path,
    log: Callable[[str], None] = print,
) -> int:
    """Baja a la tablet el catalogo de piezas de motor, bomba, caja y ventilador.

    El mecanico asigna piezas en campo, sin señal, asi que el catalogo tiene que
    viajar con el en cada sincronizacion por USB. Se arma con lo que ya existe:

      MOT_LOG_RPL   -> piezas que salieron de algun equipo, o sea libres
      MOT_*_DATA    -> piezas instaladas ahora mismo

    Las instaladas tambien bajan, marcadas con instalado=1 y el equipo donde
    estan, para que la app pueda advertir antes de reasignarlas.
    El SERIAL es la identidad de la pieza: sobre el se deduplica.
    """
    filas: list[dict] = []
    maria = connect_mariadb()
    try:
        with maria.cursor() as cur:
            for tipo, tabla in CATALOG_TABLES.items():
                # LOCALIZACION (taller/almacen) puede no existir todavia en la
                # maestra; si se agrega, esto la toma sin tocar el codigo.
                cur.execute(
                    """
                    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
                      AND UPPER(COLUMN_NAME) = 'LOCALIZACION'
                    """,
                    (tabla,),
                )
                tiene_localizacion = cur.fetchone() is not None
                col_loc = (
                    "d.LOCALIZACION AS SITIO" if tiene_localizacion
                    else "NULL AS SITIO"
                )

                # Aqui se quiere el inventario completo, instaladas y retiradas,
                # asi que no se filtra por ACTIVO. El ORDER BY si importa: la
                # deduplicacion por serial se queda con la ultima fila leida, y
                # con ACTIVO ASC la fila activa entra al final y siempre gana.
                cur.execute(
                    f"""
                    SELECT d.MARCA, d.MODELO, d.SERIAL, d.FECHA,
                           d.ESTADO, d.ACTIVO, d.UBICACION, d.CODE_CONJUNTO,
                           {col_loc}, e.EQUIPO
                    FROM `{tabla}` d
                    LEFT JOIN MOT_EQUIPO e ON e.LOCALIZACION = d.UBICACION
                    WHERE d.SERIAL IS NOT NULL AND TRIM(d.SERIAL) <> ''
                    ORDER BY d.ACTIVO ASC, d.ID ASC
                    """
                )
                unidades = cur.fetchall() or []

                destinos: dict[str, str | None] = {}
                if not tiene_localizacion:
                    cur.execute(
                        """
                        SELECT r.SERIAL, r.LOCALIZACION
                        FROM MOT_LOG_RPL r
                        INNER JOIN (
                            SELECT SERIAL, MAX(ID) AS ULTIMO
                            FROM MOT_LOG_RPL
                            WHERE EQUIPO = %s
                              AND SERIAL IS NOT NULL AND TRIM(SERIAL) <> ''
                            GROUP BY SERIAL
                        ) u ON u.ULTIMO = r.ID
                        """,
                        (str(tipo),),
                    )
                    for fila in cur.fetchall() or []:
                        s = str(fila.get("SERIAL") or "").strip()
                        if s:
                            destinos[s.upper()] = _clean_text(fila.get("LOCALIZACION"))

                catalogo: dict[str, dict] = {}
                for row in unidades:
                    serial = str(row.get("SERIAL") or "").strip()
                    if not serial:
                        continue
                    estado = (_clean_text(row.get("ESTADO")) or "").upper()
                    try:
                        ubicacion = int(row.get("UBICACION") or 0)
                    except (TypeError, ValueError):
                        ubicacion = 0
                    try:
                        activo = int(row.get("ACTIVO") or 0)
                    except (TypeError, ValueError):
                        activo = 0
                    # ACTIVO manda: es lo unico que dice si la pieza esta puesta
                    # ahora mismo. UBICACION la conservan tambien las retiradas
                    # (es donde estuvieron), asi que no sirve para decidirlo.
                    instalado = activo == 1
                    catalogo[serial.upper()] = {
                        "tipo": tipo,
                        "serial": serial,
                        "marca": _clean_text(row.get("MARCA")),
                        "modelo": _clean_text(row.get("MODELO")),
                        "instalado": 1 if instalado else 0,
                        "estado": estado or ("INSTALADO" if instalado else "DISPONIBLE"),
                        "sitio": _clean_text(row.get("SITIO"))
                        or destinos.get(serial.upper()),
                        "activo": activo,
                        "code_conjunto": row.get("CODE_CONJUNTO"),
                        "localizacion": ubicacion or None,
                        "equipo": _clean_text(row.get("EQUIPO")),
                        "ultima_fecha": _clean_text(row.get("FECHA")),
                    }

                filas.extend(catalogo.values())
    finally:
        maria.close()

    ahora = datetime.now().isoformat(timespec="seconds")
    for fila in filas:
        fila["actualizado"] = ahora

    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS CATALOGO_COMPONENTES (
              tipo          INTEGER NOT NULL,
              serial        TEXT NOT NULL,
              marca         TEXT,
              modelo        TEXT,
              instalado     INTEGER NOT NULL DEFAULT 0,
              localizacion  INTEGER,
              equipo        TEXT,
              ultima_fecha  TEXT,
              actualizado   TEXT,
              PRIMARY KEY (tipo, serial)
            )
            """
        )
        for columna, tipo_sql in (
            ("estado", "TEXT"),
            ("sitio", "TEXT"),
            ("activo", "INTEGER"),
            ("code_conjunto", "INTEGER"),
        ):
            try:
                conn.execute(
                    f"ALTER TABLE CATALOGO_COMPONENTES ADD COLUMN {columna} {tipo_sql}"
                )
            except sqlite3.OperationalError:
                pass  # ya existe
        # Se reescribe entero: una pieza que ya no esta en MariaDB no debe
        # seguir ofreciendose en campo.
        conn.execute("DELETE FROM CATALOGO_COMPONENTES")
        conn.executemany(
            """
            INSERT OR REPLACE INTO CATALOGO_COMPONENTES
              (tipo, serial, marca, modelo, instalado,
               localizacion, equipo, ultima_fecha, actualizado,
               estado, sitio, activo, code_conjunto)
            VALUES (:tipo, :serial, :marca, :modelo, :instalado,
                    :localizacion, :equipo, :ultima_fecha, :actualizado,
                    :estado, :sitio, :activo, :code_conjunto)
            """,
            filas,
        )
        conn.commit()
    finally:
        conn.close()

    libres = sum(1 for fila in filas if not fila["instalado"])
    log(
        f"Catalogo de piezas actualizado: {len(filas)} piezas "
        f"({libres} libres, {len(filas) - libres} instaladas)."
    )
    return len(filas)


def _clean_text(value: object) -> str | None:
    if value is None:
        return None
    texto = str(value).strip()
    return texto or None


def perform_usb_download_for_device(
    device: Device,
    tmp_dir: Path,
    log: Callable[[str], None] = print,
    request_id: str = "",
) -> None:
    set_tablet_usb_status(
        device.serial,
        status="SYNCING",
        detail="Descargando datos de MariaDB a la tablet...",
        tmp_dir=tmp_dir,
        request_id=request_id,
    )
    local_db = pull_tablet_database(device.serial, tmp_dir)
    sync_equipo_info_from_mariadb(local_db, log=log)
    sync_users_from_mariadb(local_db, log=log)
    sync_latest_measurements_from_mariadb(local_db, log=log)
    sync_latest_temperatures_from_mariadb(local_db, log=log)
    sync_alignment_history_from_mariadb(local_db, log=log)
    sync_lubrication_history_from_mariadb(local_db, log=log)
    sync_component_catalog_from_mariadb(local_db, log=log)
    sync_ordenes_reparacion_from_mariadb(local_db, log=log)
    sync_compressor_checklists_from_mariadb(local_db, log=log)
    sync_plate_cleanings_from_mariadb(local_db, log=log)
    # Al final, cuando ya bajo todo lo vivo: lo que se borro en la planta se
    # borra tambien de la tablet. Solo aqui, en la DESCARGA: es el unico
    # momento en que el usuario pidio "dejame la tablet como la base".
    try:
        sync_purge_deleted_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Purga de borrados no aplicada: {exc}")
    push_tablet_database(device.serial, local_db)
    set_tablet_usb_status(
        device.serial,
        status="DONE",
        detail="Datos de MariaDB descargados correctamente.",
        tmp_dir=tmp_dir,
        request_id=request_id,
    )
    log("Datos de MariaDB descargados correctamente en la tablet.")


def process_tablet_usb_request(
    device: Device,
    tmp_dir: Path,
    processed_ids: set[str],
    log: Callable[[str], None] = print,
) -> bool:
    request = read_tablet_usb_request(device.serial)
    if not request:
        return False

    request_id = str(request.get("id") or "")
    if request_id and request_id in processed_ids:
        clear_tablet_usb_request(device.serial)
        return False

    if request_id:
        processed_ids.add(request_id)

    clear_tablet_usb_request(device.serial)
    log(f"Solicitud recibida desde tablet: {request_id or 'sin id'}")

    try:
        if str(request.get("action") or "") == "download_data":
            perform_usb_download_for_device(
                device, tmp_dir, log=log, request_id=request_id
            )
        else:
            perform_usb_upload_for_device(
                device, tmp_dir, log=log, request_id=request_id
            )
    except Exception as exc:
        set_tablet_usb_status(
            device.serial,
            status="ERROR",
            detail=f"Error en subida USB: {exc}",
            tmp_dir=tmp_dir,
            request_id=request_id,
        )
        log(f"ERROR solicitud tablet: {exc}")
    return True


def _safe_pdf_name(value: str, default: str = "SCV-PTBG_medicion.pdf") -> str:
    safe_name = "".join(
        ch if ch.isalnum() or ch in " ._-" else "_" for ch in value
    ).strip() or default
    if not safe_name.lower().endswith(".pdf"):
        safe_name += ".pdf"
    return safe_name


def _request_text(request: dict, key: str, default: str = "") -> str:
    value = request.get(key)
    return default if value is None else _repair_text(str(value).strip())


def _request_info_text(request: dict, key: str) -> str:
    info = request.get("info") if isinstance(request.get("info"), dict) else {}
    value = info.get(key)
    return "" if value is None else _repair_text(str(value).strip())


def _mariadb_print_system(localizacion: int) -> tuple[str, str]:
    if localizacion <= 0:
        return "", ""
    try:
        maria = connect_mariadb()
        try:
            with maria.cursor() as cur:
                cur.execute(
                    """
                    SELECT
                        s.SISTEMA AS sistema,
                        e.NAME_SYS_2 AS subsistema
                    FROM MOT_EQUIPO e
                    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
                    WHERE e.LOCALIZACION = %s
                    LIMIT 1
                    """,
                    (localizacion,),
                )
                row = cur.fetchone()
        finally:
            maria.close()
    except Exception:
        return "", ""
    if not row:
        return "", ""
    return (
        _repair_text(str(row.get("sistema") or "").strip()),
        _repair_text(str(row.get("subsistema") or "").strip()),
    )


def _request_with_print_system(request: dict) -> dict:
    try:
        localizacion = int(request.get("localizacion") or 0)
    except (TypeError, ValueError):
        localizacion = 0
    sistema, subsistema = _mariadb_print_system(localizacion)
    if not sistema and not subsistema:
        return request
    enriched = dict(request)
    if sistema:
        enriched["sistema"] = sistema
    if subsistema:
        enriched["subsistema"] = subsistema
    return enriched


def _sqlite_print_subsystem(db_path: Path, localizacion: int) -> str:
    if localizacion <= 0 or not db_path.exists():
        return ""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        cols = conn.execute("PRAGMA table_info(EQUIPOS)").fetchall()
        has_subsystem = any(
            str(col["name"]).upper() == "SUBSISTEMA" for col in cols
        )
        if not has_subsystem:
            return ""
        row = conn.execute(
            """
            SELECT SUBSISTEMA
            FROM EQUIPOS
            WHERE LOCALIZACION = ?
            LIMIT 1
            """,
            (localizacion,),
        ).fetchone()
    finally:
        conn.close()
    if not row:
        return ""
    return _repair_text(str(row["SUBSISTEMA"] or "").strip())


def _repair_text(value: str) -> str:
    if "Ã" not in value and "Â" not in value:
        return value
    try:
        return value.encode("latin1").decode("utf-8")
    except UnicodeError:
        return value


def _measurement_value(request: dict, key: str) -> str:
    values = request.get("valores") if isinstance(request.get("valores"), dict) else {}
    value = values.get(key)
    if value is None:
        value = values.get(key.lower())
    if value is None:
        value = values.get(key.upper())
    if value is None:
        value = request.get(key)
    if value is None:
        value = request.get(key.lower())
    if value is None:
        value = request.get(key.upper())
    if value is None or value == "":
        return ""
    try:
        return f"{float(value):.2f}".rstrip("0").rstrip(".")
    except (TypeError, ValueError):
        return str(value)


PRINT_VALUE_SOURCE_POINTS_BY_PT_EQ = {
    1: {1: 1, 2: 2, 3: 5, 4: 6},
    2: {1: 1, 2: 2, 3: 5, 4: 6},
    3: {1: 1, 2: 2, 3: 5, 4: 6},
    4: {1: 1, 2: 2, 3: 9},
    5: {1: 1, 2: 2, 3: 7, 4: 8},
    6: {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 5},
    7: {1: 1, 2: 2, 3: 5, 4: 6},
    8: {1: 1, 2: 2, 3: 5, 4: 6},
    9: {1: 1, 2: 2, 3: 5, 4: 6},
}


def _draw_text(page, x: float, y: float, text: str, *, size: float = 8.0) -> None:
    if not text:
        return
    page.insert_text(
        (x, y),
        str(text)[:90],
        fontsize=size,
        fontname="helv",
        color=(0, 0, 0),
        overlay=True,
    )


def _scale_point(page, x: float, y: float) -> tuple[float, float]:
    return (
        x * page.rect.width / TEMPLATE_BASE_WIDTH,
        y * page.rect.height / TEMPLATE_BASE_HEIGHT,
    )


def _scale_rect(page, rect: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    x0, y0 = _scale_point(page, rect[0], rect[1])
    x1, y1 = _scale_point(page, rect[2], rect[3])
    return (x0, y0, x1, y1)


def _draw_centered(
    page,
    rect: tuple[float, float, float, float],
    text: str,
    *,
    size: float = 8.0,
    baseline_shift: float = 0.0,
) -> None:
    if not text:
        return
    value = str(text).strip()[:120]
    x0, y0, x1, y1 = _scale_rect(page, rect)
    scaled_size = size * min(
        page.rect.width / TEMPLATE_BASE_WIDTH,
        page.rect.height / TEMPLATE_BASE_HEIGHT,
    )
    pad = 6
    available_width = max(1, x1 - x0 - (pad * 2))
    font_size = scaled_size
    try:
        text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
    except Exception:
        text_width = len(value) * font_size * 0.45
    while text_width > available_width and font_size > 3.2:
        font_size -= 0.3
        try:
            text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
        except Exception:
            text_width = len(value) * font_size * 0.45
    while text_width > available_width and len(value) > 4:
        value = value[:-4].rstrip() + "..."
        try:
            text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
        except Exception:
            text_width = len(value) * font_size * 0.45
    x = x0 + pad + max(0, (available_width - text_width) / 2)
    y = y0 + ((y1 - y0) + font_size) / 2 + baseline_shift
    page.insert_text(
        (x, y),
        value,
        fontsize=font_size,
        fontname="helv",
        color=(0, 0, 0),
        overlay=True,
    )


def _draw_centered_absolute(
    page,
    x0: float,
    x1: float,
    baseline_y: float,
    text: str,
    *,
    size: float = 6.4,
) -> None:
    if not text:
        return
    value = str(text).strip()[:120]
    font_size = size
    pad = 14
    available_width = max(1, x1 - x0 - (pad * 2) - 24)
    try:
        text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
    except Exception:
        text_width = len(value) * font_size * 0.45
    while text_width > available_width and font_size > 3.0:
        font_size -= 0.3
        try:
            text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
        except Exception:
            text_width = len(value) * font_size * 0.45
    while text_width > available_width and len(value) > 4:
        value = value[:-4].rstrip() + "..."
        try:
            text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
        except Exception:
            text_width = len(value) * font_size * 0.45
    x = x0 + pad + max(0, (available_width - text_width) / 2)
    page.insert_text(
        (x, baseline_y),
        value,
        fontsize=font_size,
        fontname="helv",
        color=(0, 0, 0),
        overlay=True,
    )


def _first_label_rect(page, label: str, *, min_x: float | None = None):
    rects = _label_rects(page, label)
    if min_x is not None:
        rects = [rect for rect in rects if rect.x0 >= min_x]
    if not rects:
        return None
    return sorted(rects, key=lambda rect: (rect.y0, rect.x0))[0]


def _label_rects(page, label: str):
    """Busca etiquetas aunque el formato oficial cambie sus mayúsculas."""
    rects = []
    seen = set()
    for candidate in (label, label.upper(), label.capitalize()):
        for rect in page.search_for(candidate):
            key = tuple(round(value, 2) for value in rect)
            if key not in seen:
                seen.add(key)
                rects.append(rect)
    return rects


def _center_rect(x: float, y: float, width: float = 44, height: float = 12) -> tuple[float, float, float, float]:
    return (x - width / 2, y, x + width / 2, y + height)


def _cell_rect(x0: float, x1: float, y0: float, y1: float) -> tuple[float, float, float, float]:
    return (x0, y0, x1, y1)


def _draw_left_fit(
    page,
    x0: float,
    x1: float,
    baseline_y: float,
    text: str,
    *,
    size: float = 6.4,
) -> None:
    if not text:
        return
    value = str(text)[:90]
    font_size = size
    available_width = max(1, x1 - x0)
    try:
        text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
    except Exception:
        text_width = len(value) * font_size * 0.45
    while text_width > available_width and font_size > 4.2:
        font_size -= 0.3
        try:
            text_width = page.get_text_length(value, fontname="helv", fontsize=font_size)
        except Exception:
            text_width = len(value) * font_size * 0.45
    page.insert_text(
        (x0, baseline_y),
        value,
        fontsize=font_size,
        fontname="helv",
        color=(0, 0, 0),
        overlay=True,
    )


def _fill_company_header(page, request: dict, template_name: str) -> None:
    fecha_label = _first_label_rect(page, "Fecha:")
    sistema_label = _first_label_rect(page, "Sistema:")
    subsistema_label = _first_label_rect(page, "Subsistema:")
    tag_label = _first_label_rect(page, "TAG:")
    fabricante_label = _first_label_rect(page, "Fabricante:")
    if all((fecha_label, sistema_label, subsistema_label, tag_label, fabricante_label)):
        fecha = " ".join(
            item for item in (_request_text(request, "fecha"), _request_text(request, "hora")) if item
        )
        right_edge = page.rect.width - fecha_label.x0 - 14
        value_size = 6.4
        top_baseline = fecha_label.y1 - 1.2
        bottom_baseline = tag_label.y1 - 1.2

        _draw_centered_absolute(page, fecha_label.x1 + 4, sistema_label.x0 - 6, top_baseline, fecha, size=value_size)
        _draw_centered_absolute(page, sistema_label.x1 + 4, subsistema_label.x0 - 6, top_baseline, _request_text(request, "sistema"), size=value_size)
        _draw_centered_absolute(page, subsistema_label.x1 + 4, right_edge, top_baseline, _request_text(request, "subsistema") or _request_text(request, "equipo"), size=value_size)
        _draw_centered_absolute(page, tag_label.x1 + 4, fabricante_label.x0 - 6, bottom_baseline, _request_text(request, "tag"), size=value_size)
        _draw_centered_absolute(page, fabricante_label.x1 + 4, subsistema_label.x0 - 6, bottom_baseline, _request_info_text(request, "marca"), size=value_size)
        _draw_centered_absolute(page, subsistema_label.x0 + 24, right_edge, bottom_baseline, _request_info_text(request, "serial"), size=value_size)
        return

    header_rects = {
        "Motor-Bomba(A).pdf": {
            "fecha": (55, 153, 207, 166),
            "sistema": (242, 153, 350, 166),
            "subsistema": (402, 153, 528, 166),
            "tag": (55, 164, 207, 177),
            "marca": (252, 164, 350, 177),
            "serial": (371, 164, 528, 177),
        },
        "Motor-Bomba(B).pdf": {
            "fecha": (55, 171, 207, 184),
            "sistema": (242, 171, 350, 184),
            "subsistema": (402, 171, 528, 184),
            "tag": (55, 190, 207, 203),
            "marca": (252, 190, 350, 203),
            "serial": (371, 190, 528, 203),
        },
        "Motor-Caja-Bomba.pdf": {
            "fecha": (54, 134, 206, 146),
            "sistema": (235, 134, 358, 146),
            "subsistema": (400, 134, 567, 146),
            "tag": (45, 150, 206, 162),
            "marca": (245, 150, 358, 162),
            "serial": (384, 150, 567, 162),
        },
        "Motor-Ventilador(Fin-Fan).pdf": {
            "fecha": (55, 127, 214, 140),
            "sistema": (252, 127, 360, 140),
            "subsistema": (418, 127, 528, 140),
            "tag": (55, 147, 214, 160),
            "marca": (252, 147, 360, 160),
            "serial": (376, 147, 528, 160),
        },
        "Motor-Ventilador(Vent).pdf": {
            "fecha": (55, 168, 207, 181),
            "sistema": (242, 168, 350, 181),
            "subsistema": (402, 168, 528, 181),
            "tag": (55, 186, 207, 199),
            "marca": (252, 186, 350, 199),
            "serial": (371, 186, 528, 199),
        },
    }
    rects = header_rects[template_name]
    fecha = " ".join(
        item for item in (_request_text(request, "fecha"), _request_text(request, "hora")) if item
    )
    _draw_centered(page, rects["fecha"], fecha, size=6.4, baseline_shift=-5)
    _draw_centered(page, rects["sistema"], _request_text(request, "sistema"), size=6.4, baseline_shift=-5)
    _draw_centered(page, rects["subsistema"], _request_text(request, "subsistema") or _request_text(request, "equipo"), size=6.4, baseline_shift=-5)
    _draw_centered(page, rects["tag"], _request_text(request, "tag"), size=6.4, baseline_shift=-5)
    _draw_centered(page, rects["marca"], _request_info_text(request, "marca"), size=6.4, baseline_shift=-5)
    _draw_centered(page, rects["serial"], _request_info_text(request, "serial"), size=6.4, baseline_shift=-5)


def _fill_responsible_fields(page, request: dict) -> None:
    responsable = (
        _request_text(request, "responsable")
        or _request_text(request, "usuario")
        or _request_text(request, "USUARIO")
        or _request_text(request, "RESPONSABLE")
    )
    cargo = _request_text(request, "cargo") or _request_text(request, "CARGO")
    if not responsable and not cargo:
        return
    names = _label_rects(page, "Nombre:")
    cargos = _label_rects(page, "Cargo:")
    if not names and not cargos:
        return
    left_names = sorted(
        names,
        key=lambda rect: (0 if rect.x0 < page.rect.width / 2 else 1, -rect.y0),
    )
    left_cargos = sorted(
        cargos,
        key=lambda rect: (0 if rect.x0 < page.rect.width / 2 else 1, -rect.y0),
    )
    name_label = left_names[0] if left_names else None
    cargo_label = left_cargos[0] if left_cargos else None
    right_edge = page.rect.width / 2 - 8
    if name_label is not None:
        _draw_centered_absolute(
            page,
            name_label.x1 + 4,
            right_edge,
            name_label.y1 - 1.2,
            responsable,
            size=6.4,
        )
    if cargo_label is not None:
        _draw_centered_absolute(
            page,
            cargo_label.x1 + 4,
            right_edge,
            cargo_label.y1 - 1.2,
            cargo,
            size=6.4,
        )


def _fill_vibration_values(page, request: dict, template_name: str) -> None:
    positions = {
        "Motor-Bomba(A).pdf": {
            1: {"H": _cell_rect(27.6, 92.4, 452.3, 463.7), "V": _cell_rect(92.4, 155.3, 452.3, 463.7), "A": _cell_rect(155.3, 250.1, 452.3, 463.7)},
            2: {"H": _cell_rect(250.1, 362.7, 452.3, 463.7), "V": _cell_rect(362.7, 459.9, 452.3, 463.7), "A": _cell_rect(459.9, 554.0, 452.3, 463.7)},
            3: {"H": _cell_rect(27.6, 92.4, 516.5, 527.9), "V": _cell_rect(92.4, 155.3, 516.5, 527.9), "A": _cell_rect(155.3, 250.1, 516.5, 527.9)},
            4: {"H": _cell_rect(250.1, 362.7, 516.5, 527.9), "V": _cell_rect(362.7, 459.9, 516.5, 527.9), "A": _cell_rect(459.9, 554.0, 516.5, 527.9)},
        },
        "Motor-Bomba(B).pdf": {
            1: {"H": _cell_rect(26.4, 94.6, 459.5, 470.9), "V": _cell_rect(94.6, 161.5, 459.5, 470.9), "A": _cell_rect(161.5, 256.3, 459.5, 470.9)},
            2: {"H": _cell_rect(256.3, 354.7, 459.5, 470.9), "V": _cell_rect(354.7, 460.8, 459.5, 470.9), "A": _cell_rect(460.8, 563.0, 459.5, 470.9)},
            3: {"H": _cell_rect(26.4, 94.6, 534.3, 545.7), "V": _cell_rect(94.6, 161.5, 534.3, 545.7), "A": _cell_rect(161.5, 256.3, 534.3, 545.7)},
            4: {"H": _cell_rect(256.3, 354.7, 534.3, 545.7), "V": _cell_rect(354.7, 460.8, 534.3, 545.7), "A": _cell_rect(460.8, 563.0, 534.3, 545.7)},
        },
        "Motor-Caja-Bomba.pdf": {
            1: {"H": _cell_rect(27.4, 91.8, 503.1, 514.7), "V": _cell_rect(91.8, 155.5, 503.1, 514.7), "A": _cell_rect(155.5, 205.3, 503.1, 514.7)},
            2: {"H": _cell_rect(205.3, 253.3, 503.1, 514.7), "V": _cell_rect(253.3, 303.1, 503.1, 514.7), "A": _cell_rect(303.1, 357.1, 503.1, 514.7)},
            3: {"H": _cell_rect(357.1, 417.2, 503.1, 514.7), "V": _cell_rect(417.2, 474.2, 503.1, 514.7), "A": _cell_rect(474.2, 553.8, 503.1, 514.7)},
            4: {"H": _cell_rect(27.4, 91.8, 568.3, 580.0), "V": _cell_rect(91.8, 155.5, 568.3, 580.0), "A": _cell_rect(155.5, 205.3, 568.3, 580.0)},
            5: {"H": _cell_rect(205.3, 253.3, 568.3, 580.0), "V": _cell_rect(253.3, 303.1, 568.3, 580.0), "A": _cell_rect(303.1, 357.1, 568.3, 580.0)},
            6: {"H": _cell_rect(357.1, 417.2, 568.3, 580.0), "V": _cell_rect(417.2, 474.2, 568.3, 580.0), "A": _cell_rect(474.2, 553.8, 568.3, 580.0)},
        },
        "Motor-Ventilador(Fin-Fan).pdf": {
            1: {"H": _cell_rect(18.8, 106.6, 438.9, 450.5), "V": _cell_rect(106.6, 170.5, 438.9, 450.5), "A": _cell_rect(170.5, 267.7, 438.9, 450.5)},
            2: {"H": _cell_rect(267.7, 364.9, 438.9, 450.5), "V": _cell_rect(364.9, 473.8, 438.9, 450.5), "A": _cell_rect(473.8, 565.4, 438.9, 450.5)},
            3: {"H": _cell_rect(18.8, 219.1, 527.3, 538.9), "V": _cell_rect(219.1, 364.9, 527.3, 538.9), "A": _cell_rect(364.9, 565.4, 527.3, 538.9)},
        },
        "Motor-Ventilador(Vent).pdf": {
            1: {"H": _cell_rect(18.8, 147.5, 471.7, 483.1), "V": _cell_rect(147.5, 251.1, 471.7, 483.1)},
            2: {"H": _cell_rect(251.1, 402.1, 471.7, 483.1), "V": _cell_rect(402.1, 556.0, 471.7, 483.1)},
            3: {"H": _cell_rect(18.8, 147.5, 546.5, 557.9), "V": _cell_rect(147.5, 251.1, 546.5, 557.9)},
            4: {"H": _cell_rect(251.1, 402.1, 546.5, 557.9), "V": _cell_rect(402.1, 556.0, 546.5, 557.9)},
        },
    }
    try:
        pt_eq = int(request.get("pt_eq") or 0)
    except (TypeError, ValueError):
        pt_eq = 0
    source_map = PRINT_VALUE_SOURCE_POINTS_BY_PT_EQ.get(pt_eq, {})
    value_row_offset = 0
    value_baseline_shift = -0.6 if template_name == "Motor-Caja-Bomba.pdf" else -1.2
    for point, axes in positions[template_name].items():
        source_point = source_map.get(point, point)
        for axis, rect in axes.items():
            x0, y0, x1, y1 = rect
            value_rect = (x0, y0 + value_row_offset, x1, y1 + value_row_offset)
            _draw_centered(
                page,
                value_rect,
                _measurement_value(request, f"{axis}{source_point}"),
                size=9.0,
                baseline_shift=value_baseline_shift,
            )


def _fill_observations(page, request: dict, template_name: str) -> None:
    text = _request_text(request, "observaciones")
    if not text:
        return
    rectangles = {
        "Motor-Bomba(A).pdf": (55, 607, 540, 663),
        "Motor-Bomba(B).pdf": (115, 616, 520, 648),
        "Motor-Caja-Bomba.pdf": (55, 632, 540, 676),
        "Motor-Ventilador(Fin-Fan).pdf": (115, 588, 520, 620),
        "Motor-Ventilador(Vent).pdf": (115, 623, 520, 655),
    }
    rect = _scale_rect(page, rectangles[template_name])
    scaled_size = 7.5 * min(
        page.rect.width / TEMPLATE_BASE_WIDTH,
        page.rect.height / TEMPLATE_BASE_HEIGHT,
    )
    page.insert_textbox(
        rect,
        text[:250],
        fontsize=scaled_size,
        fontname="helv",
        color=(0, 0, 0),
        overlay=True,
    )


def _resolve_print_template(template_name: str) -> Path:
    aliases = PRINT_TEMPLATE_ALIASES.get(template_name, (template_name,))
    checked: list[str] = []

    for base_dir in (FORMATOS_DIR, LOCAL_FORMATOS_DIR, LEGACY_FORMATOS_DIR):
        for alias in aliases:
            candidate = base_dir / alias
            checked.append(str(candidate))
            if candidate.exists():
                if base_dir == FORMATOS_DIR:
                    try:
                        LOCAL_FORMATOS_DIR.mkdir(parents=True, exist_ok=True)
                        cached = LOCAL_FORMATOS_DIR / alias
                        if not cached.exists() or cached.stat().st_size != candidate.stat().st_size:
                            shutil.copy2(candidate, cached)
                    except OSError:
                        pass
                return candidate

    raise RuntimeError(
        "No encontre el formato oficial. Ponga los PDF en "
        f"{LOCAL_FORMATOS_DIR}, {LEGACY_FORMATOS_DIR} o conecte la ruta de red {FORMATOS_DIR}. "
        f"Busque: {', '.join(aliases)}"
    )


def build_company_template_pdf(request: dict, output_dir: Path) -> Path:
    try:
        import fitz
    except ImportError as exc:
        raise RuntimeError("Falta instalar PyMuPDF para rellenar formatos PDF oficiales.") from exc

    request = _request_with_print_system(request)

    try:
        pt_eq = int(request.get("pt_eq") or 0)
    except (TypeError, ValueError):
        pt_eq = 0

    template_name = PRINT_TEMPLATE_BY_PT_EQ.get(pt_eq)
    if not template_name:
        raise RuntimeError(f"No hay formato configurado para PUNTOS/PT_EQ {pt_eq}.")

    template_path = _resolve_print_template(template_name)

    output_dir.mkdir(parents=True, exist_ok=True)
    tag = _request_text(request, "tag") or f"LOC-{_request_text(request, 'localizacion')}"
    fecha = _request_text(request, "fecha") or datetime.now().strftime("%Y-%m-%d")
    file_name = _safe_pdf_name(f"SCV-PTBG {tag} {fecha}.pdf")
    output_path = output_dir / file_name

    # La impresión inmediata y la impresión por equipo deben usar exactamente
    # el mismo motor de llenado. El código anterior mantenía coordenadas de una
    # revisión vieja y superponía valores sobre títulos y bordes.
    if fill_official_form is not None:
        values = request.get("valores") if isinstance(request.get("valores"), dict) else {}
        normalized_values = {str(key).upper(): value for key, value in values.items()}
        selected_services: set[str] = set()
        if any(key.startswith(("H", "V", "A")) and key[1:].isdigit() for key in normalized_values):
            selected_services.add("vibration")
        if any(key.startswith("T") and key[1:].isdigit() for key in normalized_values):
            selected_services.add("temperature")
        if any(key.startswith("L") and key[1:].isdigit() for key in normalized_values):
            selected_services.add("lubrication")
        if any(key.startswith(("AMB_", "ACM_", "ACB_")) for key in normalized_values):
            selected_services.add("alignment")
        if not selected_services:
            selected_services.add("vibration")

        info = request.get("info") if isinstance(request.get("info"), dict) else {}
        current = {
            "MOTOR": {
                "brand": info.get("marca"),
                "model": info.get("modelo"),
                "serial": info.get("serial"),
            }
        }
        data = {
            "points": pt_eq,
            "date": " ".join(
                part for part in (
                    _request_text(request, "fecha"),
                    _request_text(request, "hora"),
                ) if part
            ),
            "tag": tag,
            "system": _request_text(request, "sistema"),
            "subsystem": _request_text(request, "subsistema") or _request_text(request, "equipo"),
            "current": current,
            "replacement": {},
            "temperature": {key: value for key, value in normalized_values.items() if key.startswith("T")},
            "lubrication": {key: value for key, value in normalized_values.items() if key.startswith("L")},
            "vibration": {
                key: value
                for key, value in normalized_values.items()
                if key[:1] in {"H", "V", "A"} and key[1:].isdigit()
            },
            "alignment": {
                key: value
                for key, value in normalized_values.items()
                if key.startswith(("AMB_", "ACM_", "ACB_"))
            },
            "coupling": request.get("coupling"),
            "belt": request.get("belt"),
            "belt_tension": request.get("belt_tension"),
            "observations": _request_text(request, "observaciones") or "/",
            "responsible": (
                _request_text(request, "responsable")
                or _request_text(request, "usuario")
                or "/"
            ),
            "role": _request_text(request, "cargo") or "/",
        }
        return fill_official_form(
            template_path,
            output_path,
            data,
            selected_services,
        )

    doc = fitz.open(str(template_path))
    page = doc[0]
    _fill_company_header(page, request, template_name)
    _fill_vibration_values(page, request, template_name)
    _fill_observations(page, request, template_name)
    _fill_responsible_fields(page, request)

    letter_doc = fitz.open()
    letter_page = letter_doc.new_page(width=LETTER_WIDTH, height=LETTER_HEIGHT)
    letter_page.show_pdf_page(
        fitz.Rect(0, 0, LETTER_WIDTH, LETTER_HEIGHT),
        doc,
        0,
        keep_proportion=False,
    )
    letter_doc.save(str(output_path), garbage=4, deflate=True)
    letter_doc.close()
    doc.close()
    return output_path


def list_windows_printers() -> list[str]:
    script = (
        "Get-Printer | "
        "Where-Object { $_.Name } | "
        "Select-Object -ExpandProperty Name | "
        "ConvertTo-Json"
    )
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            capture_output=True,
            text=True,
            timeout=15,
            creationflags=_hidden_process_flags(),
            startupinfo=_hidden_startup_info(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0 or not result.stdout.strip():
        return []
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return []
    if isinstance(data, str):
        return [data]
    if isinstance(data, list):
        return [str(item) for item in data if item]
    return []


def get_windows_default_printer() -> str:
    script = "(Get-CimInstance Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1 -ExpandProperty Name)"
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            capture_output=True,
            text=True,
            timeout=10,
            creationflags=_hidden_process_flags(),
            startupinfo=_hidden_startup_info(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def load_selected_printer() -> str:
    try:
        data = json.loads(PRINTER_SETTINGS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    printer = data.get("printer") if isinstance(data, dict) else ""
    return str(printer).strip() if printer else ""


def save_selected_printer(printer_name: str) -> None:
    PRINTER_SETTINGS_FILE.write_text(
        json.dumps({"printer": printer_name}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def set_windows_default_printer(printer_name: str) -> None:
    if not printer_name:
        return
    printers = list_windows_printers()
    if printer_name not in printers:
        raise RuntimeError(f"La impresora configurada no esta instalada: {printer_name}")
    result = subprocess.run(
        ["rundll32", "printui.dll,PrintUIEntry", "/y", "/n", printer_name],
        capture_output=True,
        text=True,
        timeout=15,
        creationflags=_hidden_process_flags(),
        startupinfo=_hidden_startup_info(),
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"No pude seleccionar la impresora {printer_name}. {detail}")


def get_printer_status(printer_name: str) -> str:
    script = (
        f"Get-Printer -Name {_powershell_literal(printer_name)} | "
        "Select-Object -ExpandProperty PrinterStatus"
    )
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            capture_output=True,
            text=True,
            timeout=10,
            creationflags=_hidden_process_flags(),
            startupinfo=_hidden_startup_info(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def ensure_printer_ready(printer_name: str) -> None:
    status = get_printer_status(printer_name)
    blocked = {
        "Offline": "La impresora esta fuera de linea.",
        "Error": "La impresora reporta error.",
        "TonerLow": "La impresora reporta toner/tinta baja.",
        "NotAvailable": "La impresora no esta disponible.",
        "NoToner": "La impresora reporta que no tiene toner/tinta.",
        "OutputBinFull": "La bandeja de salida esta llena.",
        "PaperJam": "La impresora tiene papel atascado.",
    }
    if status in blocked:
        raise RuntimeError(f"{blocked[status]} Revise {printer_name} y vuelva a intentar.")


def _render_pdf_for_print(pdf_path: Path) -> Path:
    try:
        import fitz
    except ImportError as exc:
        raise RuntimeError("Falta PyMuPDF para imprimir sin visor PDF.") from exc

    image_path = pdf_path.with_suffix(".print.png")
    doc = fitz.open(str(pdf_path))
    try:
        page = doc[0]
        pix = page.get_pixmap(matrix=fitz.Matrix(3, 3), alpha=False)
        pix.save(str(image_path))
    finally:
        doc.close()
    return image_path


def _powershell_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _print_image_with_powershell(image_path: Path, printer_name: str) -> None:
    if not printer_name:
        raise RuntimeError("No hay impresora seleccionada para imprimir.")
    script = f"""
Add-Type -AssemblyName System.Drawing
$imagePath = {_powershell_literal(str(image_path))}
$printerName = {_powershell_literal(printer_name)}
$image = [System.Drawing.Image]::FromFile($imagePath)
$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.PrinterSettings.PrinterName = $printerName
$doc.DocumentName = [System.IO.Path]::GetFileName($imagePath)
$doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
$doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("Letter", 850, 1100)
$doc.DefaultPageSettings.Landscape = $false
# Margen de 0.20" (20 centesimas de pulgada) por lado. Con margen cero el
# formato se escalaba contra la hoja fisica completa y el borde no imprimible
# de la impresora se comia los bordes: el reporte salia cortado.
$doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(20, 20, 20, 20)
# Coloca el origen del dibujo en la esquina del margen. Sin esto el origen cae
# en el area imprimible y el contenido queda ademas desplazado hacia abajo.
$doc.OriginAtMargins = $true
if (-not $doc.PrinterSettings.IsValid) {{
    throw "La impresora no es valida o no esta disponible: $printerName"
}}
$doc.add_PrintPage({{
    param($sender, $eventArgs)
    # MarginBounds es el area util; PageBounds es la hoja entera e incluye el
    # borde que la impresora no puede pintar.
    $bounds = $eventArgs.MarginBounds
    $ratioX = $bounds.Width / $image.Width
    $ratioY = $bounds.Height / $image.Height
    $ratio = [Math]::Min($ratioX, $ratioY)
    $width = [int]($image.Width * $ratio)
    $height = [int]($image.Height * $ratio)
    $x = [int](($bounds.Width - $width) / 2)
    $y = [int](($bounds.Height - $height) / 2)
    $eventArgs.Graphics.DrawImage($image, $x, $y, $width, $height)
    $eventArgs.HasMorePages = $false
}})
try {{
    $doc.Print()
}} finally {{
    $image.Dispose()
    $doc.Dispose()
}}
"""
    script_path = image_path.with_suffix(".print.ps1")
    script_path.write_text(script, encoding="utf-8")
    subprocess.Popen(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script_path),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=_hidden_process_flags(),
        startupinfo=_hidden_startup_info(),
    )


def open_and_print_pdf(pdf_path: Path) -> str:
    selected_printer = load_selected_printer()
    if selected_printer:
        set_windows_default_printer(selected_printer)
    printer_label = selected_printer or get_windows_default_printer()
    if not printer_label:
        raise RuntimeError("Seleccione una impresora en el programa Python antes de imprimir.")
    ensure_printer_ready(printer_label)

    try:
        os.startfile(str(pdf_path))
    except OSError as exc:
        pdf_open_detail = f"No hay visor PDF asociado ({exc})."
    else:
        pdf_open_detail = "Documento abierto."

    image_path = _render_pdf_for_print(pdf_path)
    _print_image_with_powershell(image_path, printer_label)
    return f"{pdf_open_detail} Enviado a {printer_label}: {pdf_path.name}"


def open_pdf(pdf_path: Path) -> str:
    """Abre un PDF en la laptop sin enviarlo automáticamente a imprimir."""
    try:
        os.startfile(str(pdf_path))
    except OSError as exc:
        raise RuntimeError(f"No hay un visor PDF asociado en Windows: {exc}") from exc
    return f"Reporte guardado y abierto: {pdf_path}"


def process_tablet_print_request(
    device: Device,
    tmp_dir: Path,
    processed_ids: set[str],
    log: Callable[[str], None] = print,
) -> bool:
    request = read_tablet_usb_print_request(device.serial)
    if not request:
        return False

    request_id = str(request.get("id") or "")
    claimed, request_key, lock_fd = _claim_print_request(request)
    if not claimed:
        if lock_fd is None:
            return False
        clear_tablet_usb_print_request(device.serial)
        log(f"Solicitud de impresion duplicada ignorada: {request_id or request_key}")
        set_tablet_usb_status(
            device.serial,
            status="DONE",
            detail="Solicitud de impresion duplicada ignorada.",
            tmp_dir=tmp_dir,
        )
        _release_print_request_lock(lock_fd)
        return True
    _release_print_request_lock(lock_fd)
    if request_id:
        processed_ids.add(request_id)

    clear_tablet_usb_print_request(device.serial)
    log(f"Solicitud de impresion recibida desde tablet: {request_id or 'sin id'}")

    try:
        action = str(request.get("action") or "")
        open_only = False
        if action == "official_form_print":
            if build_official_report_from_db is None:
                raise RuntimeError("No esta disponible el generador de formatos oficiales.")
            try:
                localizacion = int(request.get("localizacion") or 0)
            except (TypeError, ValueError):
                localizacion = 0
            if localizacion <= 0:
                raise RuntimeError("La solicitud no identifica el equipo.")
            requested = request.get("report_types")
            if not isinstance(requested, list) or not requested:
                requested = [str(request.get("report_type") or "integral").strip().lower()]
            try:
                odt = int(request.get("odt")) if request.get("odt") is not None else None
            except (TypeError, ValueError):
                odt = None
            set_tablet_usb_status(
                device.serial,
                status="SYNCING",
                detail="Leyendo historial del equipo y preparando el reporte...",
                tmp_dir=tmp_dir,
                request_id=request_id,
            )
            tablet_db = pull_tablet_database(device.serial, tmp_dir)
            output_dir = Path.home() / "Documents" / "SCV-PTBG Reportes"
            current_components = None
            uninstalled_components = None
            try:
                sqlite_conn = sqlite3.connect(tablet_db)
                sqlite_conn.row_factory = sqlite3.Row
                equipment_row = sqlite_conn.execute(
                    """
                    SELECT CODE_SYS, COALESCE(NULLIF(PT_EQ, 0), PUNTOS, 1) AS points
                    FROM EQUIPOS WHERE LOCALIZACION = ? LIMIT 1
                    """,
                    (localizacion,),
                ).fetchone()
                sqlite_conn.close()
                if equipment_row:
                    current_components = fetch_current_equipment_components(
                        localizacion,
                        int(equipment_row["CODE_SYS"] or 0),
                        int(equipment_row["points"] or 1),
                    )
                    uninstalled_components = apply_components_before_replacement(
                        tablet_db,
                        localizacion,
                        int(equipment_row["CODE_SYS"] or 0),
                        odt,
                        current_components,
                    )
            except Exception as component_error:
                log(f"Aviso: no se pudieron leer placas actuales: {component_error}")
            pdf_path = build_official_report_from_db(
                tablet_db,
                localizacion,
                requested,
                output_dir,
                LOCAL_FORMATOS_DIR,
                odt,
                current_components,
                uninstalled_components,
            )
            open_only = not bool(request.get("print", False))
        elif action == "black_start_print":
            if build_black_start_pdf is None:
                raise RuntimeError(
                    "No esta disponible el generador del check list de black start."
                )
            uuid = str(request.get("uuid") or "").strip()
            if not uuid:
                raise RuntimeError("La solicitud no identifica el check list.")
            set_tablet_usb_status(
                device.serial,
                status="SYNCING",
                detail="Preparando el check list del black start...",
                tmp_dir=tmp_dir,
                request_id=request_id,
            )
            # Se lee de la planta: lo impreso es lo que quedo registrado.
            maria = connect_mariadb()
            try:
                with maria.cursor() as cur:
                    cur.execute(
                        "SELECT * FROM MOT_BLKS_CHKL WHERE UUID = %s LIMIT 1",
                        (uuid,),
                    )
                    fila = cur.fetchone()
            finally:
                maria.close()
            if not fila:
                raise RuntimeError(
                    "El check list todavia no esta en la planta. "
                    "Sincroniza antes de imprimirlo."
                )
            output_dir = Path.home() / "Documents" / "SCV-PTBG Impresiones"
            pdf_path = build_black_start_pdf(dict(fila), output_dir)
            open_only = not bool(request.get("print", False))
        elif action == "compressor_checklist_print":
            if build_compressor_checklist_pdf is None:
                raise RuntimeError(
                    "No esta disponible el generador del check list de compresores."
                )
            uuid = str(request.get("uuid") or "").strip()
            if not uuid:
                raise RuntimeError("La solicitud no identifica el check list.")
            set_tablet_usb_status(
                device.serial,
                status="SYNCING",
                detail="Preparando el check list del compresor...",
                tmp_dir=tmp_dir,
                request_id=request_id,
            )
            # Se lee de la planta y no de la tablet: asi lo impreso es
            # exactamente lo que quedo registrado, ya con su ID definitivo.
            maria = connect_mariadb()
            try:
                with maria.cursor() as cur:
                    cur.execute(
                        "SELECT * FROM MOT_COMP_CHKL WHERE UUID = %s LIMIT 1",
                        (uuid,),
                    )
                    fila = cur.fetchone()
                    if fila:
                        cur.execute(
                            "SELECT * FROM MOT_COMP_CHKL WHERE LOCALIZACION = %s",
                            (fila.get("LOCALIZACION"),),
                        )
                        historial_mantenimiento = cur.fetchall()
                        # El subsistema se toma de MOT_EQUIPO.NAME_SYS_2, que
                        # es donde la planta lo mantiene, y no del que quedo
                        # copiado en el check list al capturarlo. Esa copia es
                        # una foto del dia: si despues se corrige el
                        # subsistema en la base, el papel seguiria saliendo
                        # con el viejo y nadie se enteraria.
                        cur.execute(
                            "SELECT NAME_SYS_2 FROM MOT_EQUIPO "
                            "WHERE LOCALIZACION = %s LIMIT 1",
                            (fila.get("LOCALIZACION"),),
                        )
                        equipo = cur.fetchone()
                        if equipo and (equipo.get("NAME_SYS_2") or "").strip():
                            fila = dict(fila)
                            fila["SUBSISTEMA"] = _repair_text(
                                str(equipo["NAME_SYS_2"]).strip()
                            )
            finally:
                maria.close()
            if not fila:
                raise RuntimeError(
                    "El check list todavia no esta en la planta. "
                    "Sincroniza antes de imprimirlo."
                )
            output_dir = Path.home() / "Documents" / "SCV-PTBG Impresiones"
            pdf_path = build_compressor_checklist_pdf(
                dict(fila), output_dir, historial=historial_mantenimiento,
            )
            open_only = not bool(request.get("print", False))
        elif action == "equipment_report":
            if build_equipment_report_pdf is None:
                raise RuntimeError("No esta disponible el generador de reportes comparativos.")
            try:
                localizacion = int(request.get("localizacion") or 0)
            except (TypeError, ValueError):
                localizacion = 0
            if localizacion <= 0:
                raise RuntimeError("La solicitud no identifica el equipo.")
            # La tablet manda report_types con TODO lo que se marco; report_type
            # es solo el primero. Usar el singular imprimia un sistema y perdia
            # el resto sin avisar, aunque la hoja dice "uno o varios".
            report_type = request.get("report_types")
            if not isinstance(report_type, list) or not report_type:
                report_type = str(request.get("report_type") or "integral").strip().lower()
            try:
                measurement_count = int(request.get("measurement_count") or 5)
            except (TypeError, ValueError):
                measurement_count = 5
            set_tablet_usb_status(
                device.serial,
                status="SYNCING",
                detail="Preparando reporte comparativo del equipo...",
                tmp_dir=tmp_dir,
                request_id=request_id,
            )
            tablet_db = pull_tablet_database(device.serial, tmp_dir)
            # El reporte salia con lo que hubiera dejado la ULTIMA descarga,
            # que podia tener semanas: por eso "los ultimos 5" del PDF no
            # coincidian con MariaDB. Se refresca la copia local ANTES de
            # generar; si MariaDB no responde, el reporte sale con lo de la
            # tablet y el log lo dice. La copia refrescada NO se empuja a la
            # tablet: esto es solo para el PDF.
            try:
                sync_latest_measurements_from_mariadb(tablet_db, log=log)
                sync_latest_temperatures_from_mariadb(tablet_db, log=log)
                sync_alignment_history_from_mariadb(tablet_db, log=log)
                sync_lubrication_history_from_mariadb(tablet_db, log=log)
            except Exception as exc:
                log(f"Reporte con datos de la tablet: MariaDB no disponible ({exc})")
            output_dir = Path.home() / "Documents" / "SCV-PTBG Reportes"
            pdf_path = build_equipment_report_pdf(
                tablet_db, localizacion, report_type, output_dir, measurement_count
            )
            open_only = True
        elif action == "print_measurement":
            output_dir = Path.home() / "Documents" / "SCV-PTBG Impresiones"
            default_responsable, default_cargo = read_tablet_operator(device.serial)
            if (
                default_responsable
                and not _request_text(request, "responsable")
                and not _request_text(request, "usuario")
                and not _request_text(request, "USUARIO")
                and not _request_text(request, "RESPONSABLE")
            ):
                request = dict(request)
                request["responsable"] = default_responsable
            if default_cargo and not _request_text(request, "cargo") and not _request_text(request, "CARGO"):
                request = dict(request)
                request["cargo"] = default_cargo
            if not _request_text(request, "subsistema"):
                try:
                    localizacion = int(request.get("localizacion") or 0)
                except (TypeError, ValueError):
                    localizacion = 0
                if localizacion > 0:
                    try:
                        tablet_db = pull_tablet_database(device.serial, tmp_dir)
                        subsistema = _sqlite_print_subsystem(tablet_db, localizacion)
                    except Exception:
                        subsistema = ""
                    if subsistema:
                        request = dict(request)
                        request["subsistema"] = subsistema
            pdf_path = build_company_template_pdf(request, output_dir)
        else:
            output_dir = Path.home() / "Documents" / "SCV-PTBG Impresiones"
            pdf_base64 = str(request.get("pdf_base64") or "")
            if not pdf_base64:
                raise RuntimeError("La solicitud no trajo PDF.")
            safe_name = _safe_pdf_name(str(request.get("file_name") or "SCV-PTBG_medicion.pdf"))
            output_dir.mkdir(parents=True, exist_ok=True)
            pdf_path = output_dir / safe_name
            pdf_path.write_bytes(base64.b64decode(pdf_base64))

        set_tablet_usb_status(
            device.serial,
            status="SYNCING",
            detail=f"Abriendo {pdf_path.name}" if open_only else f"Abriendo e imprimiendo {pdf_path.name}",
            tmp_dir=tmp_dir,
            request_id=request_id,
        )

        detail = open_pdf(pdf_path) if open_only else open_and_print_pdf(pdf_path)

        set_tablet_usb_status(
            device.serial,
            status="DONE",
            detail=detail,
            tmp_dir=tmp_dir,
            request_id=request_id,
        )
        log(detail)
    except Exception as exc:
        set_tablet_usb_status(
            device.serial,
            status="ERROR",
            detail=f"Error imprimiendo desde laptop: {exc}",
            tmp_dir=tmp_dir,
            request_id=request_id,
        )
        log(f"ERROR impresion tablet: {exc}")
    return True


def run_status_daemon(log_path: Path | None = None) -> None:
    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", 38721))
        lock.listen(1)
    except OSError:
        return

    log_path = log_path or Path(__file__).with_name("usb_status_daemon.log")

    def daemon_log(message: str) -> None:
        stamp = datetime.now().isoformat(timespec="seconds")
        try:
            with log_path.open("a", encoding="utf-8") as fh:
                fh.write(f"{stamp} {message}\n")
        except Exception:
            pass

    daemon_log("daemon iniciado")
    work = tempfile.TemporaryDirectory(prefix="scv_ptbg_status_")
    processed_ids: set[str] = set()
    try:
        while True:
            try:
                devices = list_devices()
                ready = [device for device in devices if device.state == "device"]
                if ready:
                    handled_print = process_tablet_print_request(
                        ready[0],
                        Path(work.name),
                        processed_ids,
                        log=daemon_log,
                    )
                    if handled_print:
                        time.sleep(45)
                        continue
                    handled = process_tablet_usb_request(
                        ready[0],
                        Path(work.name),
                        processed_ids,
                        log=daemon_log,
                    )
                    if handled:
                        time.sleep(45)
                        continue
                    set_tablet_usb_status(
                        ready[0].serial,
                        status="ONLINE",
                        detail="Laptop conectada",
                        tmp_dir=Path(work.name),
                    )
                    daemon_log(f"ONLINE {ready[0].serial}")
                else:
                    daemon_log("OFFLINE sin tablet autorizada")
            except Exception as exc:
                daemon_log(f"ERROR {exc}")
            time.sleep(4)
    finally:
        work.cleanup()


def acquire_gui_instance_lock() -> socket.socket | None:
    """Permite una sola ventana del cargador para evitar monitores duplicados."""
    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", 38722))
        lock.listen(1)
        return lock
    except OSError:
        lock.close()
        return None


def launch_gui() -> None:
    import tkinter as tk
    from tkinter import messagebox, ttk

    root = tk.Tk()
    root.title("SCV-PTBG - Subir mediciones USB desde laptop")
    root.geometry("980x680")
    root.minsize(900, 620)
    root.configure(bg="#F2F5FA")

    palette = {
        "header_top": "#0A1C3E",
        "header_bottom": "#0D3B6E",
        "bg": "#F2F5FA",
        "bg2": "#E8EDF5",
        "panel": "#FFFFFF",
        "panel_soft": "#F8FAFD",
        "ink": "#1A2B4A",
        "muted": "#6B7C9A",
        "hint": "#CBD5E1",
        "line": "#E2E8F0",
        "line_dark": "#CBD5E1",
        "teal": "#00B89C",
        "teal_dark": "#009B82",
        "teal_light": "#E6F7F4",
        "warning": "#F59E0B",
        "warning_bg": "#FFFBEB",
        "red": "#EF4444",
        "red_bg": "#FEF2F2",
        "info": "#3B82F6",
        "info_bg": "#EFF6FF",
        "green": "#00B89C",
    }

    style = ttk.Style(root)
    style.theme_use("clam")
    style.configure("App.TFrame", background=palette["bg"])
    style.configure("Panel.TFrame", background=palette["panel"], relief="flat")
    style.configure("Soft.TFrame", background=palette["panel_soft"], relief="flat")
    style.configure("Header.TFrame", background=palette["header_top"])
    style.configure("Title.TLabel", background=palette["header_top"], foreground="#FFFFFF", font=("Segoe UI", 22, "bold"))
    style.configure("Subtitle.TLabel", background=palette["header_top"], foreground="#D8E5F5", font=("Segoe UI", 10))
    style.configure("PanelTitle.TLabel", background=palette["panel"], foreground=palette["ink"], font=("Segoe UI", 11, "bold"))
    style.configure("Muted.TLabel", background=palette["panel"], foreground=palette["muted"], font=("Segoe UI", 9))
    style.configure("Metric.TLabel", background=palette["panel"], foreground=palette["ink"], font=("Segoe UI", 20, "bold"))
    style.configure("MetricName.TLabel", background=palette["panel"], foreground=palette["muted"], font=("Segoe UI", 8, "bold"))
    style.configure("Status.TLabel", background=palette["panel_soft"], foreground=palette["muted"], font=("Segoe UI", 9))
    style.configure("Primary.TButton", font=("Segoe UI", 10, "bold"), padding=(18, 12), foreground="#ffffff", background=palette["teal"])
    style.map("Primary.TButton", background=[("active", palette["teal_dark"]), ("disabled", "#94a3b8")])
    style.configure("Secondary.TButton", font=("Segoe UI", 10, "bold"), padding=(18, 12), foreground=palette["ink"], background=palette["bg2"])
    style.map("Secondary.TButton", background=[("active", palette["line_dark"]), ("disabled", "#e5e7eb")])
    style.configure("Treeview", rowheight=30, font=("Segoe UI", 9), background="#ffffff", fieldbackground="#ffffff", foreground=palette["ink"], bordercolor=palette["line"])
    style.configure("Treeview.Heading", font=("Segoe UI", 9, "bold"), background=palette["bg2"], foreground=palette["ink"])
    style.configure("Horizontal.TProgressbar", troughcolor=palette["bg2"], background=palette["teal"], bordercolor=palette["bg2"], lightcolor=palette["teal"], darkcolor=palette["teal_dark"])

    status = tk.StringVar(
        value="Abra este programa en la laptop, conecte la tablet por USB y presione Detectar."
    )
    device_var = tk.StringVar(value="Tablet: no detectada")
    connection_var = tk.StringVar(value="OFFLINE")
    pending_var = tk.StringVar(value="Pendientes: -")
    uploaded_var = tk.StringVar(value="0")
    failed_var = tk.StringVar(value="0")
    status_badge = tk.StringVar(value="OFFLINE")
    printer_var = tk.StringVar(value="")
    printer_status_var = tk.StringVar(value="Impresora: sin configurar")

    frame = ttk.Frame(root, padding=22, style="App.TFrame")
    frame.pack(fill="both", expand=True)
    frame.columnconfigure(0, weight=1)
    frame.rowconfigure(4, weight=1)

    header = ttk.Frame(frame, padding=18, style="Header.TFrame")
    header.grid(row=0, column=0, sticky="ew")
    header.columnconfigure(0, weight=1)
    ttk.Label(header, text="SCV-PTBG", style="Title.TLabel").grid(row=0, column=0, sticky="w")
    ttk.Label(
        header,
        text="Subida USB desde laptop a MariaDB. La tablet no usa WiFi para sincronizar.",
        style="Subtitle.TLabel",
    ).grid(row=1, column=0, sticky="w", pady=(2, 0))

    badge = tk.Label(
        header,
        textvariable=status_badge,
        bg=palette["teal_light"],
        fg=palette["teal_dark"],
        padx=14,
        pady=7,
        font=("Segoe UI", 8, "bold"),
    )
    badge.grid(row=0, column=1, rowspan=2, sticky="e")

    top = ttk.Frame(frame, style="App.TFrame")
    top.grid(row=1, column=0, sticky="ew", pady=(18, 14))
    for idx in range(5):
        top.columnconfigure(idx, weight=1)

    def metric(parent, col: int, title: str, value_var: tk.StringVar, color: str) -> None:
        card = ttk.Frame(parent, padding=16, style="Panel.TFrame")
        card.grid(row=0, column=col, sticky="ew", padx=(0 if col == 0 else 6, 0 if col == 4 else 6))
        ttk.Label(card, text=title.upper(), style="MetricName.TLabel").pack(anchor="w")
        tk.Label(card, textvariable=value_var, bg=palette["panel"], fg=color, font=("Segoe UI", 22, "bold")).pack(anchor="w", pady=(4, 0))

    metric(top, 0, "Conexion USB", connection_var, palette["red"])
    metric(top, 1, "Tablet", device_var, palette["teal"])
    metric(top, 2, "Pendientes", pending_var, palette["warning"])
    metric(top, 3, "Subidas", uploaded_var, palette["green"])
    metric(top, 4, "Errores", failed_var, palette["red"])

    status_panel = ttk.Frame(frame, padding=(16, 12), style="Soft.TFrame")
    status_panel.grid(row=2, column=0, sticky="ew", pady=(0, 14))
    status_panel.columnconfigure(0, weight=1)
    ttk.Label(status_panel, textvariable=status, style="Status.TLabel").grid(row=0, column=0, sticky="w")
    progress = ttk.Progressbar(status_panel, mode="indeterminate", style="Horizontal.TProgressbar")
    progress.grid(row=1, column=0, sticky="ew", pady=(10, 0))

    printer_panel = ttk.Frame(frame, padding=(16, 12), style="Panel.TFrame")
    printer_panel.grid(row=3, column=0, sticky="ew", pady=(0, 14))
    printer_panel.columnconfigure(1, weight=1)
    ttk.Label(printer_panel, text="Impresora", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 12))
    printer_combo = ttk.Combobox(
        printer_panel,
        textvariable=printer_var,
        state="readonly",
        font=("Segoe UI", 9),
    )
    printer_combo.grid(row=0, column=1, sticky="ew", padx=(0, 8))
    ttk.Button(printer_panel, text="Refrescar", style="Secondary.TButton", command=lambda: refresh_printers()).grid(row=0, column=2, padx=(0, 8))
    ttk.Button(printer_panel, text="Guardar predeterminada", style="Primary.TButton", command=lambda: save_printer_from_ui()).grid(row=0, column=3)
    ttk.Label(printer_panel, textvariable=printer_status_var, style="Muted.TLabel").grid(row=1, column=1, columnspan=3, sticky="w", pady=(8, 0))

    content = ttk.Frame(frame, style="App.TFrame")
    content.grid(row=4, column=0, sticky="nsew")
    content.columnconfigure(0, weight=3)
    content.columnconfigure(1, weight=2)
    content.rowconfigure(0, weight=1)

    table_panel = ttk.Frame(content, padding=14, style="Panel.TFrame")
    table_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
    table_panel.rowconfigure(1, weight=1)
    table_panel.columnconfigure(0, weight=1)
    ttk.Label(table_panel, text="Mediciones pendientes", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
    columns = ("loc", "fecha", "rms", "obs")
    pending_table = ttk.Treeview(table_panel, columns=columns, show="headings", selectmode="browse")
    pending_table.heading("loc", text="LOC")
    pending_table.heading("fecha", text="Fecha y hora")
    pending_table.heading("rms", text="RMS")
    pending_table.heading("obs", text="Observacion")
    pending_table.column("loc", width=70, anchor="center", stretch=False)
    pending_table.column("fecha", width=150, stretch=False)
    pending_table.column("rms", width=70, anchor="center", stretch=False)
    pending_table.column("obs", width=260)
    pending_table.grid(row=1, column=0, sticky="nsew")
    table_scroll = ttk.Scrollbar(table_panel, orient="vertical", command=pending_table.yview)
    table_scroll.grid(row=1, column=1, sticky="ns")
    pending_table.configure(yscrollcommand=table_scroll.set)

    log_panel = ttk.Frame(content, padding=14, style="Panel.TFrame")
    log_panel.grid(row=0, column=1, sticky="nsew", padx=(8, 0))
    log_panel.rowconfigure(1, weight=1)
    log_panel.columnconfigure(0, weight=1)
    ttk.Label(log_panel, text="Confirmaciones", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
    log_box = tk.Text(
        log_panel,
        height=14,
        wrap="word",
        bd=0,
        padx=12,
        pady=12,
        bg=palette["header_top"],
        fg="#E8EDF5",
        insertbackground="#E8EDF5",
        font=("Consolas", 9),
    )
    log_box.grid(row=1, column=0, sticky="nsew")
    log_box.tag_configure("ok", foreground=palette["teal"])
    log_box.tag_configure("warn", foreground="#FCD34D")
    log_box.tag_configure("err", foreground="#FCA5A5")
    log_box.tag_configure("info", foreground="#D8E5F5")

    buttons = ttk.Frame(frame, style="App.TFrame")
    buttons.grid(row=5, column=0, sticky="ew", pady=(16, 0))
    buttons.columnconfigure(2, weight=1)

    state = {
        "device": None,
        "db": None,
        "tmp": None,
        "heartbeat_stop": None,
        "monitor_stop": threading.Event(),
        "monitor_tmp": tempfile.TemporaryDirectory(prefix="scv_ptbg_monitor_"),
        "processed_requests": set(),
    }

    def set_badge(text: str, bg: str, fg: str) -> None:
        status_badge.set(text)
        badge.configure(bg=bg, fg=fg)

    def set_connection(label: str, detail: str) -> None:
        connection_var.set(label)
        shown_detail = detail
        if label == "ONLINE":
            shown_detail = detail if detail.startswith("TAB") else "Tablet conectada"
        elif detail.startswith("ADB:") or "run-as" in detail or " sh -c " in detail:
            shown_detail = "Revise conexion ADB"
            log(detail[:900])
        device_var.set(shown_detail)
        if label == "ONLINE":
            set_badge("ONLINE", palette["teal_light"], palette["teal_dark"])
        else:
            set_badge("OFFLINE", palette["red_bg"], palette["red"])

    def log(message: str) -> None:
        if message.startswith("Subida confirmada"):
            tag = "ok"
        elif message.startswith("Ya existia"):
            tag = "warn"
        elif message.startswith("ERROR") or message.startswith("Error"):
            tag = "err"
        else:
            tag = "info"

        def append() -> None:
            log_box.insert("end", message + "\n", tag)
            log_box.see("end")

        root.after(0, append)

    def refresh_printers() -> None:
        printers = list_windows_printers()
        current_saved = load_selected_printer()
        windows_default = get_windows_default_printer()
        preferred = current_saved if current_saved in printers else windows_default
        printer_combo.configure(values=printers)
        if preferred in printers:
            printer_var.set(preferred)
        elif printers:
            printer_var.set(printers[0])
        else:
            printer_var.set("")

        saved_label = load_selected_printer() or "sin configurar"
        if printers:
            printer_status_var.set(
                f"Predeterminada SCV-PTBG: {saved_label}. Windows: {windows_default or 'sin predeterminada'}"
            )
        else:
            printer_status_var.set("No encontre impresoras instaladas en Windows.")

    def save_printer_from_ui() -> None:
        printer = printer_var.get().strip()
        if not printer:
            messagebox.showwarning("SCV-PTBG", "No hay impresora seleccionada.")
            return
        try:
            save_selected_printer(printer)
            set_windows_default_printer(printer)
        except Exception as exc:
            messagebox.showerror("SCV-PTBG", str(exc))
            log(f"ERROR impresora: {exc}")
            return
        printer_status_var.set(f"Predeterminada SCV-PTBG: {printer}")
        log(f"Impresora predeterminada SCV-PTBG: {printer}")

    def render_pending(rows: list[dict]) -> None:
        def update() -> None:
            pending_table.delete(*pending_table.get_children())
            for row in rows:
                pending_table.insert(
                    "",
                    "end",
                    values=(
                        row.get("LOCALIZACION") or "-",
                        f"{row.get('FECHA') or ''} {row.get('HORA') or ''}".strip(),
                        row.get("RMS") if row.get("RMS") is not None else "-",
                        row.get("OBSERVACIONES") or "",
                    ),
                )

        root.after(0, update)

    def run_background(fn) -> None:
        for child in buttons.winfo_children():
            child.configure(state="disabled")
        root.after(0, progress.start)

        def worker() -> None:
            try:
                fn()
            except Exception as exc:
                log(f"ERROR: {exc}")
                root.after(0, lambda: set_badge("ERROR", palette["red_bg"], palette["red"]))
                root.after(0, lambda: messagebox.showerror("SCV-PTBG", str(exc)))
            finally:
                root.after(0, progress.stop)
                root.after(0, lambda: [child.configure(state="normal") for child in buttons.winfo_children()])

        threading.Thread(target=worker, daemon=True).start()

    def start_connection_monitor() -> None:
        def monitor() -> None:
            last_label = None
            last_detail = None
            while not state["monitor_stop"].wait(4):
                # Solo un fallo al listar dispositivos significa que se perdio
                # la tablet. Antes cualquier error de aqui adentro -incluido uno
                # de impresion- marcaba OFFLINE con la tablet perfectamente
                # conectada, y ademas se etiquetaba como "ADB:".
                try:
                    devices = list_devices()
                except Exception as exc:
                    log("No pude listar dispositivos por ADB:\n" + traceback.format_exc())
                    root.after(
                        0,
                        lambda e=exc: set_connection("OFFLINE", f"ADB: {e}"),
                    )
                    continue

                try:
                    label, detail = tablet_connection_status(devices)
                    if label != last_label or detail != last_detail:
                        root.after(0, lambda l=label, d=detail: set_connection(l, d))
                        last_label, last_detail = label, detail

                    ready = [device for device in devices if device.state == "device"]
                    if ready:
                        handled_print = process_tablet_print_request(
                            ready[0],
                            Path(state["monitor_tmp"].name),
                            state["processed_requests"],
                            log=log,
                        )
                        if handled_print:
                            continue
                        handled = process_tablet_usb_request(
                            ready[0],
                            Path(state["monitor_tmp"].name),
                            state["processed_requests"],
                            log=log,
                        )
                        if handled:
                            continue
                        set_tablet_usb_status(
                            ready[0].serial,
                            status="ONLINE",
                            detail="Laptop conectada",
                            tmp_dir=Path(state["monitor_tmp"].name),
                        )
                except Exception:
                    # La tablet sigue conectada: se registra el fallo completo
                    # en el log en vez de perder el traceback y cambiar a
                    # OFFLINE por algo que no es la conexion.
                    log("Fallo atendiendo la tablet:\n" + traceback.format_exc())

        threading.Thread(target=monitor, daemon=True).start()

    def start_heartbeat(serial: str) -> None:
        previous = state.get("heartbeat_stop")
        if previous is not None:
            previous.set()

        stop_event = threading.Event()
        state["heartbeat_stop"] = stop_event

        def beat() -> None:
            while not stop_event.wait(4):
                try:
                    set_tablet_usb_status(
                        serial,
                        status="ONLINE",
                        detail="Laptop conectada",
                        tmp_dir=Path(state["tmp"].name) if state.get("tmp") else None,
                    )
                except Exception as exc:
                    log(f"Error actualizando estado USB en tablet: {exc}")
                    break

        threading.Thread(target=beat, daemon=True).start()

    def on_close() -> None:
        stop_event = state.get("heartbeat_stop")
        if stop_event is not None:
            stop_event.set()
        state["monitor_stop"].set()
        state["monitor_tmp"].cleanup()
        root.destroy()

    def detect() -> None:
        devices = list_devices()
        label, detail = tablet_connection_status(devices)
        root.after(0, lambda: set_connection(label, detail))
        device = select_ready_device(devices)
        tmp = tempfile.TemporaryDirectory(prefix="scv_ptbg_gui_")
        set_tablet_usb_status(
            device.serial,
            status="ONLINE",
            detail="Laptop conectada",
            tmp_dir=Path(tmp.name),
        )
        db_path = pull_tablet_database(device.serial, Path(tmp.name))
        try:
            sync_equipo_info_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Catalogo tecnico no actualizado: {exc}")
        try:
            sync_users_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Usuarios no actualizados: {exc}")
        try:
            sync_latest_measurements_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Ultimas mediciones no actualizadas: {exc}")
        try:
            sync_latest_temperatures_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Temperaturas historicas no actualizadas: {exc}")
        try:
            sync_alignment_history_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Alineaciones historicas no actualizadas: {exc}")
        try:
            sync_lubrication_history_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Lubricaciones historicas no actualizadas: {exc}")
        # Tambien aqui: esta ruta baja datos y empuja la base.
        try:
            sync_purge_deleted_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Purga de borrados no aplicada: {exc}")
        push_tablet_database(device.serial, db_path)
        pending = pending_rows_for_display(db_path)
        state.update({"device": device, "db": db_path, "tmp": tmp})
        start_heartbeat(device.serial)
        render_pending(pending)
        root.after(0, lambda: set_connection("ONLINE", device.serial))
        root.after(0, lambda: pending_var.set(str(len(pending))))
        root.after(0, lambda: uploaded_var.set("0"))
        root.after(0, lambda: failed_var.set("0"))
        root.after(0, lambda: status.set("Tablet lista. Puede subir las mediciones."))
        log(f"Tablet detectada: {device.serial}")
        log(f"Registros pendientes: {len(pending)}")

    def upload() -> None:
        devices = list_devices()
        device = select_ready_device(devices)
        tmp = tempfile.TemporaryDirectory(prefix="scv_ptbg_gui_upload_")
        state.update({"device": device, "tmp": tmp})
        start_heartbeat(device.serial)
        root.after(0, lambda: set_connection("ONLINE", device.serial))
        root.after(0, lambda: status.set("Subiendo mediciones a MariaDB desde la laptop..."))
        root.after(0, lambda: set_badge("SUBIENDO", palette["info_bg"], palette["info"]))

        set_tablet_usb_status(
            device.serial,
            status="SYNCING",
            detail="Leyendo base actual de la tablet...",
            tmp_dir=Path(tmp.name),
        )
        db_path = pull_tablet_database(device.serial, Path(tmp.name))
        state["db"] = db_path
        default_responsable, default_cargo = read_tablet_operator(device.serial)

        try:
            sync_equipo_info_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Catalogo tecnico no actualizado: {exc}")
        try:
            sync_users_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Usuarios no actualizados: {exc}")

        pending_measurements = fetch_pending_measurements(db_path)
        pending_temperatures = fetch_pending_temperatures(db_path)
        pending_alignments = fetch_pending_alignments(db_path)
        pending_replacements = fetch_pending_replacements(db_path)
        pending_now = pending_rows_for_display(db_path)
        all_local = fetch_local_measurements(db_path, only_pending=False)
        log(f"Mediciones pendientes encontradas: {len(pending_measurements)}")
        log(f"Temperaturas pendientes encontradas: {len(pending_temperatures)}")
        log(f"Alineaciones pendientes encontradas: {len(pending_alignments)}")
        log(f"Componentes de reemplazo pendientes: {len(pending_replacements)}")
        log(f"Mediciones locales en tablet: {len(all_local)}")
        root.after(0, lambda: pending_var.set(str(len(pending_now))))
        render_pending(pending_now)

        summary = upload_pending_work(
            db_path,
            default_responsable=default_responsable,
            default_cargo=default_cargo,
            log=log,
        )
        try:
            sync_latest_measurements_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Ultimas mediciones no actualizadas: {exc}")
        try:
            sync_latest_temperatures_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Temperaturas historicas no actualizadas: {exc}")
        try:
            sync_alignment_history_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Alineaciones historicas no actualizadas: {exc}")
        try:
            sync_lubrication_history_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Lubricaciones historicas no actualizadas: {exc}")
        try:
            sync_equipo_info_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Catalogo tecnico no actualizado: {exc}")
        try:
            sync_users_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Usuarios no actualizados: {exc}")
        # Lo borrado a mano en la planta se va tambien de la tablet. Va en
        # toda ruta que baje datos y empuje la base: si solo estuviera en
        # la descarga, subir pendientes devolveria los datos viejos.
        try:
            sync_purge_deleted_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Purga de borrados no aplicada: {exc}")
        push_tablet_database(device.serial, db_path)
        set_tablet_usb_status(
            device.serial,
            status="DONE" if summary.failed == 0 else "ERROR",
            detail=(
                f"Proceso terminado: {summary.uploaded} subidas, "
                f"{summary.skipped} ya existentes, {summary.failed} errores"
            ),
            tmp_dir=Path(tmp.name),
        )
        remaining = pending_rows_for_display(db_path)
        render_pending(remaining)
        root.after(0, lambda: pending_var.set(str(len(remaining))))
        root.after(0, lambda: uploaded_var.set(str(summary.uploaded + summary.skipped)))
        root.after(0, lambda: failed_var.set(str(summary.failed)))
        root.after(0, lambda: status.set("Subida finalizada. Revise las confirmaciones."))
        root.after(0, lambda: set_badge("FINALIZADO", palette["teal_light"], palette["teal_dark"]))
        root.after(
            0,
            lambda: messagebox.showinfo(
                "SCV-PTBG",
                f"Subidas: {summary.uploaded}\n"
                f"Ya existentes: {summary.skipped}\n"
                f"Con error: {summary.failed}",
            ),
        )

    ttk.Button(buttons, text="Detectar tablet", style="Secondary.TButton", command=lambda: run_background(detect)).grid(row=0, column=0, sticky="w")
    ttk.Button(buttons, text="Subir pendientes", style="Primary.TButton", command=lambda: run_background(upload)).grid(row=0, column=1, sticky="w", padx=10)
    ttk.Button(buttons, text="Cerrar", style="Secondary.TButton", command=on_close).grid(row=0, column=3, sticky="e")

    root.protocol("WM_DELETE_WINDOW", on_close)
    refresh_printers()
    start_connection_monitor()
    root.mainloop()


if __name__ == "__main__":
    if "--status-daemon" in sys.argv:
        run_status_daemon()
    elif "--cli" in sys.argv:
        run_usb_upload()
    else:
        _gui_instance_lock = acquire_gui_instance_lock()
        if _gui_instance_lock is not None:
            launch_gui()
