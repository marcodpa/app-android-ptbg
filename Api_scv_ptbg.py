"""
SCV-PTBG — API REST
Base oficial: PTBG_DAT
Tablas:
  - MOT_EQUIPO   : catálogo de equipos
  - MOT_DATA     : datos técnicos / placa
  - MOT_SYSTEM   : sistemas
  - MOT_VIBR_MUES: mediciones de vibración

Instalar:
  pip install fastapi uvicorn pymysql python-jose[cryptography] passlib[bcrypt]

Ejecutar:
  python Api_scv_ptbg.py
"""

from fastapi import FastAPI, HTTPException, Depends, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from starlette.middleware.base import BaseHTTPMiddleware
from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Any
from datetime import datetime, timedelta
from decimal import Decimal
from jose import JWTError, jwt
from passlib.context import CryptContext
import pymysql
import pymysql.cursors
import os
import re

# ── Config ────────────────────────────────────────────────────────────
DB_HOST = os.getenv("SCV_DB_HOST", "172.16.200.2")
DB_PORT = int(os.getenv("SCV_DB_PORT", "3306"))
DB_USER = os.getenv("SCV_DB_USER", "admin")
DB_PASS = os.getenv("SCV_DB_PASSWORD", "")
DB_NAME = os.getenv("SCV_DB_NAME", "PTBG_DAT")

SECRET_KEY = os.getenv("SCV_SECRET_KEY", "cambiar-esta-clave-en-produccion")
ALGORITHM = "HS256"
TOKEN_HOURS = 12

USUARIOS_FALLBACK = {
    "admin": {
        "rol": "admin",
        "nombre": "Administrador",
        "cargo": "ADMIN",
    },
}

# ── App ───────────────────────────────────────────────────────────────
app = FastAPI(title="SCV-PTBG API", version="2.0.0")
pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer = HTTPBearer(auto_error=False)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

class PrivateNetworkMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["Access-Control-Allow-Private-Network"] = "true"
        response.headers["Access-Control-Allow-Origin"] = "*"
        return response

app.add_middleware(PrivateNetworkMiddleware)

# ── DB ────────────────────────────────────────────────────────────────
def get_db():
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

# ── JWT ───────────────────────────────────────────────────────────────
def create_token(data: dict):
    exp = datetime.utcnow() + timedelta(hours=TOKEN_HOURS)
    return jwt.encode({**data, "exp": exp}, SECRET_KEY, algorithm=ALGORITHM)

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Token requerido")
    try:
        return jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Token invalido")

# ── Modelos ───────────────────────────────────────────────────────────
class LoginReq(BaseModel):
    username: str
    password: str = ""

class MedicionReq(BaseModel):
    uuid: str
    localizacion: int
    sistema: str
    fecha: str
    hora: str
    H1: Optional[float] = None
    V1: Optional[float] = None
    A1: Optional[float] = None
    H2: Optional[float] = None
    V2: Optional[float] = None
    A2: Optional[float] = None
    H3: Optional[float] = None
    V3: Optional[float] = None
    A3: Optional[float] = None
    H4: Optional[float] = None
    V4: Optional[float] = None
    A4: Optional[float] = None
    H5: Optional[float] = None
    V5: Optional[float] = None
    A5: Optional[float] = None
    H6: Optional[float] = None
    V6: Optional[float] = None
    A6: Optional[float] = None
    H7: Optional[float] = None
    V7: Optional[float] = None
    A7: Optional[float] = None
    H8: Optional[float] = None
    V8: Optional[float] = None
    A8: Optional[float] = None
    H9: Optional[float] = None
    V9: Optional[float] = None
    A9: Optional[float] = None
    RMS: Optional[float] = None
    OBSERVACIONES: Optional[str] = None
    USUARIO: Optional[str] = None
    RESPONSABLE: Optional[str] = None
    CARGO: Optional[str] = None
    MARCA: Optional[str] = None
    MODELO: Optional[str] = None
    SERIAL: Optional[str] = None
    usuario: Optional[str] = None
    tablet_id: Optional[str] = None

class TemperatureReq(BaseModel):
    uuid: str
    localizacion: int = Field(gt=0)
    sistema: str
    fecha: str
    hora: str
    T1: float = 0.0
    T2: float = 0.0
    T3: float = 0.0
    T4: float = 0.0
    T5: float = 0.0
    T6: float = 0.0
    T7: float = 0.0
    T8: float = 0.0
    T9: float = 0.0
    T10: float = 0.0
    OBSERVACIONES: Optional[str] = None
    USUARIO: Optional[str] = None
    CARGO: Optional[str] = None
    MARCA: Optional[str] = None
    MODELO: Optional[str] = None
    SERIAL: Optional[str] = None
    ODT: Optional[int] = None

    @field_validator("T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10", mode="before")
    @classmethod
    def default_missing_temperature(cls, value):
        return 0.0 if value is None else value

class SyncReq(BaseModel):
    mediciones: List[MedicionReq]

class ReplacementItem(BaseModel):
    equipo: int
    marca: str
    modelo: str
    serial: str

class ReplacementReq(BaseModel):
    localizacion: int
    code_conjunto: int
    componentes: List[ReplacementItem]

# ── Helpers ───────────────────────────────────────────────────────────
def _clean(value: Any, fallback: Optional[str] = None) -> Optional[str]:
    if value is None:
        return fallback
    value = str(value).strip()
    if value == "" or value.upper() in {"NULL", "NONE", "N/A"}:
        return fallback
    return value

_REPLACEMENT_TABLES = {
    1: ("MOT_DATA", "Motor"),
    2: ("MOT_BOMB_DATA", "Bomba"),
    3: ("MOT_CAJA_DATA", "Caja"),
    4: ("MOT_VENT_DATA", "Ventilador"),
}

def _execute_replacements(
    cur,
    request: ReplacementReq,
    *,
    fecha: str,
    hora: str,
) -> dict:
    if request.localizacion <= 0 or request.code_conjunto <= 0:
        raise HTTPException(
            status_code=422,
            detail="LOCALIZACION y CODE_CONJUNTO deben ser mayores que cero",
        )
    if not request.componentes:
        raise HTTPException(status_code=422, detail="Seleccione al menos un componente")

    seen = set()
    created = []
    updated = []
    unchanged = []

    for component in request.componentes:
        table_info = _REPLACEMENT_TABLES.get(component.equipo)
        if table_info is None:
            raise HTTPException(
                status_code=422,
                detail=f"Tipo de equipo invalido: {component.equipo}",
            )
        if component.equipo in seen:
            raise HTTPException(
                status_code=422,
                detail=f"El componente {component.equipo} esta repetido",
            )
        seen.add(component.equipo)

        table, label = table_info
        marca = _clean(component.marca)
        modelo = _clean(component.modelo)
        serial = _clean(component.serial)
        if not marca or not modelo or not serial:
            raise HTTPException(
                status_code=422,
                detail=f"Marca, modelo y serial son obligatorios para {label}",
            )

        cur.execute(
            f"""
                SELECT ID, MARCA, MODELO, SERIAL
                FROM `{table}`
                WHERE UBICACION = %s AND CODE_CONJUNTO = %s
                LIMIT 1
                FOR UPDATE
            """,
            (request.localizacion, request.code_conjunto),
        )
        current = cur.fetchone()
        if not current:
            cur.execute(
                f"""
                    INSERT INTO `{table}`
                        (FECHA, HORA, MARCA, MODELO, SERIAL,
                         UBICACION, CODE_CONJUNTO)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    fecha,
                    hora,
                    marca,
                    modelo,
                    serial,
                    request.localizacion,
                    request.code_conjunto,
                ),
            )
            created.append(label)
            continue

        current_values = tuple(
            (_clean(current.get(key), "") or "").upper()
            for key in ("MARCA", "MODELO", "SERIAL")
        )
        new_values = tuple(value.upper() for value in (marca, modelo, serial))
        if current_values == new_values:
            unchanged.append(label)
            continue

        cur.execute(
            """
                INSERT INTO MOT_LOG_RPL
                    (FECHA, HORA, MARCA, MODELO, SERIAL,
                     EQUIPO, UBICACION, CODE_CONJUNTO)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                fecha,
                hora,
                current.get("MARCA"),
                current.get("MODELO"),
                current.get("SERIAL"),
                component.equipo,
                request.localizacion,
                request.code_conjunto,
            ),
        )
        cur.execute(
            f"""
                UPDATE `{table}`
                SET FECHA = %s, HORA = %s, MARCA = %s, MODELO = %s, SERIAL = %s
                WHERE ID = %s
            """,
            (fecha, hora, marca, modelo, serial, current["ID"]),
        )
        updated.append(label)

    return {
        "creados": len(created),
        "actualizados": len(updated),
        "sin_cambios": len(unchanged),
        "componentes_creados": created,
        "componentes_actualizados": updated,
        "componentes_sin_cambios": unchanged,
    }

def _norm_user(value: str) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip()).upper()

def _user_from_mdb(username: str) -> Optional[dict]:
    wanted = _norm_user(username)
    if not wanted:
        return None

    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(
                """
                SELECT ID, USUARIO, CARGO
                FROM MDB_USERS
                WHERE UPPER(TRIM(USUARIO)) = %s
                ORDER BY ID DESC
                LIMIT 1
                """,
                (wanted,),
            )
            row = cur.fetchone()
            if not row:
                return None
            nombre = _clean(row.get("USUARIO"), username) or username
            cargo = _clean(row.get("CARGO"), "MECANICO") or "MECANICO"
            return {
                "id": row.get("ID"),
                "username": nombre,
                "nombre": nombre,
                "cargo": cargo,
                "rol": "mecanico",
                "source": "MDB_USERS",
            }
    finally:
        db.close()

def _list_mdb_users() -> list[dict]:
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(
                """
                SELECT ID, USUARIO, CARGO
                FROM MDB_USERS
                WHERE COALESCE(TRIM(USUARIO), '') <> ''
                ORDER BY USUARIO
                """
            )
            rows = cur.fetchall()
            return [
                {
                    "id": row.get("ID"),
                    "username": _clean(row.get("USUARIO"), "") or "",
                    "nombre": _clean(row.get("USUARIO"), "") or "",
                    "responsable": _clean(row.get("USUARIO"), "") or "",
                    "cargo": _clean(row.get("CARGO"), "MECANICO") or "MECANICO",
                    "rol": "mecanico",
                }
                for row in rows
            ]
    finally:
        db.close()

def _normalize_qr(value: str) -> str:
    """Acepta QR numérico, PTBG-004, MOT-6241, URL con code=, etc."""
    if value is None:
        return ""
    code = str(value).strip()
    if "/" in code:
        code = code.rstrip("/").split("/")[-1]
    if "code=" in code.lower():
        code = code.split("=")[-1]
    code = code.strip().upper()
    # PTBG-004 -> 4
    m = re.fullmatch(r"PTBG[-_ ]*(\d+)", code)
    if m:
        return str(int(m.group(1)))
    # LOC-004 -> 4
    m = re.fullmatch(r"LOC[-_ ]*(\d+)", code)
    if m:
        return str(int(m.group(1)))
    return code

def _measurement_dt(row: dict) -> datetime:
    fecha = str(row.get("FECHA") or "").strip()
    hora = str(row.get("HORA") or "").strip() or "00:00:00"
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%d/%m/%Y %H:%M:%S",
        "%d/%m/%Y %H:%M",
        "%d/%m/%y %H:%M:%S",
        "%d/%m/%y %H:%M",
    ):
        try:
            return datetime.strptime(f"{fecha} {hora}", fmt)
        except ValueError:
            pass
    return datetime.fromtimestamp(0)

def _newest_measurement(rows: list[dict]) -> Optional[dict]:
    if not rows:
        return None
    return max(rows, key=lambda r: (_measurement_dt(r), int(r.get("ID") or 0)))

_TEMPERATURE_SELECT = """
    SELECT ID, FECHA, HORA, SISTEMA, LOCALIZACION,
           T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
           OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT
    FROM MOT_TEMP_MUES
"""

_TEMPERATURE_DATE_SQL = """
    COALESCE(
        STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
        STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')
    )
"""

def _temperature_row(row: dict) -> dict:
    mapped = {}
    for key, value in row.items():
        if isinstance(value, Decimal):
            mapped[key] = float(value)
        elif hasattr(value, "isoformat"):
            mapped[key] = value.isoformat()
        else:
            mapped[key] = value
    return mapped

def _normalized_temperature_number(value) -> Decimal:
    if value is None or str(value).strip() == "":
        return Decimal("0.00")
    return Decimal(str(value).strip().replace(",", ".")).quantize(Decimal("0.01"))

def _normalized_temperature_text(value) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip()).upper()

def _temperature_sample_signature(sample: dict) -> tuple:
    temperatures = tuple(
        _normalized_temperature_number(sample.get(f"T{index}"))
        for index in range(1, 11)
    )
    text_fields = tuple(
        _normalized_temperature_text(sample.get(field))
        for field in (
            "SISTEMA",
            "OBSERVACIONES",
            "USUARIO",
            "CARGO",
            "MARCA",
            "MODELO",
            "SERIAL",
        )
    )
    raw_odt = sample.get("ODT")
    odt = None if raw_odt is None or str(raw_odt).strip() == "" else int(raw_odt)
    return temperatures + text_fields + (odt,)

def _equipo_defaults(row: dict) -> dict:
    """
    Convierte la estructura oficial PTBG_DAT a nombres compatibles con Flutter.

    MOT_EQUIPO:
      ID, CODE_SYS, EQUIPO, LOCALIZACION, NAME_SYS_1, NAME_SYS_2,
      CODE_QR, PUNTOS, TAGNAME

    MOT_DATA:
      UBICACION, MARCA, MODELO, SERIAL, VOLTAJE, CORRIENTE, RPM, SF, HP, etc.
    """
    localizacion = row.get("LOCALIZACION")
    code_qr = _clean(row.get("CODE_QR"))
    tagname = _clean(row.get("TAGNAME"))
    qr_final = code_qr or str(localizacion or "")

    puntos = row.get("PUNTOS")
    try:
        puntos = int(puntos) if puntos is not None else 1
    except Exception:
        puntos = 1

    # Campos compatibles con app vieja
    row["ID"] = row.get("ID")
    row["CODE_SYS"] = row.get("CODE_SYS")
    row["LOCALIZACION"] = localizacion
    row["QR_CODE"] = qr_final
    row["PUNTOS"] = puntos
    row["NUM_PUNTOS"] = puntos
    row["PT_EQ"] = puntos  # Alias temporal para código Flutter que aún espere PT_EQ.
    row["TAGNAME"] = tagname or ""
    row["TG_EQ"] = tagname or ""  # Alias temporal para código Flutter viejo.

    row["SISTEMA"] = (
        _clean(row.get("SISTEMA"))
        or _clean(row.get("NAME_SYS"))
        or _clean(row.get("NAME_SYS_1"))
        or "Sin sistema"
    )
    row["SUBSISTEMA"] = _clean(row.get("NAME_SYS_2"), "")
    row["SS_EQ"] = row["SUBSISTEMA"]

    # Info técnica desde MOT_DATA. Se envían nombres nuevos y aliases viejos.
    row["MARCA_INFO"] = _clean(row.get("MARCA"), "Sin datos")
    row["SERIAL_INFO"] = _clean(row.get("SERIAL"), "Sin datos")
    row["MODEL_INFO"] = _clean(row.get("MODELO"), "Sin datos")
    row["MODELO_INFO"] = row["MODEL_INFO"]
    row["HP_INFO"] = _clean(row.get("HP"), "Sin datos")
    row["VOLTS_INFO"] = _clean(row.get("VOLTAJE"), "Sin datos")
    row["VOLTAJE_INFO"] = row["VOLTS_INFO"]
    row["CORRIENTE_INFO"] = _clean(row.get("CORRIENTE"), "Sin datos")
    row["FLA_INFO"] = row["CORRIENTE_INFO"]
    row["RPM_INFO"] = _clean(row.get("RPM"), "Sin datos")
    row["SF_INFO"] = _clean(row.get("SF"), "Sin datos")
    row["FRAME_INFO"] = _clean(row.get("FRAME"), "Sin datos")
    row["START_INFO"] = _clean(row.get("ARRANQUE"), "Sin datos")
    row["ARRANQUE_INFO"] = row["START_INFO"]
    row["PH_INFO"] = _clean(row.get("PH"), "Sin datos")
    row["TENSION_INFO"] = _clean(row.get("TENSION"), "Sin datos")
    row["LUBRICACION_INFO"] = _clean(row.get("LUBRICACION"), "Sin datos")
    row["BRGS_DRIVE_INFO"] = _clean(row.get("BRGS_DRIVE"), "Sin datos")
    row["BRGS_OPP_INFO"] = _clean(row.get("BRGS_OPP"), "Sin datos")
    row["CICLO_INFO"] = _clean(row.get("CICLO"), "Sin datos")
    row["HZ_INFO"] = _clean(row.get("CICLO"), "Sin datos")

    # Tipo visual/axial para compatibilidad.
    row["TIPO_EQUIPO"] = str(puntos)
    row["TIENE_AXIAL"] = 1

    return row

# ── Endpoints ─────────────────────────────────────────────────────────
@app.options("/{path:path}")
async def options_handler(path: str):
    return Response(headers={
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Allow-Private-Network": "true",
    })

@app.get("/estado")
def estado():
    return {
        "status": "ok",
        "sistema": "SCV-PTBG",
        "version": "2.0.0",
        "db": DB_NAME,
        "equipos": "MOT_EQUIPO",
        "data": "MOT_DATA",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }

@app.post("/login")
def login(req: LoginReq):
    user = _user_from_mdb(req.username)
    if user is None:
        user = USUARIOS_FALLBACK.get(req.username.lower())
    if not user:
        raise HTTPException(status_code=401, detail="Usuario incorrecto")
    token = create_token({"sub": req.username, "rol": user["rol"]})
    return {
        "access_token": token,
        "token_type": "bearer",
        "username": user.get("username") or req.username,
        "nombre": user["nombre"],
        "responsable": user["nombre"],
        "cargo": user.get("cargo") or user["rol"],
        "rol": user["rol"],
    }

@app.get("/usuarios")
def usuarios():
    try:
        return _list_mdb_users()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

_EQUIPOS_SELECT = """
    SELECT
        e.ID,
        e.CODE_SYS,
        e.EQUIPO,
        e.LOCALIZACION,
        e.NAME_SYS_1,
        e.NAME_SYS_2,
        e.CODE_QR,
        e.PUNTOS,
        e.TAGNAME,

        s.ID AS SYS_ID,
        s.SISTEMA,
        s.CODE AS SYS_CODE,
        s.NAME_SYS,

        d.ID AS DATA_ID,
        d.FECHA,
        d.HORA,
        d.MARCA,
        d.MODELO,
        d.VOLTAJE,
        d.CORRIENTE,
        d.SERIAL,
        d.RPM,
        d.SF,
        d.HP,
        d.FRAME,
        d.BRGS_DRIVE,
        d.BRGS_OPP,
        d.CICLO,
        d.UBICACION,
        d.CODE_CONJUNTO,
        d.ARRANQUE,
        d.PH,
        d.TENSION,
        d.LUBRICACION
    FROM MOT_EQUIPO e
    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
    LEFT JOIN MOT_DATA d ON d.UBICACION = e.LOCALIZACION
"""

@app.get("/equipos")
def get_equipos():
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(_EQUIPOS_SELECT + " ORDER BY e.LOCALIZACION")
            rows = cur.fetchall()
            return [_equipo_defaults(r) for r in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en /equipos: {e}")
    finally:
        db.close()

@app.get("/equipos/{qr_code}")
def get_equipo_by_qr(qr_code: str):
    code = _normalize_qr(qr_code)
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(
                _EQUIPOS_SELECT + """
                WHERE UPPER(TRIM(COALESCE(e.CODE_QR, ''))) = %s
                   OR UPPER(TRIM(COALESCE(e.TAGNAME, ''))) = %s
                   OR CAST(e.LOCALIZACION AS CHAR) = %s
                   OR CAST(e.ID AS CHAR) = %s
                LIMIT 1
                """,
                (code, code, code, code),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail=f"Equipo no encontrado para QR: {code}")
            return _equipo_defaults(row)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en /equipos/{{qr_code}}: {e}")
    finally:
        db.close()

@app.get("/equipo-info/{localizacion}")
def get_equipo_info(localizacion: int):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT
                    UBICACION AS LOCALIZACION,
                    FECHA,
                    HORA,
                    MARCA,
                    MODELO,
                    VOLTAJE,
                    CORRIENTE,
                    SERIAL,
                    RPM,
                    SF,
                    HP,
                    FRAME,
                    BRGS_DRIVE,
                    BRGS_OPP,
                    CICLO,
                    CODE_CONJUNTO,
                    ARRANQUE,
                    PH,
                    TENSION,
                    LUBRICACION
                FROM MOT_DATA
                WHERE UBICACION = %s
                LIMIT 1
            """, (localizacion,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Sin datos técnicos")
            return row
    finally:
        db.close()

@app.get("/debug-qr/{qr_code}")
def debug_qr(qr_code: str):
    code = _normalize_qr(qr_code)
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT ID, EQUIPO, LOCALIZACION, CODE_QR, TAGNAME, PUNTOS
                FROM MOT_EQUIPO
                WHERE UPPER(TRIM(COALESCE(CODE_QR, ''))) = %s
                   OR UPPER(TRIM(COALESCE(TAGNAME, ''))) = %s
                   OR CAST(LOCALIZACION AS CHAR) = %s
                   OR CAST(ID AS CHAR) = %s
                LIMIT 10
            """, (code, code, code, code))
            return {
                "qr_recibido": qr_code,
                "qr_normalizado": code,
                "db": DB_NAME,
                "tabla": "MOT_EQUIPO",
                "resultado": cur.fetchall(),
            }
    finally:
        db.close()

@app.get("/debug-puntos")
def debug_puntos():
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT ID, EQUIPO, LOCALIZACION, PUNTOS, TAGNAME
                FROM MOT_EQUIPO
                ORDER BY LOCALIZACION
            """)
            return cur.fetchall()
    finally:
        db.close()

@app.get("/ultima-medicion/{localizacion}")
def get_ultima_medicion(localizacion: int):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT * FROM MOT_VIBR_MUES
                WHERE LOCALIZACION = %s
                ORDER BY ID DESC
                LIMIT 1
            """, (localizacion,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Sin mediciones previas")
            return row
    finally:
        db.close()

@app.get("/historial/{localizacion}")
def get_historial(localizacion: int, limit: int = 10, payload=Depends(verify_token)):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT ID, FECHA, HORA, H1,V1,A1, H2,V2,A2,
                       H3,V3,A3, H4,V4,A4, RMS, OBSERVACIONES
                FROM MOT_VIBR_MUES
                WHERE LOCALIZACION = %s
                ORDER BY ID DESC
                LIMIT %s
            """, (localizacion, limit))
            return cur.fetchall()
    finally:
        db.close()

@app.get("/ultimas-mediciones")
def get_ultimas_mediciones(limit: int = 50):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT ID, FECHA, HORA, SISTEMA, LOCALIZACION,
                       H1,V1,A1, H2,V2,A2, H3,V3,A3,
                       H4,V4,A4, H5,V5,A5, H6,V6,A6,
                       H7,V7,A7, H8,V8,A8, H9,V9,A9,
                       RMS, OBSERVACIONES
                FROM MOT_VIBR_MUES
                ORDER BY ID DESC
                LIMIT %s
            """, (limit,))
            return cur.fetchall()
    finally:
        db.close()

@app.post("/mediciones", status_code=201)
def insert_medicion(m: MedicionReq, payload=Depends(verify_token)):
    db = get_db()
    try:
        with db.cursor() as cur:
            try:
                cur.execute("SELECT ID FROM MOT_VIBR_MUES WHERE UUID = %s", (m.uuid,))
                if cur.fetchone():
                    return {"status": "already_exists", "uuid": m.uuid}
            except Exception:
                pass

            cur.execute("""
                INSERT INTO MOT_VIBR_MUES
                (FECHA,HORA,SISTEMA,LOCALIZACION,
                 H1,V1,A1,H2,V2,A2,H3,V3,A3,
                 H4,V4,A4,H5,V5,A5,H6,V6,A6,
                 H7,V7,A7,H8,V8,A8,H9,V9,A9,
                 RMS,OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL)
                VALUES(%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s)
            """, (
                m.fecha, m.hora, m.sistema, m.localizacion,
                m.H1, m.V1, m.A1, m.H2, m.V2, m.A2, m.H3, m.V3, m.A3,
                m.H4, m.V4, m.A4, m.H5, m.V5, m.A5, m.H6, m.V6, m.A6,
                m.H7, m.V7, m.A7, m.H8, m.V8, m.A8, m.H9, m.V9, m.A9,
                m.RMS, m.OBSERVACIONES, m.USUARIO or m.RESPONSABLE, m.CARGO,
                m.MARCA, m.MODELO, m.SERIAL,
            ))
            db.commit()
            return {"status": "ok", "uuid": m.uuid, "id": cur.lastrowid}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        db.close()

@app.post("/sincronizar")
def sincronizar(req: SyncReq, payload=Depends(verify_token)):
    resultados = []
    for m in req.mediciones:
        try:
            insert_medicion(m, payload)
            resultados.append({"uuid": m.uuid, "status": "ok"})
        except Exception as e:
            resultados.append({"uuid": m.uuid, "status": "error", "detalle": str(e)})
    ok = sum(1 for r in resultados if r["status"] == "ok")
    return {
        "total": len(resultados),
        "exitosas": ok,
        "fallidas": len(resultados) - ok,
        "detalle": resultados,
    }

@app.post("/reemplazos", status_code=201)
def registrar_reemplazo(
    request: ReplacementReq,
    payload=Depends(verify_token),
):
    now = datetime.now()
    fecha = now.strftime("%Y-%m-%d")
    hora = now.strftime("%H:%M:%S")
    db = get_db()
    try:
        with db.cursor() as cur:
            result = _execute_replacements(
                cur,
                request,
                fecha=fecha,
                hora=hora,
            )
        db.commit()
        return {
            "status": "ok",
            "fecha": fecha,
            "hora": hora,
            **result,
        }
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo guardar el reemplazo: {exc}",
        )
    finally:
        db.close()

@app.post("/temperaturas", status_code=201)
def insert_temperature(m: TemperatureReq, payload=Depends(verify_token)):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("""
                SELECT ID, SISTEMA, T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
                       OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT
                FROM MOT_TEMP_MUES
                WHERE LOCALIZACION = %s AND FECHA = %s AND HORA = %s
                ORDER BY ID DESC
            """, (m.localizacion, m.fecha, m.hora))
            wanted_signature = _temperature_sample_signature({
                "SISTEMA": m.sistema,
                "T1": m.T1,
                "T2": m.T2,
                "T3": m.T3,
                "T4": m.T4,
                "T5": m.T5,
                "T6": m.T6,
                "T7": m.T7,
                "T8": m.T8,
                "T9": m.T9,
                "T10": m.T10,
                "OBSERVACIONES": m.OBSERVACIONES,
                "USUARIO": m.USUARIO,
                "CARGO": m.CARGO,
                "MARCA": m.MARCA,
                "MODELO": m.MODELO,
                "SERIAL": m.SERIAL,
                "ODT": m.ODT,
            })
            existing = next(
                (
                    row
                    for row in cur.fetchall()
                    if _temperature_sample_signature(row) == wanted_signature
                ),
                None,
            )
            if existing:
                return {
                    "status": "skipped",
                    "reason": "already_exists",
                    "uuid": m.uuid,
                    "id": existing.get("ID"),
                }

            cur.execute("""
                INSERT INTO MOT_TEMP_MUES
                (FECHA,HORA,SISTEMA,LOCALIZACION,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
                 OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT)
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                       %s,%s,%s,%s,%s,%s,%s)
            """, (
                m.fecha, m.hora, m.sistema, m.localizacion,
                m.T1, m.T2, m.T3, m.T4, m.T5,
                m.T6, m.T7, m.T8, m.T9, m.T10,
                m.OBSERVACIONES, m.USUARIO, m.CARGO,
                m.MARCA, m.MODELO, m.SERIAL, m.ODT,
            ))
            db.commit()
            return {"status": "ok", "uuid": m.uuid, "id": cur.lastrowid}
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(exc))
    finally:
        db.close()

@app.get("/temperaturas")
def get_temperatures(
    localizacion: Optional[int] = None,
    limit: int = 50,
    payload=Depends(verify_token),
):
    db = get_db()
    try:
        with db.cursor() as cur:
            sql = _TEMPERATURE_SELECT
            params = []
            if localizacion is not None:
                sql += " WHERE LOCALIZACION = %s"
                params.append(localizacion)
            sql += f" ORDER BY {_TEMPERATURE_DATE_SQL} DESC, ID DESC LIMIT %s"
            params.append(max(0, limit))
            cur.execute(sql, tuple(params))
            return [_temperature_row(row) for row in cur.fetchall()]
    finally:
        db.close()

@app.get("/temperaturas/ultimas")
def get_latest_temperatures(
    limit: int = 50,
    payload=Depends(verify_token),
):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(f"""
                SELECT ID, FECHA, HORA, SISTEMA, LOCALIZACION,
                       T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
                       OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT
                FROM (
                    SELECT ID, FECHA, HORA, SISTEMA, LOCALIZACION,
                           T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
                           OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT,
                           ROW_NUMBER() OVER (
                               PARTITION BY LOCALIZACION
                               ORDER BY {_TEMPERATURE_DATE_SQL} DESC, ID DESC
                           ) AS rn
                    FROM MOT_TEMP_MUES
                ) AS ranked
                WHERE rn = 1
                ORDER BY {_TEMPERATURE_DATE_SQL} DESC, ID DESC
                LIMIT %s
            """, (max(0, limit),))
            return [_temperature_row(row) for row in cur.fetchall()]
    finally:
        db.close()

@app.get("/temperaturas/ultima/{localizacion}")
def get_latest_temperature(
    localizacion: int,
    payload=Depends(verify_token),
):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(
                _TEMPERATURE_SELECT
                + f" WHERE LOCALIZACION = %s ORDER BY {_TEMPERATURE_DATE_SQL} DESC, ID DESC LIMIT 1",
                (localizacion,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Sin temperaturas previas")
            return _temperature_row(row)
    finally:
        db.close()

@app.get("/sistemas")
def get_sistemas():
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute("SELECT * FROM MOT_SYSTEM ORDER BY CODE")
            return cur.fetchall()
    finally:
        db.close()

# ── Servir Flutter web (opcional, al final para no bloquear rutas) ─────
from fastapi.staticfiles import StaticFiles
try:
    app.mount("/", StaticFiles(directory="build/web", html=True), name="web")
    print("Flutter web cargado")
except Exception as e:
    print(f"Flutter web no disponible: {e}")

if __name__ == "__main__":
    import uvicorn
    print("=" * 65)
    print("  SCV-PTBG API - Sistema de Captura de Vibraciones")
    print("=" * 65)
    print(f"  DB:      {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print("  Equipos: MOT_EQUIPO")
    print("  Data:    MOT_DATA")
    print("  App:     http://0.0.0.0:8001")
    print("  Docs:    http://127.0.0.1:8001/docs")
    print("=" * 65)
    uvicorn.run(app, host="0.0.0.0", port=8001)
