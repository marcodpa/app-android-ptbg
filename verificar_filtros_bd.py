"""Diagnóstico de solo lectura. Nunca altera tablas ni registra trabajos."""
import argparse
import json
from datetime import datetime
from pathlib import Path

import filter_sync
import tablet_uploader as uploader


def inspect_database():
    db = uploader.pymysql.connect(
        host=uploader.DB_HOST, port=uploader.DB_PORT,
        user=uploader.DB_USER, password=uploader.DB_PASS,
        database=uploader.DB_NAME, cursorclass=uploader.pymysql.cursors.DictCursor,
        charset='utf8mb4', connect_timeout=5, read_timeout=15, write_timeout=15,
    )
    result = {'checked_at': datetime.now().isoformat(), 'read_only': True,
              'tables': {}, 'warnings': []}
    try:
        with db.cursor() as cur:
            cur.execute('SET SESSION TRANSACTION READ ONLY')
            cur.execute('START TRANSACTION WITH CONSISTENT SNAPSHOT')
            expected = {remote: columns for _, remote, columns in filter_sync.CATALOGS}
            expected[filter_sync.CHANGES] = ('ID', *filter_sync.CHANGE_MAP)
            expected[f'{uploader.DB_NAME}.MOT_INDICE'] = ('ID', 'ODT', 'TABLET_ORIGEN')
            expected['PTBG_DAT.MDB_USERS'] = ('USUARIO', 'ROL')
            for table, columns in expected.items():
                schema, name = table.split('.')
                cur.execute('SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA '
                            'FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s',
                            (schema, name))
                actual = cur.fetchall()
                missing = sorted(set(columns) - {c['COLUMN_NAME'] for c in actual})
                cur.execute('SELECT ENGINE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s',
                            (schema, name))
                engine = (cur.fetchone() or {}).get('ENGINE')
                cur.execute('SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME, SEQ_IN_INDEX '
                            'FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s '
                            'ORDER BY INDEX_NAME, SEQ_IN_INDEX', (schema, name))
                indexes = cur.fetchall()
                result['tables'][table] = dict(columns=actual, missing=missing, engine=engine, indexes=indexes)
                if missing:
                    result['warnings'].append(f'{table}: faltan columnas {missing}')
                if engine != 'InnoDB':
                    result['warnings'].append(f'{table}: motor {engine}, revisar transacciones')
                # Proves SELECT access without exposing user records/history.
                cur.execute(f'SELECT {",".join(columns)} FROM {table} LIMIT 0')
            snapshots = []
            for _, table, columns in filter_sync.CATALOGS:
                cur.execute(f'SELECT {",".join(columns)} FROM {table}')
                snapshots.append(cur.fetchall())
            filter_sync.validate_catalog(*snapshots)
            result['catalog_counts'] = dict(zip(('systems', 'subsystems', 'elements'), map(len, snapshots)))
            result['systems'] = snapshots[0]
            bundled = json.loads(Path('assets/data/filter_catalog.json').read_text(encoding='utf-8'))
            result['matches_bundled_snapshot'] = all(
                sorted(rows, key=lambda r: r['ID']) == sorted(bundled[key], key=lambda r: r['ID'])
                for rows, key in zip(snapshots, ('systems', 'subsystems', 'elements')))
            cur.execute('SELECT COUNT(*) AS total FROM PTBG_FLT.FLT_CHANGE')
            result['changes_count'] = cur.fetchone()['total']
            for key in ('UUID', 'ODT'):
                cur.execute(f'SELECT COUNT(*) AS total FROM (SELECT {key} FROM PTBG_FLT.FLT_CHANGE '
                            f'GROUP BY {key} HAVING COUNT(*)>1) duplicates_found')
                result[f'duplicate_{key.lower()}_groups'] = cur.fetchone()['total']
            # Grants may contain authentication hashes: never output raw grants.
            cur.execute('SHOW GRANTS FOR CURRENT_USER')
            privileges = []
            for row in cur.fetchall():
                grant = str(next(iter(row.values())))
                if grant.startswith('GRANT ') and ' ON ' in grant and ' TO ' in grant:
                    privileges.append(grant.split(' TO ', 1)[0][6:])
            result['declared_privileges'] = privileges
            result['warnings'].append('Permisos de escritura solo inspeccionados; no se ejecutó INSERT/UPDATE.')
            result['ok'] = not any(t['missing'] for t in result['tables'].values())
    finally:
        db.rollback()
        db.close()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pedir-clave', action='store_true')
    parser.add_argument('--salida', type=Path, required=True)
    args = parser.parse_args()
    if args.pedir_clave:
        from abrir_subidor_seguro import request_credentials
        if not request_credentials():
            return 2
    try:
        result = inspect_database()
    except Exception as exc:
        # No credential values, grants or connection tracebacks in diagnostics.
        result = {'ok': False, 'read_only': True, 'error_type': type(exc).__name__,
                  'error_code': exc.args[0] if exc.args and isinstance(exc.args[0], int) else None}
    args.salida.parent.mkdir(parents=True, exist_ok=True)
    args.salida.write_text(json.dumps(result, indent=2, ensure_ascii=False, default=str), encoding='utf-8')
    print('Diagnóstico guardado. Solo lectura. Resultado:', 'OK' if result['ok'] else 'REQUIERE REVISION')
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
