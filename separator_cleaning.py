"""Limpieza de plato tipo 10: SQLite offline <-> MOT_SEP_REG por ODT.

No crea ni modifica el esquema MariaDB; usa las tablas provistas por planta.
"""
import sqlite3
from datetime import datetime

TABLE = "LIMPIEZAS_PLATO_LOCAL"
COLUMNS = ("FECHA", "HORA", "HORAS_FUNCIONAMIENTO", "OBSERVACIONES", "USUARIO",
           "CARGO", "MARCA", "MODELO", "SERIAL", "ODT", "UUID")
LOCAL_COLUMNS = ("fecha", "hora", "horas_funcionamiento", "observaciones", "responsable",
                 "cargo", "marca", "modelo", "serial", "odt", "uuid")


def ensure_schema(conn):
    conn.execute(f"""CREATE TABLE IF NOT EXISTS {TABLE} (
      uuid TEXT PRIMARY KEY, localizacion INTEGER NOT NULL,
      fecha TEXT NOT NULL, hora TEXT NOT NULL,
      horas_funcionamiento INTEGER NOT NULL CHECK(horas_funcionamiento BETWEEN 0 AND 2147483647),
      observaciones TEXT, responsable TEXT, cargo TEXT, marca TEXT, modelo TEXT, serial TEXT,
      odt INTEGER NOT NULL, sincronizado INTEGER NOT NULL DEFAULT 0, error_sync TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)""")
    conn.execute(f"CREATE INDEX IF NOT EXISTS IDX_PLATO_PENDING ON {TABLE}(sincronizado, created_at)")
    conn.commit()


def upload(db_path, connect, log=print):
    result = dict(total=0, uploaded=0, skipped=0, failed=0, messages=[])
    local = sqlite3.connect(db_path)
    local.row_factory = sqlite3.Row
    remote = None
    try:
        ensure_schema(local)
        rows = [dict(r) for r in local.execute(f"SELECT * FROM {TABLE} WHERE sincronizado=0 ORDER BY created_at")]
        result['total'] = len(rows)
        if not rows:
            return result
        try:
            remote = connect()
        except Exception as exc:
            message = str(exc)
            local.execute(f"UPDATE {TABLE} SET error_sync=? WHERE sincronizado=0", (message[:500],))
            local.commit()
            result.update(failed=len(rows), messages=[message])
            return result
        for row in rows:
            try:
                # Nunca truncar un horometro decimal o asociar el detalle a otra ODT.
                hours = row['horas_funcionamiento']
                if not isinstance(hours, int) or not 0 <= hours <= 2147483647:
                    raise ValueError('Horometro invalido: se requieren horas enteras.')
                with remote.cursor() as cur:
                    cur.execute('SELECT UBICACION FROM MOT_INDICE WHERE ODT=%s FOR UPDATE', (row['odt'],))
                    order = cur.fetchone()
                    if not order or int(order['UBICACION']) != row['localizacion']:
                        raise ValueError('La ODT no esta sincronizada o pertenece a otro equipo.')
                    cur.execute('SELECT ODT FROM MOT_SEP_REG WHERE UUID=%s LIMIT 1', (row['uuid'],))
                    previous = cur.fetchone()
                    if previous and int(previous['ODT']) != row['odt']:
                        raise ValueError('El UUID de limpieza ya pertenece a otra ODT.')
                    if not previous:
                        cur.execute(f"INSERT INTO MOT_SEP_REG ({','.join(COLUMNS)}) VALUES ({','.join(['%s']*len(COLUMNS))})",
                                    tuple(row[k] for k in LOCAL_COLUMNS))
                    cur.execute('UPDATE MOT_INDICE SET LIMPIEZA_PLATO=1 WHERE ODT=%s AND UBICACION=%s',
                                (row['odt'], row['localizacion']))
                remote.commit()
                local.execute(f"UPDATE {TABLE} SET sincronizado=1, error_sync=NULL WHERE uuid=?", (row['uuid'],))
                local.commit()
                result['skipped' if previous else 'uploaded'] += 1
            except Exception as exc:
                remote.rollback()
                message = str(exc)
                local.execute(f"UPDATE {TABLE} SET error_sync=? WHERE uuid=? AND sincronizado=0", (message[:500], row['uuid']))
                local.commit()
                result['failed'] += 1
                result['messages'].append(message)
                log(f"Limpieza pendiente ODT {row['odt']}: {message}")
        return result
    finally:
        local.close()
        if remote is not None:
            remote.close()


def _date(value):
    text = str(value or '').strip().split(' ')[0]
    for pattern in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y'):
        try:
            return datetime.strptime(text, pattern).strftime('%Y-%m-%d')
        except ValueError:
            pass
    raise ValueError('Fecha invalida en el historial de limpieza; se conserva el historial local.')


def download(db_path, connect, log=print):
    remote = connect()
    try:
        with remote.cursor() as cur:
            cur.execute('SELECT s.*, i.UBICACION AS LOCALIZACION FROM MOT_SEP_REG s '
                        'JOIN MOT_INDICE i ON i.ODT=s.ODT ORDER BY s.ID')
            source = cur.fetchall()
    finally:
        remote.close()
    # Validar toda la descarga antes de reemplazar cualquier fila sincronizada.
    rows = {}
    for item in source:
        uuid = str(item.get('UUID') or f"MOT_SEP_REG:{item['ID']}")
        hours = item['HORAS_FUNCIONAMIENTO']
        if hours is None or int(hours) != hours or not 0 <= hours <= 2147483647:
            raise ValueError('Horometro invalido en MariaDB; no se reemplaza el historial local.')
        row = {k: item.get(c) for k, c in zip(LOCAL_COLUMNS, COLUMNS)}
        row.update(uuid=uuid, localizacion=int(item['LOCALIZACION']), fecha=_date(item['FECHA']),
                   hora=str(item.get('HORA') or ''), horas_funcionamiento=int(hours), sincronizado=1, error_sync=None)
        if uuid in rows and rows[uuid] != row:
            raise ValueError('ODT o UUID ambiguo en el historial de limpieza.')
        rows[uuid] = row
    local = sqlite3.connect(db_path)
    try:
        ensure_schema(local)
        with local:
            pending = {r[0] for r in local.execute(f'SELECT uuid FROM {TABLE} WHERE sincronizado=0')}
            local.execute(f'DELETE FROM {TABLE} WHERE sincronizado=1')
            for uuid, row in rows.items():
                if uuid in pending:
                    continue
                columns = tuple(row)
                local.execute(f"INSERT INTO {TABLE} ({','.join(columns)}) VALUES ({','.join(['?']*len(columns))})",
                              tuple(row[k] for k in columns))
    finally:
        local.close()
    log(f'Historial de limpieza de plato descargado: {len(rows)} registros.')
    return len(rows)
