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
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Callable, Iterable

try:
    import pymysql
except ImportError:  # pragma: no cover - se informa en runtime al operador.
    pymysql = None

DB_HOST = os.getenv("SCV_DB_HOST", "172.16.200.2")
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
)

INSERT_SQL = f"""
INSERT INTO MOT_VIBR_MUES
({",".join(INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(INSERT_COLUMNS))})
"""

TEMPERATURE_COLUMNS = tuple(f"T{point}" for point in range(1, 11))
TEMPERATURE_INSERT_COLUMNS = (
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
    "FECHA", "HORA", "SISTEMA", "LOCALIZACION", *ALIGNMENT_COLUMNS,
    "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
)
ALIGNMENT_INSERT_SQL = f"""
INSERT INTO MOT_ALN_REG
({",".join(ALIGNMENT_INSERT_COLUMNS)})
VALUES ({",".join(["%s"] * len(ALIGNMENT_INSERT_COLUMNS))})
"""

REPLACEMENT_TABLES = {
    1: ("MOT_DATA", "Motor"),
    2: ("MOT_BOMB_DATA", "Bomba"),
    3: ("MOT_CAJA_DATA", "Caja"),
    4: ("MOT_VENT_DATA", "Ventilador"),
}

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
    sdk_adb = Path.home() / "AppData" / "Local" / "Android" / "Sdk" / "platform-tools" / "adb.exe"
    if sdk_adb.exists():
        return str(sdk_adb)
    found = shutil.which("adb")
    if found:
        return found
    raise FileNotFoundError("No se encontro adb.exe. Instale Android Platform Tools.")


def run_adb(args: Iterable[str], *, serial: str | None = None, timeout: int = 30) -> subprocess.CompletedProcess:
    cmd = [find_adb()]
    if serial:
        cmd += ["-s", serial]
    cmd += list(args)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


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
    if data.get("action") != "upload_pending":
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
    if data.get("action") not in {"print_pdf", "print_measurement"}:
        return None
    return data


def clear_tablet_usb_print_request(serial: str) -> None:
    run_adb(
        ["shell", "run-as", PACKAGE_NAME, "rm", "-f", REMOTE_USB_PRINT_REQUEST],
        serial=serial,
        timeout=10,
    )


def _print_request_key(request: dict) -> str:
    if str(request.get("action") or "") == "print_measurement":
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


def _normalize_alignment_row(row: dict) -> dict:
    normalized = {
        "uuid": row.get("uuid"),
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
            placeholders = ",".join(["%s"] * len(localizaciones))
            with maria.cursor() as cur:
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
                        RPM AS rpm
                    FROM MOT_DATA
                    WHERE UBICACION IN ({placeholders})
                    """,
                    tuple(localizaciones),
                )
                rows = cur.fetchall()
                cur.execute(
                    f"""
                    SELECT
                        LOCALIZACION AS localizacion,
                        s.SISTEMA AS sistema,
                        e.NAME_SYS_2 AS subsistema
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
            (localizacion, marca, serial, modelo, hp, start, volts, fla, sf, hz, rpm)
            VALUES
            (:localizacion, :marca, :serial, :modelo, :hp, :start, :volts, :fla, :sf, :hz, :rpm)
            """,
            rows,
        )
        conn.commit()
        conn.executemany(
            """
            UPDATE EQUIPOS
            SET
              SISTEMA = COALESCE(:sistema, SISTEMA),
              SUBSISTEMA = :subsistema
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
                SELECT ID AS id, USUARIO AS usuario, CARGO AS cargo
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
              cargo    TEXT
            )
            """
        )
        conn.execute("DELETE FROM USUARIOS")
        conn.executemany(
            """
            INSERT OR REPLACE INTO USUARIOS (id, usuario, cargo)
            VALUES (:id, :usuario, :cargo)
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


def _replacement_text(value: object) -> str:
    return str(value or "").strip()


def apply_replacement_row(cursor, row: dict) -> str:
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

    cursor.execute(
        f"""
        SELECT ID, {", ".join(selected_columns)}
        FROM `{table}`
        WHERE UBICACION = %s AND CODE_CONJUNTO = %s
        LIMIT 1
        FOR UPDATE
        """,
        (localizacion, code_conjunto),
    )
    current = cursor.fetchone()
    if not current:
        insert_columns = [
            "FECHA",
            "HORA",
            *selected_columns,
            "UBICACION",
            "CODE_CONJUNTO",
        ]
        insert_values = [
            fecha,
            hora,
            *(new_values_by_column[column] for column in selected_columns),
            localizacion,
            code_conjunto,
        ]
        if equipment_type == 1:
            insert_columns.append("ACTIVO")
            insert_values.append(1)
        cursor.execute(
            f"""
            INSERT INTO `{table}`
              ({", ".join(insert_columns)})
            VALUES ({", ".join(["%s"] * len(insert_columns))})
            """,
            tuple(insert_values),
        )
        return "created"

    current_values = tuple(
        _replacement_text(current.get(key)).upper()
        for key in selected_columns
    )
    new_values = tuple(
        new_values_by_column[key].upper() for key in selected_columns
    )
    if current_values == new_values:
        return "skipped"

    cursor.execute(
        """
        INSERT INTO MOT_LOG_RPL
          (FECHA, HORA, MARCA, MODELO, SERIAL, EQUIPO, UBICACION, CODE_CONJUNTO)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
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
        ),
    )
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
                    outcomes = [apply_replacement_row(cursor, row) for row in operation_rows]
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


def upload_pending_work(
    db_path: Path,
    *,
    default_responsable: str = "",
    default_cargo: str = "",
    log: Callable[[str], None] = print,
) -> UploadSummary:
    measurement_summary = upload_pending(
        db_path,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
        log=log,
    )
    replacement_summary = upload_pending_replacements(db_path, log=log)
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
    return merge_upload_summaries(
        measurement_summary,
        replacement_summary,
        temperature_summary,
        alignment_summary,
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
    pending_replacements = fetch_pending_replacements(local_db)
    all_local = fetch_local_measurements(local_db, only_pending=False)
    log(f"Mediciones pendientes encontradas: {len(pending)}")
    log(f"Temperaturas pendientes encontradas: {len(pending_temperatures)}")
    log(f"Alineaciones pendientes encontradas: {len(pending_alignments)}")
    log(f"Componentes de reemplazo pendientes: {len(pending_replacements)}")
    log(f"Mediciones locales en tablet: {len(all_local)}")
    summary = upload_pending_work(
        local_db,
        default_responsable=default_responsable,
        default_cargo=default_cargo,
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
        sync_equipo_info_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Catalogo tecnico no actualizado: {exc}")
    try:
        sync_users_from_mariadb(local_db, log=log)
    except Exception as exc:
        log(f"Usuarios no actualizados: {exc}")
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
        perform_usb_upload_for_device(
            device,
            tmp_dir,
            log=log,
            request_id=request_id,
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
    rects = page.search_for(label)
    if min_x is not None:
        rects = [rect for rect in rects if rect.x0 >= min_x]
    if not rects:
        return None
    return sorted(rects, key=lambda rect: (rect.y0, rect.x0))[0]


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
    names = page.search_for("Nombre:")
    cargos = page.search_for("Cargo:")
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
$doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
if (-not $doc.PrinterSettings.IsValid) {{
    throw "La impresora no es valida o no esta disponible: $printerName"
}}
$doc.add_PrintPage({{
    param($sender, $eventArgs)
    $bounds = $eventArgs.PageBounds
    $ratioX = $bounds.Width / $image.Width
    $ratioY = $bounds.Height / $image.Height
    $ratio = [Math]::Min($ratioX, $ratioY)
    $width = [int]($image.Width * $ratio)
    $height = [int]($image.Height * $ratio)
    $x = $bounds.Left + [int](($bounds.Width - $width) / 2)
    $y = $bounds.Top + [int](($bounds.Height - $height) / 2)
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
        output_dir = Path.home() / "Documents" / "SCV-PTBG Impresiones"
        action = str(request.get("action") or "")
        if action == "print_measurement":
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
            detail=f"Abriendo e imprimiendo {pdf_path.name}",
            tmp_dir=tmp_dir,
        )

        detail = open_and_print_pdf(pdf_path)

        set_tablet_usb_status(
            device.serial,
            status="DONE",
            detail=detail,
            tmp_dir=tmp_dir,
        )
        log(detail)
    except Exception as exc:
        set_tablet_usb_status(
            device.serial,
            status="ERROR",
            detail=f"Error imprimiendo desde laptop: {exc}",
            tmp_dir=tmp_dir,
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
                try:
                    devices = list_devices()
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
                except Exception as exc:
                    root.after(
                        0,
                        lambda e=exc: set_connection("OFFLINE", f"ADB: {e}"),
                    )

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
            sync_equipo_info_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Catalogo tecnico no actualizado: {exc}")
        try:
            sync_users_from_mariadb(db_path, log=log)
        except Exception as exc:
            log(f"Usuarios no actualizados: {exc}")
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
        launch_gui()
