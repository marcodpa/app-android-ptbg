"""Filtros por USB. Sin DDL remoto ni credenciales propias.

La numeración se comparte entre MOT_INDICE y FLT_CHANGE. Todos los uploaders
activos deben usar el mismo bloqueo; una versión antigua no participa en él.
"""
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta
import json
import sqlite3
from uuid import UUID

SYSTEM = 'PTBG_DAT.MDB_SYSTEM'
SUBSYSTEM = 'PTBG_DAT.MDB_SUBSYSTEM'
ELEMENTS = 'PTBG_FLT.FLT_ELEMENTS'
CHANGES = 'PTBG_FLT.FLT_CHANGE'
CATALOGS = (
    ('FILTROS_SYSTEM', SYSTEM, ('ID', 'SISTEMA', 'CODE_SYS', 'PTBG_FLT')),
    ('FILTROS_SUBSYSTEM', SUBSYSTEM, ('ID', 'CODE_SYS', 'NAME_SUB_SYS', 'CODE_SUB_SYS', 'PTBG_FLT')),
    ('FILTROS_ELEMENTS', ELEMENTS, ('ID', 'TAGNAME', 'CODE_SYS', 'CODE_SUB_SYS', 'ELEMENTO',
                                 'CANTIDAD', 'LOCALIZACION', 'MODELO', 'MARCA', 'ESPECIFICACIONES')),
)
CHANGE_MAP = {
    'UUID': 'uuid', 'ODT': 'odt', 'FECHA': 'fecha', 'HORA': 'hora', 'SISTEMA': 'sistema',
    'CODE_SYS': 'code_sys', 'CODE_SUB_SYS': 'code_sub_sys', 'LOCALIZACION': 'localizacion',
    'TAGNAME': 'tagname', 'ELEMENTO': 'elemento', 'MODELO': 'modelo', 'MARCA': 'marca',
    'ESPECIFICACIONES': 'especificaciones', 'OBSERVACIONES': 'observaciones',
    'USUARIO': 'responsable', 'CARGO': 'cargo', 'TABLET_ORIGEN': 'tablet_origen',
}


@contextmanager
def local(path):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    try:
        with conn:
            yield conn
    finally:
        conn.close()


def ensure_schema(conn):
    # Keep aligned with FilterStore.ensureSchema. Never touch remote schema.
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_META (
        clave TEXT PRIMARY KEY, valor TEXT NOT NULL)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_SYSTEM (
        ID INTEGER PRIMARY KEY, SISTEMA TEXT NOT NULL, CODE_SYS INTEGER NOT NULL UNIQUE,
        PTBG_FLT INTEGER NOT NULL DEFAULT 0)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_SUBSYSTEM (
        ID INTEGER PRIMARY KEY, CODE_SYS INTEGER NOT NULL, NAME_SUB_SYS TEXT NOT NULL,
        CODE_SUB_SYS INTEGER NOT NULL, PTBG_FLT INTEGER NOT NULL DEFAULT 0,
        UNIQUE(CODE_SYS,CODE_SUB_SYS))''')
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_ELEMENTS (
        ID INTEGER PRIMARY KEY, TAGNAME TEXT, CODE_SYS INTEGER NOT NULL,
        CODE_SUB_SYS INTEGER NOT NULL, ELEMENTO TEXT NOT NULL, CANTIDAD INTEGER NOT NULL,
        LOCALIZACION INTEGER NOT NULL UNIQUE, MODELO TEXT, MARCA TEXT, ESPECIFICACIONES TEXT)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_CAMBIOS_LOCAL (
        uuid TEXT PRIMARY KEY, odt INTEGER NOT NULL, fecha TEXT NOT NULL, hora TEXT NOT NULL,
        sistema TEXT NOT NULL, code_sys INTEGER NOT NULL, code_sub_sys INTEGER NOT NULL,
        localizacion INTEGER NOT NULL, tagname TEXT NOT NULL, elemento TEXT NOT NULL,
        cantidad INTEGER, modelo TEXT NOT NULL, marca TEXT NOT NULL, especificaciones TEXT NOT NULL,
        observaciones TEXT NOT NULL, responsable TEXT NOT NULL, cargo TEXT NOT NULL,
        tablet_origen TEXT NOT NULL, sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''')
    conn.execute('CREATE INDEX IF NOT EXISTS IDX_FILTROS_PENDING ON FILTROS_CAMBIOS_LOCAL(sincronizado)')
    conn.execute('''CREATE TABLE IF NOT EXISTS FILTROS_CATALOGO_PENDING (
        uuid TEXT PRIMARY KEY, accion TEXT NOT NULL, payload TEXT NOT NULL,
        responsable TEXT NOT NULL, tablet_origen TEXT NOT NULL,
        sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''')


def pending(path, table='FILTROS_CAMBIOS_LOCAL'):
    if table not in ('FILTROS_CAMBIOS_LOCAL', 'FILTROS_CATALOGO_PENDING'):
        raise ValueError('Tabla no permitida')
    with local(path) as conn:
        ensure_schema(conn)
        return [dict(r) for r in conn.execute(f'SELECT * FROM {table} WHERE sincronizado=0 ORDER BY created_at')]


@contextmanager
def odt_lock(cursor):
    acquire_odt_lock(cursor)
    try:
        yield
    finally:
        cursor.execute("SELECT RELEASE_LOCK('STER_ODT_GENERAL') AS released")


def acquire_odt_lock(cursor):
    # Closing the owning connection also releases this lock.
    cursor.execute("SELECT GET_LOCK('STER_ODT_GENERAL', 10) AS acquired")
    if int((cursor.fetchone() or {}).get('acquired') or 0) != 1:
        raise RuntimeError('Otra sincronización está asignando ODT. Reintente.')


def filter_odt_max(cursor, odt=None):
    """Missing new schema is compatible with old motor-only installations.

    Permission/network errors are NOT treated as an empty table.
    """
    try:
        sql = f'SELECT COALESCE(MAX(ODT),0) AS max_odt FROM {CHANGES}'
        cursor.execute(sql + (' WHERE ODT=%s' if odt is not None else ''), (odt,) if odt is not None else ())
        return int((cursor.fetchone() or {}).get('max_odt') or 0)
    except Exception as exc:
        if getattr(exc, 'args', ()) and exc.args[0] in (1049, 1146):
            return 0
        raise


def normalize(value):
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    if isinstance(value, timedelta):
        seconds = int(value.total_seconds())
        return f'{seconds // 3600:02}:{seconds % 3600 // 60:02}:{seconds % 60:02}'
    return value


def validate_catalog(systems, subsystems, elements):
    codes, pairs, locations = set(), set(), set()
    for s in systems:
        if 'SISTEMA' not in s or not str(s['SISTEMA'] or '').strip():
            raise ValueError('MDB_SYSTEM no contiene SISTEMA válido; no se sustituirá el catálogo.')
        code = int(s['CODE_SYS'])
        if code in codes: raise ValueError('CODE_SYS duplicado')
        codes.add(code)
    for s in subsystems:
        key = (int(s['CODE_SYS']), int(s['CODE_SUB_SYS']))
        if key[0] not in codes or key in pairs: raise ValueError('Relación de subsistemas inválida')
        pairs.add(key)
    for e in elements:
        key = (int(e['CODE_SYS']), int(e['CODE_SUB_SYS']))
        loc = int(e['LOCALIZACION'])
        if key not in pairs or loc in locations or int(e['CANTIDAD']) <= 0:
            raise ValueError('Relación, localización o cantidad de filtro inválida')
        locations.add(loc)


def download(path, connect, log=print):
    db = connect()
    try:
        with db.cursor() as cur:
            snapshots = []
            for _, remote, columns in CATALOGS:
                cur.execute(f'SELECT {",".join(columns)} FROM {remote}')
                snapshots.append(cur.fetchall())
            validate_catalog(*snapshots)
            cur.execute(f'SELECT {",".join(CHANGE_MAP)} FROM {CHANGES}')
            history = cur.fetchall()
        # Only replace caches AFTER all remote reads/validation succeed.
        with local(path) as conn:
            ensure_schema(conn)
            for (table, _, columns), rows in zip(CATALOGS, snapshots):
                conn.execute(f'DELETE FROM {table}')
                for row in rows:
                    values = [normalize(row[c]) for c in columns]
                    if 'PTBG_FLT' in columns:
                        values[columns.index('PTBG_FLT')] = int(row.get('PTBG_FLT') or 0)
                    conn.execute(f'INSERT INTO {table} ({",".join(columns)}) VALUES ({",".join("?" for _ in columns)})', values)
            remote_ids = set()
            for r in history:
                uid = str(r['UUID'] or '').strip()
                if not uid: raise ValueError('Historial de filtros sin UUID; requiere revisión')
                if uid in remote_ids: raise ValueError('UUID duplicado en FLT_CHANGE')
                remote_ids.add(uid)
                previous = conn.execute('SELECT sincronizado FROM FILTROS_CAMBIOS_LOCAL WHERE uuid=?', (uid,)).fetchone()
                if previous and previous['sincronizado'] == 0:
                    continue  # Never overwrite an unsent capture.
                columns = list(CHANGE_MAP.values())
                values = [normalize(r[c]) if r[c] is not None else '' for c in CHANGE_MAP]
                if previous:
                    conn.execute('UPDATE FILTROS_CAMBIOS_LOCAL SET ' + ','.join(f'{c}=?' for c in columns) +
                                 ', sincronizado=1,error_sync=NULL WHERE uuid=?', values + [uid])
                else:
                    conn.execute(f'INSERT INTO FILTROS_CAMBIOS_LOCAL ({",".join(columns)},sincronizado) VALUES ({",".join("?" for _ in columns)},1)', values)
            # Server is authoritative for confirmed history, not for pending work.
            for r in conn.execute('SELECT uuid FROM FILTROS_CAMBIOS_LOCAL WHERE sincronizado=1').fetchall():
                if r['uuid'] not in remote_ids:
                    conn.execute('DELETE FROM FILTROS_CAMBIOS_LOCAL WHERE uuid=? AND sincronizado=1', (r['uuid'],))
            # Even an intentionally empty server catalog must never be reseeded.
            conn.execute("INSERT OR REPLACE INTO FILTROS_META (clave,valor) VALUES ('catalog_source','server')")
        log(f'Filtros: {len(snapshots[2])} elementos y {len(history)} cambios descargados.')
    finally:
        db.close()


def mark(path, table, uuid, error=None):
    with local(path) as conn:
        conn.execute(f'UPDATE {table} SET sincronizado=?,error_sync=? WHERE uuid=?', (0 if error else 1, error, uuid))
        if table == 'FILTROS_CAMBIOS_LOCAL':
            # Reservation only. Older uploaders must never send it to MOT_INDICE.
            conn.execute('''UPDATE ORDENES_TRABAJO_LOCAL SET sincronizado=1,error_sync=NULL
                WHERE modulo='filtros' AND odt=(SELECT odt FROM FILTROS_CAMBIOS_LOCAL WHERE uuid=?)''', (uuid,))


def validate_change(row):
    UUID(row['uuid'])
    date.fromisoformat(row['fecha'])
    time.fromisoformat(row['hora'])
    for key, limit in [('sistema',50), ('tagname',150), ('elemento',150), ('responsable',150),
                       ('cargo',150), ('modelo',150), ('marca',150), ('especificaciones',50), ('tablet_origen',100)]:
        text = str(row.get(key) or '').strip()
        if (not text and key != 'tagname') or len(text) > limit:
            raise ValueError(f'{key}: dato vacío o longitud inválida')
    if int(row['cantidad'] or 0) <= 0: raise ValueError('Cantidad completa no capturada')


def refresh_installed_filter(cur, row):
    """Project the newest replacement into the catalog, including safe retries.

    Use service time rather than upload order so a late offline tablet cannot
    restore an older model. ID makes equal timestamps deterministic.
    """
    identity = (row['localizacion'], row['code_sys'], row['code_sub_sys'])
    cur.execute(f'''SELECT MODELO, MARCA, ESPECIFICACIONES FROM {CHANGES}
        WHERE LOCALIZACION=%s AND CODE_SYS=%s AND CODE_SUB_SYS=%s
        ORDER BY FECHA DESC, HORA DESC, ID DESC LIMIT 1''', identity)
    latest = cur.fetchone()
    if latest is None:
        raise ValueError('No se encontró el cambio de filtro para actualizar su ficha')
    cur.execute(f'''UPDATE {ELEMENTS} SET MODELO=%s, MARCA=%s, ESPECIFICACIONES=%s
        WHERE LOCALIZACION=%s AND CODE_SYS=%s AND CODE_SUB_SYS=%s''',
        (latest['MODELO'], latest['MARCA'], latest['ESPECIFICACIONES']) + identity)


def upload(path, connect, remap, log=print):
    rows = pending(path)
    result = dict(total=len(rows), uploaded=0, skipped=0, failed=0, messages=[])
    if not rows: return result
    db = None
    try:
        db = connect()
        with db.cursor() as cur, odt_lock(cur):
            for row in rows:
                try:
                    validate_change(row)
                    cur.execute(f'SELECT {",".join(CHANGE_MAP)} FROM {CHANGES} WHERE UUID=%s', (row['uuid'],))
                    existing = cur.fetchall()
                    if existing:
                        # Same UUID with different payload is a conflict, never a silent success.
                        if len(existing) != 1 or any(str(normalize(existing[0][remote]) or '') != str(row[key] or '')
                            for remote, key in CHANGE_MAP.items() if key != 'odt'):
                            raise ValueError('UUID existente con contenido distinto; requiere revisión')
                        final_odt = int(existing[0]['ODT'])
                        if final_odt != int(row['odt']): remap(path, int(row['odt']), final_odt)
                        refresh_installed_filter(cur, row)
                        db.commit()
                        mark(path, 'FILTROS_CAMBIOS_LOCAL', row['uuid'])
                        result['skipped'] += 1
                        continue
                    cur.execute(f'''SELECT e.*, s.SISTEMA FROM {ELEMENTS} e
                        JOIN {SYSTEM} s ON s.CODE_SYS=e.CODE_SYS
                        JOIN {SUBSYSTEM} sub ON sub.CODE_SYS=e.CODE_SYS AND sub.CODE_SUB_SYS=e.CODE_SUB_SYS
                        WHERE e.LOCALIZACION=%s AND s.PTBG_FLT=1 AND sub.PTBG_FLT=1''', (row['localizacion'],))
                    found = cur.fetchall()
                    if len(found) != 1: raise ValueError('Filtro no habilitado o relación ambigua; revisar catálogo')
                    for remote, key in [('CODE_SYS','code_sys'), ('CODE_SUB_SYS','code_sub_sys'), ('CANTIDAD','cantidad'),
                                        ('ELEMENTO','elemento'), ('TAGNAME','tagname'), ('SISTEMA','sistema')]:
                        if str(found[0].get(remote) or '') != str(row[key] or ''):
                            raise ValueError(f'Catálogo cambió ({remote}); se conserva el pendiente para revisión')
                    cur.execute('SELECT ODT FROM MOT_INDICE WHERE ODT=%s', (row['odt'],))
                    motor_collision = cur.fetchone()
                    if motor_collision or filter_odt_max(cur, row['odt']):
                        cur.execute('SELECT COALESCE(MAX(ODT),0) AS max_odt FROM MOT_INDICE')
                        maximum = max(int((cur.fetchone() or {}).get('max_odt') or 0), filter_odt_max(cur))
                        with local(path) as conn:
                            local_max = conn.execute('SELECT COALESCE(MAX(odt),0) FROM ORDENES_TRABAJO_LOCAL').fetchone()[0]
                        new = max(maximum, int(local_max), int(row['odt'])) + 1
                        if new > 2147483647: raise ValueError('No hay rango INT disponible para ODT')
                        remap(path, int(row['odt']), new)
                        row['odt'] = new
                    cur.execute(f'INSERT INTO {CHANGES} ({",".join(CHANGE_MAP)}) VALUES ({",".join("%s" for _ in CHANGE_MAP)})',
                                tuple(row[k] for k in CHANGE_MAP.values()))
                    refresh_installed_filter(cur, row)
                    db.commit()
                    mark(path, 'FILTROS_CAMBIOS_LOCAL', row['uuid'])
                    result['uploaded'] += 1
                except Exception as exc:
                    db.rollback()
                    message = str(exc)[:500]
                    mark(path, 'FILTROS_CAMBIOS_LOCAL', row['uuid'], message)
                    result['failed'] += 1
                    result['messages'].append(message)
    except Exception as exc:
        # Connection/lock failure: preserve every unconfirmed record.
        remaining = pending(path)
        result['failed'] = len(remaining)
        for row in remaining: mark(path, 'FILTROS_CAMBIOS_LOCAL', row['uuid'], str(exc)[:500])
        result['messages'].append(str(exc))
    finally:
        if db: db.close()
    log(f"Filtros: {result['uploaded']} subidos, {result['skipped']} existentes, {result['failed']} errores.")
    return result


def upload_catalog(path, connect, log=print):
    rows = pending(path, 'FILTROS_CATALOGO_PENDING')
    result = dict(total=len(rows), uploaded=0, skipped=0, failed=0, messages=[])
    if not rows: return result
    db = None
    try:
        db = connect()
        with db.cursor() as cur, odt_lock(cur):
            for row in rows:
                try:
                    # Server role is authoritative; a local preference is not authorization.
                    cur.execute('SELECT ROL FROM PTBG_DAT.MDB_USERS WHERE USUARIO=%s', (row['responsable'],))
                    users = cur.fetchall()
                    if len(users) != 1 or str(users[0].get('ROL') or '').strip().upper() not in ('ADMIN','ADMINISTRADOR'):
                        raise PermissionError('El responsable no es administrador en MDB_USERS')
                    p = json.loads(row['payload'])
                    disposition = 'uploaded'
                    if row['accion'] == 'add':
                        columns = CATALOGS[2][2][1:]
                        for key in ['CODE_SYS','CODE_SUB_SYS','CANTIDAD','LOCALIZACION']:
                            n = int(p[key])
                            if n < 1 or n > 32767: raise ValueError(f'{key} fuera de rango')
                            p[key] = n
                        for key in ['TAGNAME','ELEMENTO','MODELO','MARCA','ESPECIFICACIONES']:
                            if not str(p[key]).strip() or len(str(p[key])) > (50 if key == 'ESPECIFICACIONES' else 150):
                                raise ValueError(f'{key} inválido')
                        cur.execute(f'''SELECT sub.ID FROM {SUBSYSTEM} sub JOIN {SYSTEM} s ON s.CODE_SYS=sub.CODE_SYS
                            WHERE sub.CODE_SYS=%s AND sub.CODE_SUB_SYS=%s AND sub.PTBG_FLT=1 AND s.PTBG_FLT=1''', (p['CODE_SYS'], p['CODE_SUB_SYS']))
                        if len(cur.fetchall()) != 1: raise ValueError('Sistema/subsistema no habilitado o ambiguo')
                        cur.execute(f'SELECT {",".join(columns)} FROM {ELEMENTS} WHERE LOCALIZACION=%s', (p['LOCALIZACION'],))
                        existing = cur.fetchall()
                        if existing:
                            if len(existing) != 1 or any(str(existing[0][k] or '') != str(p[k] or '') for k in columns):
                                raise ValueError('Localización ya utilizada con otros datos')
                            disposition = 'skipped'
                        else:
                            cur.execute(f'INSERT INTO {ELEMENTS} ({",".join(columns)}) VALUES ({",".join("%s" for _ in columns)})', tuple(p[k] for k in columns))
                            db.commit()
                    elif row['accion'] in ('system','subsystem'):
                        table = SYSTEM if row['accion'] == 'system' else SUBSYSTEM
                        where = 'CODE_SYS=%s' + (' AND CODE_SUB_SYS=%s' if table == SUBSYSTEM else '')
                        args = (int(p['CODE_SYS']),) + ((int(p['CODE_SUB_SYS']),) if table == SUBSYSTEM else ())
                        value, previous = int(p['PTBG_FLT']), int(p['previous'])
                        if value not in (0,1) or previous not in (0,1): raise ValueError('Bandera inválida')
                        cur.execute(f'SELECT PTBG_FLT FROM {table} WHERE {where} FOR UPDATE', args)
                        current = cur.fetchall()
                        if len(current) != 1: raise ValueError('Código inexistente o duplicado')
                        current_value = int(current[0]['PTBG_FLT'] or 0)
                        if current_value == value:
                            disposition = 'skipped'
                        elif current_value != previous:
                            raise ValueError('El estado cambió en la planta; descargue y revise')
                        else:
                            cur.execute(f'UPDATE {table} SET PTBG_FLT=%s WHERE {where}', (value,) + args)
                            db.commit()
                    else: raise ValueError('Acción no permitida')
                    mark(path, 'FILTROS_CATALOGO_PENDING', row['uuid'])
                    result[disposition] += 1
                except Exception as exc:
                    db.rollback()
                    mark(path, 'FILTROS_CATALOGO_PENDING', row['uuid'], str(exc)[:500])
                    result['failed'] += 1
                    result['messages'].append(str(exc))
    except Exception as exc:
        remaining = pending(path, 'FILTROS_CATALOGO_PENDING')
        result['failed'] = len(remaining)
        for row in remaining: mark(path, 'FILTROS_CATALOGO_PENDING', row['uuid'], str(exc)[:500])
        result['messages'].append(str(exc))
    finally:
        if db: db.close()
    log(f"Catálogo filtros: {result['uploaded']} solicitudes aplicadas; {result['failed']} errores.")
    return result
