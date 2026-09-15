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
from uuid import uuid4
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

class LubricationReq(BaseModel):
    uuid: str
    localizacion: int = Field(gt=0)
    sistema: str
    fecha: str
    hora: str
    L1: Optional[float] = None
    L2: Optional[float] = None
    L3: Optional[float] = None
    L4: Optional[float] = None
    L5: Optional[float] = None
    L6: Optional[float] = None
    L7: Optional[float] = None
    L8: Optional[float] = None
    L9: Optional[float] = None
    OBSERVACIONES: Optional[str] = None
    USUARIO: Optional[str] = None
    CARGO: Optional[str] = None
    MARCA: Optional[str] = None
    MODELO: Optional[str] = None
    SERIAL: Optional[str] = None
    ODT: Optional[int] = None

class SyncReq(BaseModel):
    mediciones: List[MedicionReq]

class ReplacementItem(BaseModel):
    equipo: int
    marca: str
    modelo: str
    serial: str
    # Que se dano en la pieza que sale. Va a MOT_LOG_RPL.MOTIVO.
    motivo: Optional[str] = None
    observaciones: Optional[str] = None
    # Con que estatus y en que sitio queda la pieza retirada. Lo elige el
    # tecnico en la tablet: solo el sabe si sirve, quedo averiada o se desecha.
    estado_saliente: Optional[str] = None
    sitio_saliente: Optional[str] = None
    # Identidad del movimiento, para no duplicar si se reintenta.
    uuid: Optional[str] = None

class ReplacementReq(BaseModel):
    localizacion: int
    code_conjunto: int
    componentes: List[ReplacementItem]
    # La app ya mandaba la ODT pero el modelo no la declaraba, asi que FastAPI
    # la descartaba en silencio y nunca llegaba a la base.
    odt: Optional[int] = None
    usuario: Optional[str] = None
    cargo: Optional[str] = None

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

def _tabla_tiene_localizacion(cur, table: str) -> bool:
    """LOCALIZACION (taller/almacen) puede no existir aun en la maestra."""
    cur.execute(
        """
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
              AND UPPER(COLUMN_NAME) = 'LOCALIZACION'
        """,
        (table,),
    )
    return cur.fetchone() is not None


def _instalar_pieza(
    cur,
    *,
    table: str,
    serial: str,
    marca: str,
    modelo: str,
    fecha: str,
    hora: str,
    localizacion: int,
    code_conjunto: int,
) -> None:
    """Deja la pieza como la instalada en esa posicion.

    El SERIAL es la identidad: una pieza que ya paso por la planta reactiva su
    fila en vez de crear otra. Si se insertara una fila nueva cada vez, el
    mismo motor apareceria repetido en el inventario y el serial dejaria de
    identificar una pieza. Si el serial no existe, la fila se crea: ese es el
    alta de piezas nuevas, que ocurre al escribirlas en el reemplazo.
    """
    cur.execute(
        f"""
            SELECT ID FROM `{table}`
            WHERE UPPER(TRIM(SERIAL)) = %s
            ORDER BY ACTIVO DESC, ID DESC
            LIMIT 1
            FOR UPDATE
        """,
        (serial.upper(),),
    )
    existente = cur.fetchone()
    if existente:
        cur.execute(
            f"""
                UPDATE `{table}`
                SET ACTIVO = 1, ESTADO = 'INSTALADO',
                    FECHA = %s, HORA = %s, MARCA = %s, MODELO = %s,
                    UBICACION = %s, CODE_CONJUNTO = %s
                WHERE ID = %s
            """,
            (fecha, hora, marca, modelo, localizacion, code_conjunto,
             existente["ID"]),
        )
        return

    cur.execute(
        f"""
            INSERT INTO `{table}`
                (FECHA, HORA, MARCA, MODELO, SERIAL,
                 UBICACION, CODE_CONJUNTO, ACTIVO, ESTADO)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 1, 'INSTALADO')
        """,
        (fecha, hora, marca, modelo, serial, localizacion, code_conjunto),
    )


def _execute_replacements(
    cur,
    request: ReplacementReq,
    *,
    fecha: str,
    hora: str,
    usuario: Optional[str] = None,
    cargo: Optional[str] = None,
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

        tiene_localizacion = _tabla_tiene_localizacion(cur, table)

        # ACTIVO = 1 es la pieza puesta ahora. La maestra guarda una fila por
        # pieza fisica, asi que una posicion acumula filas historicas.
        cur.execute(
            f"""
                SELECT ID, MARCA, MODELO, SERIAL, FECHA
                FROM `{table}`
                WHERE UBICACION = %s AND CODE_CONJUNTO = %s AND ACTIVO = 1
                LIMIT 1
                FOR UPDATE
            """,
            (request.localizacion, request.code_conjunto),
        )
        current = cur.fetchone()
        if not current:
            _instalar_pieza(
                cur,
                table=table,
                serial=serial,
                marca=marca,
                modelo=modelo,
                fecha=fecha,
                hora=hora,
                localizacion=request.localizacion,
                code_conjunto=request.code_conjunto,
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

        # MOT_LOG_RPL guarda la pieza que SALE, no la que entra. FECHA es
        # cuando salio y FECHA_INSTALACION cuando se habia puesto: con las dos
        # se saca el tiempo que estuvo en servicio.
        cur.execute(
            """
                INSERT INTO MOT_LOG_RPL
                    (FECHA, HORA, MARCA, MODELO, SERIAL,
                     EQUIPO, UBICACION, CODE_CONJUNTO,
                     ODT, USUARIO, CARGO, MOTIVO,
                     FECHA_INSTALACION, OBSERVACIONES, UUID)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s)
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
                request.odt,
                usuario,
                cargo,
                _clean(component.motivo),
                _clean(current.get("FECHA")),
                _clean(component.observaciones),
                _clean(component.uuid),
            ),
        )
        # La pieza que sale CONSERVA su fila: deja de estar activa pero sigue
        # existiendo en el inventario con el estatus que eligio el tecnico.
        # Antes esta fila se sobrescribia con la pieza nueva y la retirada
        # desaparecia de la planta.
        estado_saliente = (_clean(component.estado_saliente) or "").upper()
        if estado_saliente not in ESTADOS_MANUALES:
            estado_saliente = "DISPONIBLE"

        campos_salida = ["ACTIVO = 0", "ESTADO = %s", "FECHA = %s", "HORA = %s"]
        valores_salida = [estado_saliente, fecha, hora]
        if tiene_localizacion:
            campos_salida.append("LOCALIZACION = %s")
            valores_salida.append(_clean(component.sitio_saliente))
        valores_salida.append(current["ID"])
        cur.execute(
            f"UPDATE `{table}` SET {', '.join(campos_salida)} WHERE ID = %s",
            tuple(valores_salida),
        )

        _instalar_pieza(
            cur,
            table=table,
            serial=serial,
            marca=marca,
            modelo=modelo,
            fecha=fecha,
            hora=hora,
            localizacion=request.localizacion,
            code_conjunto=request.code_conjunto,
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
                SELECT ID, USUARIO, CARGO, COALESCE(ROL, '') AS ROL
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
            # El rol sale de MDB_USERS.ROL: antes iba fijo en "mecanico" y
            # un administrador entraba como uno mas.
            rol_planta = _clean(row.get("ROL"), "") or ""
            return {
                "id": row.get("ID"),
                "username": nombre,
                "nombre": nombre,
                "cargo": cargo,
                "rol": "admin" if "ADMIN" in rol_planta.upper() else "mecanico",
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
                SELECT ID, USUARIO, CARGO, COALESCE(ROL, '') AS ROL
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
                    "rol": _clean(row.get("ROL"), "") or "",
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

    # Familia de compatibilidad. Se manda tal cual, incluido el NULL: los 51
    # equipos originales no la tienen y se resuelven con la lista del codigo.
    try:
        familia = row.get("FAMILIA_COMPAT")
        row["FAMILIA_COMPAT"] = int(familia) if familia is not None else None
    except (TypeError, ValueError):
        row["FAMILIA_COMPAT"] = None

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
    for column in (
        "MOTORES_LUB", "CANT_MOT_LUB", "ELEC_MOT_LUB", "MAN_MOT_LUB",
        "ELEMENTO_LUB", "CANT_ELEM_LUB", "ELEC_ELEM_LUB", "MAN_ELEM_LUB",
    ):
        row[column] = row.get(column)
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
        -- Familia de compatibilidad: que piezas puede recibir el equipo. No se
        -- deduce del sistema ni del subsistema (VENT TURB y VENT GEN comparten
        -- los dos y son familias distintas), por eso viaja como columna propia.
        e.FAMILIA_COMPAT,

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
        d.LUBRICACION,
        d.MOTORES_LUB,
        d.CANT_MOT_LUB,
        d.ELEC_MOT_LUB,
        d.MAN_MOT_LUB,
        d.ELEMENTO_LUB,
        d.CANT_ELEM_LUB,
        d.ELEC_ELEM_LUB,
        d.MAN_ELEM_LUB
    FROM MOT_EQUIPO e
    LEFT JOIN MOT_SYSTEM s ON s.CODE = e.CODE_SYS
    -- ACTIVO = 1 es el motor puesto ahora. MOT_DATA guarda una fila por pieza
    -- fisica, asi que una posicion acumula filas historicas: sin este filtro
    -- el LEFT JOIN devolveria el equipo repetido una vez por pieza.
    -- Va dentro del ON y no del WHERE: en el WHERE convertiria el LEFT JOIN en
    -- INNER y desapareceria todo equipo que aun no tiene ficha tecnica.
    LEFT JOIN MOT_DATA d
           ON d.UBICACION = e.LOCALIZACION AND d.ACTIVO = 1
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
                    LUBRICACION,
                    MOTORES_LUB,
                    CANT_MOT_LUB,
                    ELEC_MOT_LUB,
                    MAN_MOT_LUB,
                    ELEMENTO_LUB,
                    CANT_ELEM_LUB,
                    ELEC_ELEM_LUB,
                    MAN_ELEM_LUB
                FROM MOT_DATA
                -- La placa que se pide es la del motor puesto ahora, no la de
                -- los que pasaron por esa posicion.
                WHERE UBICACION = %s AND ACTIVO = 1
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
            # El UUID es la identidad de la medicion. Si ya esta, la tablet
            # esta reintentando un envio cuya respuesta se perdio: no se
            # duplica. Antes este chequeo estaba dentro de un try/except que se
            # tragaba el error, y el INSERT ni siquiera guardaba la columna.
            cur.execute("SELECT ID FROM MOT_VIBR_MUES WHERE UUID = %s", (m.uuid,))
            existente = cur.fetchone()
            if existente:
                return {
                    "status": "already_exists",
                    "uuid": m.uuid,
                    "id": existente.get("ID"),
                }

            cur.execute("""
                INSERT INTO MOT_VIBR_MUES
                (UUID,FECHA,HORA,SISTEMA,LOCALIZACION,
                 H1,V1,A1,H2,V2,A2,H3,V3,A3,
                 H4,V4,A4,H5,V5,A5,H6,V6,A6,
                 H7,V7,A7,H8,V8,A8,H9,V9,A9,
                 RMS,OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL)
                VALUES(%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s,%s,%s,
                 %s,%s,%s,%s,%s,%s,%s)
            """, (
                m.uuid, m.fecha, m.hora, m.sistema, m.localizacion,
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
                # Si la app no manda responsable, se toma del token: siempre
                # queda registrado quien hizo el reemplazo.
                usuario=_clean(request.usuario) or _clean(payload.get("sub")),
                cargo=_clean(request.cargo) or _clean(payload.get("rol")),
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

@app.get("/componentes/{tipo}")
def listar_componentes(tipo: int, payload=Depends(verify_token)):
    """
    Inventario de piezas de un tipo (1 Motor, 2 Bomba, 3 Caja, 4 Ventilador).

    La tabla maestra (MOT_*_DATA) es la fuente de verdad: ahi vive toda unidad
    de la planta, este instalada, averiada en taller o disponible en almacen.
    MOT_LOG_RPL no se consulta para armar el inventario porque es una bitacora
    inmutable de permutas, no un registro de existencias; solo se usa para
    completar donde quedo la pieza cuando la maestra no lo dice.

    El SERIAL identifica la pieza fisica.
    """
    table_info = _REPLACEMENT_TABLES.get(tipo)
    if table_info is None:
        raise HTTPException(
            status_code=422,
            detail=f"Tipo de equipo invalido: {tipo}",
        )
    table, label = table_info

    db = get_db()
    try:
        with db.cursor() as cur:
            # LOCALIZACION (taller/almacen) hoy solo existe en MOT_LOG_RPL. Si
            # se agrega a la maestra, esta consulta la toma de ahi sin cambios.
            cur.execute(
                """
                    SELECT COLUMN_NAME
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = %s
                      AND UPPER(COLUMN_NAME) = 'LOCALIZACION'
                """,
                (table,),
            )
            maestra_tiene_localizacion = cur.fetchone() is not None

            columna_localizacion = (
                "d.LOCALIZACION AS LOCALIZACION"
                if maestra_tiene_localizacion
                else "NULL AS LOCALIZACION"
            )
            cur.execute(
                f"""
                    SELECT d.ID, d.MARCA, d.MODELO, d.SERIAL,
                           d.ESTADO, d.ACTIVO, d.UBICACION, d.CODE_CONJUNTO,
                           d.FECHA, {columna_localizacion},
                           e.EQUIPO AS EQUIPO_NOMBRE
                    FROM `{table}` d
                    LEFT JOIN MOT_EQUIPO e ON e.LOCALIZACION = d.UBICACION
                """
            )
            unidades = cur.fetchall() or []

            # Ultimo destino conocido por serial, para las piezas cuya maestra
            # no guarda localizacion.
            destinos = {}
            if not maestra_tiene_localizacion:
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
                    serial = _clean(fila.get("SERIAL"))
                    if serial:
                        destinos[serial.upper()] = _clean(fila.get("LOCALIZACION"))
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo leer el inventario de {label}: {exc}",
        )
    finally:
        db.close()

    piezas = []
    for row in unidades:
        serial = _clean(row.get("SERIAL"))
        if not serial:
            continue
        estado = (_clean(row.get("ESTADO")) or "").upper()
        try:
            ubicacion = int(row.get("UBICACION") or 0)
        except (TypeError, ValueError):
            ubicacion = 0
        activo = row.get("ACTIVO")

        # ACTIVO manda: es la fila vigente de esa posicion. Las retiradas
        # conservan su UBICACION, asi que deducirlo de ahi marcaria como
        # instalada toda pieza que alguna vez estuvo puesta.
        if activo is not None:
            instalado = int(activo or 0) == 1
        else:
            # Filas anteriores al uso de ACTIVO.
            instalado = estado == "INSTALADO" if estado else ubicacion > 0
        piezas.append({
            "id": row.get("ID"),
            "marca": _clean(row.get("MARCA"), "") or "",
            "modelo": _clean(row.get("MODELO"), "") or "",
            "serial": serial,
            "estado": estado or ("INSTALADO" if instalado else "DISPONIBLE"),
            "estado_declarado": bool(estado),
            "activo": row.get("ACTIVO"),
            "instalado": instalado,
            "ubicacion": ubicacion or None,
            "equipo": _clean(row.get("EQUIPO_NOMBRE"), "") or "",
            "code_conjunto": row.get("CODE_CONJUNTO"),
            "fecha": str(row.get("FECHA") or ""),
            "localizacion": _clean(row.get("LOCALIZACION"))
            or destinos.get(serial.upper()),
        })

    # Primero lo disponible, que es lo que el tecnico busca para reemplazar.
    orden_estado = {"DISPONIBLE": 0, "AVERIADO": 1, "AVERIA": 1, "INSTALADO": 2}
    piezas.sort(
        key=lambda item: (
            orden_estado.get(item["estado"], 3),
            item["marca"].upper(),
            item["modelo"].upper(),
            item["serial"].upper(),
        )
    )
    return {
        "tipo": tipo,
        "componente": label,
        "total": len(piezas),
        "disponibles": sum(1 for p in piezas if not p["instalado"]),
        "piezas": piezas,
    }

# Estados que el tecnico puede poner desde la tablet.
#
# INSTALADO no esta a proposito: que una pieza este puesta en un equipo lo
# decide el reemplazo, no un cambio manual de estatus. Permitirlo dejaria la
# maestra diciendo que esta instalada sin que exista el equipo ni la ODT que
# lo respalde.
ESTADOS_MANUALES = {"DISPONIBLE", "AVERIADO", "DESECHADO"}


class EstadoComponenteReq(BaseModel):
    serial: str
    estado: str
    localizacion: Optional[str] = None
    observaciones: Optional[str] = None
    usuario: Optional[str] = None
    cargo: Optional[str] = None
    uuid: Optional[str] = None


@app.post("/componentes/{tipo}/estado")
def actualizar_estado_componente(
    tipo: int,
    req: EstadoComponenteReq,
    payload=Depends(verify_token),
):
    """
    Cambia la condicion de una pieza en su tabla maestra.

    No toca MOT_LOG_RPL: esa es la bitacora inmutable de permutas y un cambio
    de estatus no es una permuta. Tampoco permite marcar INSTALADO ni mover la
    UBICACION: eso solo lo hace un reemplazo.
    """
    table_info = _REPLACEMENT_TABLES.get(tipo)
    if table_info is None:
        raise HTTPException(status_code=422, detail=f"Tipo de equipo invalido: {tipo}")
    table, label = table_info

    serial = _clean(req.serial)
    if not serial:
        raise HTTPException(status_code=422, detail="El serial es obligatorio")

    estado = (_clean(req.estado) or "").upper()
    if estado not in ESTADOS_MANUALES:
        raise HTTPException(
            status_code=422,
            detail=(
                "Estado invalido. Permitidos: "
                + ", ".join(sorted(ESTADOS_MANUALES))
                + ". INSTALADO solo lo asigna un reemplazo."
            ),
        )

    db = get_db()
    try:
        with db.cursor() as cur:
            # Si por lo que sea hubiera mas de una fila con el mismo serial,
            # manda la vigente: nunca se cambia el estatus de una historica.
            cur.execute(
                f"""
                    SELECT ID, ESTADO, UBICACION, ACTIVO
                    FROM `{table}`
                    WHERE UPPER(TRIM(SERIAL)) = %s
                    ORDER BY ACTIVO DESC, ID DESC
                    LIMIT 1
                    FOR UPDATE
                """,
                (serial.upper(),),
            )
            pieza = cur.fetchone()
            if not pieza:
                raise HTTPException(
                    status_code=404,
                    detail=f"No existe un {label} con serial {serial}",
                )

            estado_actual = (_clean(pieza.get("ESTADO")) or "").upper()
            try:
                ubicacion = int(pieza.get("UBICACION") or 0)
            except (TypeError, ValueError):
                ubicacion = 0
            activo = pieza.get("ACTIVO")
            # ACTIVO manda; solo se deduce en filas anteriores a su uso.
            if activo is not None:
                instalada = int(activo or 0) == 1
            else:
                instalada = (
                    estado_actual == "INSTALADO" if estado_actual else ubicacion > 0
                )
            if instalada:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"El {label} {serial} esta instalado. Registre el "
                        "reemplazo para retirarlo antes de cambiarle el estatus."
                    ),
                )

            cur.execute(
                """
                    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
                      AND UPPER(COLUMN_NAME) = 'LOCALIZACION'
                """,
                (table,),
            )
            tiene_localizacion = cur.fetchone() is not None

            ahora = datetime.now()
            campos = ["ESTADO = %s", "FECHA = %s", "HORA = %s"]
            valores = [
                estado,
                ahora.strftime("%Y-%m-%d"),
                ahora.strftime("%H:%M:%S"),
            ]
            if tiene_localizacion:
                campos.append("LOCALIZACION = %s")
                valores.append(_clean(req.localizacion))
            valores.append(pieza["ID"])

            cur.execute(
                f"UPDATE `{table}` SET {', '.join(campos)} WHERE ID = %s",
                tuple(valores),
            )
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo actualizar el estatus: {exc}",
        )
    finally:
        db.close()

    return {
        "status": "ok",
        "tipo": tipo,
        "componente": label,
        "serial": serial,
        "estado": estado,
        "localizacion": _clean(req.localizacion),
        "localizacion_guardada": tiene_localizacion,
        "usuario": _clean(req.usuario) or _clean(payload.get("sub")),
    }

# ── Ordenes de reparacion de componentes ──────────────────────────────
#
# Una orden saca UNA pieza de la planta para repararla. Mientras esta abierta
# la pieza queda EN REPARACION en su maestra; al cerrar, el RESULTADO decide
# con que estatus vuelve al inventario.
#
# No se escribe en MOT_LOG_RPL: esa es la bitacora de permutas y mandar una
# pieza al taller no es una permuta.

# Estatus que lleva la pieza mientras su orden esta abierta. No esta en
# ESTADOS_MANUALES a proposito: no lo puede fijar el tecnico a dedo, solo lo
# produce abrir una orden, y solo cerrarla lo saca.
ESTADO_EN_REPARACION = "EN REPARACION"

# Con que estatus vuelve la pieza al inventario segun como salio del taller.
RESULTADOS_REPARACION = {
    "REPARADO": "DISPONIBLE",
    "NO REPARABLE": "DESECHADO",
    "SIN INTERVENCION": "AVERIADO",
}

# A donde se puede mandar una pieza. Lista cerrada para que el inventario no
# termine con veinte formas de escribir el mismo taller.
DESTINOS_REPARACION = {
    "TALLER ELECTRICO",
    "TALLER MECANICO",
    "TALLER EXTERNO",
    "ALMACEN PRINCIPAL",
    "ALMACEN DE MOTORES",
}


class OrdenReparacionReq(BaseModel):
    equipo: int
    serial: str
    destino: str
    # Identidad de la orden. Si la tablet no la manda, se genera aqui; sin ella
    # un reintento crearia una segunda orden para la misma salida.
    uuid: Optional[str] = None
    marca: Optional[str] = None
    modelo: Optional[str] = None
    ubicacion_origen: Optional[int] = None
    motivo: Optional[str] = None
    fecha_salida: Optional[str] = None
    hora_salida: Optional[str] = None
    usuario_salida: Optional[str] = None
    cargo_salida: Optional[str] = None
    odt: Optional[int] = None
    observaciones: Optional[str] = None


class CierreOrdenReparacionReq(BaseModel):
    resultado: str
    fecha_retorno: Optional[str] = None
    hora_retorno: Optional[str] = None
    usuario_cierre: Optional[str] = None
    cargo_cierre: Optional[str] = None
    trabajo_realizado: Optional[str] = None
    ubicacion_final: Optional[str] = None
    observaciones: Optional[str] = None


def _pieza_vigente(cur, table: str, serial: str) -> Optional[dict]:
    """Devuelve la fila viva de esa pieza en su maestra.

    La identidad de la pieza es el SERIAL. Si por algun arrastre historico
    hubiera mas de una fila con el mismo serial, manda la activa: juzgar el
    caso con una fila vieja diria que la pieza esta libre cuando en realidad
    sigue montada en un equipo.
    """
    cur.execute(
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
    return cur.fetchone()


def _pieza_instalada(pieza: dict) -> bool:
    activo = pieza.get("ACTIVO")
    if activo is not None:
        return int(activo or 0) == 1
    # Filas anteriores al uso de ACTIVO: se deduce igual que en el inventario.
    estado = (_clean(pieza.get("ESTADO")) or "").upper()
    try:
        ubicacion = int(pieza.get("UBICACION") or 0)
    except (TypeError, ValueError):
        ubicacion = 0
    return estado == "INSTALADO" if estado else ubicacion > 0


def _aplicar_estatus_orden(
    cur,
    *,
    table: str,
    pieza_id: int,
    estado: str,
    localizacion: Optional[str],
    fecha: str,
    hora: str,
) -> bool:
    """Escribe en la maestra el estatus que impone la orden.

    Nunca toca ACTIVO ni UBICACION: que una pieza este montada en un equipo lo
    decide solo el reemplazo. Una orden manda la pieza al taller, no la
    desinstala.
    """
    campos = ["ESTADO = %s", "FECHA = %s", "HORA = %s"]
    valores: list[Any] = [estado, fecha, hora]
    # LOCALIZACION (taller/almacen) no existe en todas las maestras
    # desplegadas; sin comprobarlo el UPDATE tumbaria la transaccion.
    guardo_localizacion = False
    if localizacion is not None and _tabla_tiene_localizacion(cur, table):
        campos.append("LOCALIZACION = %s")
        valores.append(localizacion)
        guardo_localizacion = True
    valores.append(pieza_id)
    cur.execute(
        f"UPDATE `{table}` SET {', '.join(campos)} WHERE ID = %s",
        tuple(valores),
    )
    return guardo_localizacion


def _orden_por_uuid(cur, orden_uuid: str) -> Optional[dict]:
    cur.execute(
        """
            SELECT * FROM MOT_ORD_REP
            WHERE UUID = %s
            LIMIT 1
            FOR UPDATE
        """,
        (orden_uuid,),
    )
    return cur.fetchone()


def _orden_publica(row: dict) -> dict:
    """Pasa una fila de MOT_ORD_REP al formato que consume la tablet."""
    try:
        equipo = int(_clean(row.get("EQUIPO")) or 0)
    except (TypeError, ValueError):
        equipo = 0
    tabla_info = _REPLACEMENT_TABLES.get(equipo)
    return {
        "id": row.get("ID"),
        "uuid": _clean(row.get("UUID")),
        "equipo": equipo,
        "componente": tabla_info[1] if tabla_info else "",
        "serial": _clean(row.get("SERIAL"), "") or "",
        "marca": _clean(row.get("MARCA"), "") or "",
        "modelo": _clean(row.get("MODELO"), "") or "",
        "ubicacion_origen": row.get("UBICACION_ORIGEN"),
        "destino": _clean(row.get("DESTINO"), "") or "",
        "motivo": _clean(row.get("MOTIVO"), "") or "",
        "fecha_salida": _clean(row.get("FECHA_SALIDA"), "") or "",
        "hora_salida": _clean(row.get("HORA_SALIDA"), "") or "",
        "usuario_salida": _clean(row.get("USUARIO_SALIDA"), "") or "",
        "cargo_salida": _clean(row.get("CARGO_SALIDA"), "") or "",
        "odt": row.get("ODT"),
        "estado_orden": (_clean(row.get("ESTADO_ORDEN")) or "ABIERTA").upper(),
        "fecha_retorno": _clean(row.get("FECHA_RETORNO"), "") or "",
        "hora_retorno": _clean(row.get("HORA_RETORNO"), "") or "",
        "usuario_cierre": _clean(row.get("USUARIO_CIERRE"), "") or "",
        "cargo_cierre": _clean(row.get("CARGO_CIERRE"), "") or "",
        "trabajo_realizado": _clean(row.get("TRABAJO"), "") or "",
        "resultado": _clean(row.get("RESULTADO"), "") or "",
        "ubicacion_final": _clean(row.get("UBICACION_FINAL"), "") or "",
        "observaciones": _clean(row.get("OBSERVACIONES"), "") or "",
    }


@app.post("/ordenes-reparacion", status_code=201)
def crear_orden_reparacion(
    req: OrdenReparacionReq,
    payload=Depends(verify_token),
):
    """Abre una orden y deja la pieza EN REPARACION en su maestra."""
    table_info = _REPLACEMENT_TABLES.get(req.equipo)
    if table_info is None:
        raise HTTPException(
            status_code=422, detail=f"Tipo de equipo invalido: {req.equipo}"
        )
    table, label = table_info

    serial = _clean(req.serial)
    if not serial:
        raise HTTPException(status_code=422, detail="El serial es obligatorio")

    destino = (_clean(req.destino) or "").upper()
    if destino not in DESTINOS_REPARACION:
        raise HTTPException(
            status_code=422,
            detail=(
                "Destino invalido. Permitidos: "
                + ", ".join(sorted(DESTINOS_REPARACION))
            ),
        )

    orden_uuid = _clean(req.uuid) or str(uuid4())
    ahora = datetime.now()
    fecha = _clean(req.fecha_salida) or ahora.strftime("%Y-%m-%d")
    hora = _clean(req.hora_salida) or ahora.strftime("%H:%M:%S")
    usuario = _clean(req.usuario_salida) or _clean(payload.get("sub"))
    cargo = _clean(req.cargo_salida) or _clean(payload.get("rol"))

    db = get_db()
    try:
        with db.cursor() as cur:
            # Dedup por UUID: la tablet reintenta sin señal y no puede acabar
            # con dos ordenes para la misma salida de la misma pieza.
            existente = _orden_por_uuid(cur, orden_uuid)
            if existente:
                db.commit()
                return {
                    "status": "duplicada",
                    "uuid": orden_uuid,
                    "orden": _orden_publica(existente),
                }

            pieza = _pieza_vigente(cur, table, serial)
            if not pieza:
                raise HTTPException(
                    status_code=404,
                    detail=f"No existe un {label} con serial {serial}",
                )
            if _pieza_instalada(pieza):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"El {label} {serial} esta instalado en la ubicacion "
                        f"{pieza.get('UBICACION')}. Registre el reemplazo que "
                        "lo retira antes de mandarlo a reparacion."
                    ),
                )

            # Una pieza no puede estar en dos talleres a la vez: si ya tiene
            # una orden abierta, cerrar la nueva dejaria el estatus mintiendo.
            cur.execute(
                """
                    SELECT UUID FROM MOT_ORD_REP
                    WHERE TRIM(EQUIPO) = %s
                      AND UPPER(TRIM(SERIAL)) = %s
                      AND UPPER(TRIM(COALESCE(ESTADO_ORDEN, 'ABIERTA'))) = 'ABIERTA'
                    LIMIT 1
                """,
                (str(req.equipo), serial.upper()),
            )
            abierta = cur.fetchone()
            if abierta:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"El {label} {serial} ya tiene la orden "
                        f"{_clean(abierta.get('UUID'))} abierta. Cierrela antes "
                        "de abrir otra."
                    ),
                )

            cur.execute(
                """
                    INSERT INTO MOT_ORD_REP
                        (UUID, EQUIPO, SERIAL, MARCA, MODELO,
                         UBICACION_ORIGEN, DESTINO, MOTIVO,
                         FECHA_SALIDA, HORA_SALIDA, USUARIO_SALIDA,
                         CARGO_SALIDA, ODT, ESTADO_ORDEN, OBSERVACIONES)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s,
                            %s, %s, %s, %s, %s, 'ABIERTA', %s)
                """,
                (
                    orden_uuid,
                    str(req.equipo),
                    serial,
                    _clean(req.marca),
                    _clean(req.modelo),
                    req.ubicacion_origen,
                    destino,
                    _clean(req.motivo),
                    fecha,
                    hora,
                    usuario,
                    cargo,
                    req.odt,
                    _clean(req.observaciones),
                ),
            )

            # El DESTINO es donde esta fisicamente la pieza mientras dura la
            # orden, asi que se refleja en LOCALIZACION; el inventario debe
            # poder decir en que taller esta sin abrir la orden.
            _aplicar_estatus_orden(
                cur,
                table=table,
                pieza_id=pieza["ID"],
                estado=ESTADO_EN_REPARACION,
                localizacion=destino,
                fecha=fecha,
                hora=hora,
            )
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo abrir la orden de reparacion: {exc}",
        )
    finally:
        db.close()

    return {
        "status": "ok",
        "uuid": orden_uuid,
        "equipo": req.equipo,
        "componente": label,
        "serial": serial,
        "destino": destino,
        "estado_orden": "ABIERTA",
        "estado_pieza": ESTADO_EN_REPARACION,
        "fecha_salida": fecha,
        "hora_salida": hora,
        "usuario_salida": usuario,
        "cargo_salida": cargo,
    }


@app.post("/ordenes-reparacion/{uuid}/cerrar")
def cerrar_orden_reparacion(
    uuid: str,
    req: CierreOrdenReparacionReq,
    payload=Depends(verify_token),
):
    """Cierra la orden y devuelve la pieza al inventario segun el RESULTADO."""
    resultado = (_clean(req.resultado) or "").upper()
    if resultado not in RESULTADOS_REPARACION:
        raise HTTPException(
            status_code=422,
            detail=(
                "Resultado invalido. Permitidos: "
                + ", ".join(sorted(RESULTADOS_REPARACION))
            ),
        )
    estado_final = RESULTADOS_REPARACION[resultado]

    ahora = datetime.now()
    fecha = _clean(req.fecha_retorno) or ahora.strftime("%Y-%m-%d")
    hora = _clean(req.hora_retorno) or ahora.strftime("%H:%M:%S")
    usuario = _clean(req.usuario_cierre) or _clean(payload.get("sub"))
    cargo = _clean(req.cargo_cierre) or _clean(payload.get("rol"))
    ubicacion_final = _clean(req.ubicacion_final)

    db = get_db()
    try:
        with db.cursor() as cur:
            orden = _orden_por_uuid(cur, uuid)
            if not orden:
                raise HTTPException(
                    status_code=404,
                    detail=f"No existe la orden de reparacion {uuid}",
                )
            if (_clean(orden.get("ESTADO_ORDEN")) or "ABIERTA").upper() == "CERRADA":
                # Reintento de la tablet sobre una orden ya cerrada: se responde
                # lo que hay. Volver a cerrarla pisaria el resultado real con
                # uno que quizas ya cambio el estatus de la pieza.
                db.commit()
                return {
                    "status": "ya_cerrada",
                    "uuid": uuid,
                    "orden": _orden_publica(orden),
                }

            try:
                equipo = int(_clean(orden.get("EQUIPO")) or 0)
            except (TypeError, ValueError):
                equipo = 0
            table_info = _REPLACEMENT_TABLES.get(equipo)
            if table_info is None:
                raise HTTPException(
                    status_code=422,
                    detail=f"La orden {uuid} tiene un tipo de equipo invalido: {equipo}",
                )
            table, label = table_info
            serial = _clean(orden.get("SERIAL")) or ""

            cur.execute(
                """
                    UPDATE MOT_ORD_REP
                    SET ESTADO_ORDEN = 'CERRADA',
                        FECHA_RETORNO = %s, HORA_RETORNO = %s,
                        USUARIO_CIERRE = %s, CARGO_CIERRE = %s,
                        TRABAJO = %s, RESULTADO = %s,
                        UBICACION_FINAL = %s,
                        OBSERVACIONES = COALESCE(%s, OBSERVACIONES)
                    WHERE UUID = %s
                """,
                (
                    fecha,
                    hora,
                    usuario,
                    cargo,
                    _clean(req.trabajo_realizado),
                    resultado,
                    ubicacion_final,
                    _clean(req.observaciones),
                    uuid,
                ),
            )

            pieza = _pieza_vigente(cur, table, serial) if serial else None
            estado_aplicado = False
            if pieza and not _pieza_instalada(pieza):
                _aplicar_estatus_orden(
                    cur,
                    table=table,
                    pieza_id=pieza["ID"],
                    estado=estado_final,
                    localizacion=ubicacion_final,
                    fecha=fecha,
                    hora=hora,
                )
                estado_aplicado = True
            # Si la pieza volvio a instalarse por un reemplazo mientras la orden
            # seguia abierta, la orden se cierra igual pero no se le toca el
            # estatus: manda el reemplazo, y una orden que no se puede cerrar
            # nunca dejaria la pieza colgada en EN REPARACION para siempre.
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo cerrar la orden de reparacion: {exc}",
        )
    finally:
        db.close()

    return {
        "status": "ok",
        "uuid": uuid,
        "equipo": equipo,
        "componente": label,
        "serial": serial,
        "estado_orden": "CERRADA",
        "resultado": resultado,
        "estado_pieza": estado_final if estado_aplicado else None,
        "estado_pieza_aplicado": estado_aplicado,
        "ubicacion_final": ubicacion_final,
        "fecha_retorno": fecha,
        "hora_retorno": hora,
        "usuario_cierre": usuario,
        "cargo_cierre": cargo,
    }


@app.get("/ordenes-reparacion")
def listar_ordenes_reparacion(
    abiertas: Optional[bool] = None,
    equipo: Optional[int] = None,
    serial: Optional[str] = None,
    limit: int = 200,
    payload=Depends(verify_token),
):
    """Lista ordenes para que la tablet refresque su cache local."""
    condiciones = []
    valores: list[Any] = []
    if abiertas is True:
        condiciones.append(
            "UPPER(TRIM(COALESCE(ESTADO_ORDEN, 'ABIERTA'))) = 'ABIERTA'"
        )
    elif abiertas is False:
        condiciones.append(
            "UPPER(TRIM(COALESCE(ESTADO_ORDEN, 'ABIERTA'))) = 'CERRADA'"
        )
    if equipo is not None:
        condiciones.append("TRIM(EQUIPO) = %s")
        valores.append(str(equipo))
    serial_filtro = _clean(serial)
    if serial_filtro:
        condiciones.append("UPPER(TRIM(SERIAL)) = %s")
        valores.append(serial_filtro.upper())

    where = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""
    # Tope defensivo: la tablet no necesita el historico completo y una lista
    # sin limite puede tardar mas de lo que aguanta la sincronizacion por USB.
    limit = max(1, min(int(limit or 200), 1000))

    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(
                f"""
                    SELECT * FROM MOT_ORD_REP
                    {where}
                    ORDER BY ID DESC
                    LIMIT {limit}
                """,
                tuple(valores),
            )
            filas = cur.fetchall() or []
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudieron leer las ordenes de reparacion: {exc}",
        )
    finally:
        db.close()

    ordenes = [_orden_publica(fila) for fila in filas]
    return {
        "total": len(ordenes),
        "abiertas": sum(1 for o in ordenes if o["estado_orden"] == "ABIERTA"),
        "ordenes": ordenes,
    }

@app.post("/temperaturas", status_code=201)
def insert_temperature(m: TemperatureReq, payload=Depends(verify_token)):
    db = get_db()
    try:
        with db.cursor() as cur:
            # El UUID identifica el registro sin ambiguedad. Si ya esta, es un
            # reintento de la tablet, no una medicion nueva.
            cur.execute(
                "SELECT ID FROM MOT_TEMP_MUES WHERE UUID = %s LIMIT 1",
                (m.uuid,),
            )
            repetida = cur.fetchone()
            if repetida:
                return {
                    "status": "skipped",
                    "reason": "already_exists",
                    "uuid": m.uuid,
                    "id": repetida.get("ID"),
                }

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
                (UUID,FECHA,HORA,SISTEMA,LOCALIZACION,
                 T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,
                 OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT)
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                       %s,%s,%s,%s,%s,%s,%s)
            """, (
                m.uuid, m.fecha, m.hora, m.sistema, m.localizacion,
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

@app.post("/lubricaciones", status_code=201)
def insert_lubrication(m: LubricationReq, payload=Depends(verify_token)):
    db = get_db()
    try:
        with db.cursor() as cur:
            # Primero por UUID: es la identidad exacta del registro. El chequeo
            # por localizacion+fecha+hora se conserva como red para lo que se
            # subio antes de que existiera la columna.
            cur.execute(
                "SELECT ID FROM MOT_LUB_REG WHERE UUID = %s LIMIT 1", (m.uuid,)
            )
            existing = cur.fetchone()
            if not existing:
                cur.execute("""
                    SELECT ID FROM MOT_LUB_REG
                    WHERE LOCALIZACION = %s AND FECHA = %s AND HORA = %s
                    LIMIT 1
                """, (m.localizacion, m.fecha, m.hora))
                existing = cur.fetchone()
            if existing:
                return {
                    "status": "skipped",
                    "reason": "already_exists",
                    "uuid": m.uuid,
                    "id": existing.get("ID"),
                }
            cur.execute("""
                INSERT INTO MOT_LUB_REG
                (UUID,FECHA,HORA,SISTEMA,LOCALIZACION,
                 L1,L2,L3,L4,L5,L6,L7,L8,L9,
                 OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT)
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                       %s,%s,%s,%s,%s,%s,%s)
            """, (
                m.uuid, m.fecha, m.hora, m.sistema, m.localizacion,
                m.L1, m.L2, m.L3, m.L4, m.L5, m.L6, m.L7, m.L8, m.L9,
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

@app.get("/lubricaciones")
def get_lubrications(
    localizacion: Optional[int] = None,
    limit: int = 50,
    payload=Depends(verify_token),
):
    db = get_db()
    try:
        with db.cursor() as cur:
            sql = """
                SELECT ID,FECHA,HORA,SISTEMA,LOCALIZACION,
                       L1,L2,L3,L4,L5,L6,L7,L8,L9,
                       OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT
                FROM MOT_LUB_REG
            """
            params = []
            if localizacion is not None:
                sql += " WHERE LOCALIZACION = %s"
                params.append(localizacion)
            sql += " ORDER BY FECHA DESC, HORA DESC, ID DESC LIMIT %s"
            params.append(max(0, limit))
            cur.execute(sql, tuple(params))
            return cur.fetchall()
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
