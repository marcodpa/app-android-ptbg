"""Integration contracts against isolated SQLite databases; never the plant."""
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import filter_sync as fs
import tablet_uploader as up


class Cursor:
    def __init__(self, db): self.db = db
    def __enter__(self): return self
    def __exit__(self, *_): pass
    def execute(self, sql, args=()):
        self.db.queries.append(sql)
        self.result = self.db.conn.execute(sql.replace('%s','?').replace(' FOR UPDATE',''), args)
    def fetchone(self):
        r = self.result.fetchone()
        return dict(r) if r else None
    def fetchall(self): return [dict(r) for r in self.result.fetchall()]


class Server:
    def __init__(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.row_factory = sqlite3.Row
        self.lock = 1
        self.fail_commit = False
        self.queries = []
        self.conn.create_function('GET_LOCK', 2, lambda *_: self.lock)
        self.conn.create_function('RELEASE_LOCK', 1, lambda *_: 1)
        for db in ['PTBG_DAT','PTBG_FLT']: self.conn.execute(f"ATTACH DATABASE ':memory:' AS {db}")
        for _, name, cols in fs.CATALOGS:
            self.conn.execute(f'CREATE TABLE {name} (' + ','.join(f'{c} {"INTEGER" if c in ("ID","CODE_SYS","CODE_SUB_SYS","PTBG_FLT","CANTIDAD","LOCALIZACION") else "TEXT"}' for c in cols) + ')')
        self.conn.execute(f'CREATE TABLE {fs.CHANGES} (ID INTEGER PRIMARY KEY,' + ','.join(f'{c} {"INTEGER" if c in ("ODT","CODE_SYS","CODE_SUB_SYS","LOCALIZACION") else "TEXT"}' for c in fs.CHANGE_MAP) + ')')
        self.conn.execute('CREATE TABLE MOT_INDICE (ODT INTEGER PRIMARY KEY,' + ','.join(f'{c} TEXT' for c in up.WORK_ORDER_COLUMNS if c != 'ODT') + ')')
        self.conn.execute('CREATE TABLE PTBG_DAT.MDB_USERS (USUARIO TEXT, ROL TEXT)')
        self.conn.execute("INSERT INTO PTBG_DAT.MDB_USERS VALUES ('ADMIN TEST','ADMIN')")
        self.conn.execute("INSERT INTO PTBG_DAT.MDB_SYSTEM VALUES (11,'BG1',1,1)")
        self.conn.execute("INSERT INTO PTBG_DAT.MDB_SUBSYSTEM VALUES (90,1,'Aire para ventilación y combustión',1,1)")
        self.conn.execute("INSERT INTO PTBG_FLT.FLT_ELEMENTS VALUES (20,'N/A',1,1,'Filtro aire',152,1,'SIN DATOS','SIN DATOS','SIN DATOS')")
        self.conn.commit()
    def cursor(self): return Cursor(self)
    def commit(self):
        if self.fail_commit: raise RuntimeError('corte de conexión')
        self.conn.commit()
    def rollback(self): self.conn.rollback()
    def close(self): pass  # Test server lives across client connections.


class FilterSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)/'tablet.db'
        self.server = Server()
        with fs.local(self.path) as conn:
            up.ensure_work_order_schema(conn)
            fs.ensure_schema(conn)
        self.connect = lambda: self.server
        fs.download(self.path, self.connect, lambda _: None)
    def tearDown(self):
        self.server.conn.close()
        self.tmp.cleanup()
    def capture(self, odt=100, origin='Tablet A'):
        uid = str(uuid4())
        row = dict(uuid=uid,odt=odt,fecha='2026-09-21',hora='10:00:00',sistema='BG1',code_sys=1,
                   code_sub_sys=1,localizacion=1,tagname='N/A',elemento='Filtro aire',cantidad=152,
                   modelo='MODELO X',marca='MARCA X',especificaciones='10',observaciones='',
                   responsable='ADMIN TEST',cargo='Mecánico',tablet_origen=origin)
        with fs.local(self.path) as conn:
            conn.execute("INSERT INTO ORDENES_TRABAJO_LOCAL (odt,fecha,hora,equipo,ubicacion,tablet_origen,modulo,sincronizado) VALUES (?,? ,?,'Filtro aire',1,?,'filtros',1)",(odt,row['fecha'],row['hora'],origin))
            conn.execute('INSERT INTO FILTROS_CAMBIOS_LOCAL ('+','.join(row)+') VALUES ('+','.join('?' for _ in row)+')',tuple(row.values()))
        return uid
    def upload(self): return fs.upload(self.path,self.connect,up.remap_local_odt,lambda _:None)
    def scalar(self, sql):
        with fs.local(self.path) as c: return c.execute(sql).fetchone()[0]
    def test_schema_is_additive_and_repeatable(self):
        self.capture()
        with fs.local(self.path) as c:
            fs.ensure_schema(c); fs.ensure_schema(c)
        self.assertEqual(self.scalar('SELECT cantidad FROM FILTROS_CAMBIOS_LOCAL'),152)
        self.assertEqual(up.fetch_pending_work_orders(self.path),[])
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM ORDENES_TRABAJO_LOCAL WHERE sincronizado=0'),0)
    def test_upload_preserves_origin_and_retry_is_idempotent(self):
        self.capture()
        self.assertEqual(self.upload()['uploaded'],1)
        with fs.local(self.path) as c: c.execute('UPDATE FILTROS_CAMBIOS_LOCAL SET sincronizado=0')
        self.assertEqual(self.upload()['skipped'],1)
        self.assertEqual(self.server.conn.execute('SELECT COUNT(*) FROM PTBG_FLT.FLT_CHANGE').fetchone()[0],1)
        self.assertEqual(self.server.conn.execute('SELECT TABLET_ORIGEN FROM PTBG_FLT.FLT_CHANGE').fetchone()[0],'Tablet A')
    def test_replacement_updates_installed_catalog(self):
        self.capture()
        self.assertEqual(self.upload()['uploaded'], 1)
        row = self.server.conn.execute('SELECT MODELO,MARCA,ESPECIFICACIONES FROM PTBG_FLT.FLT_ELEMENTS').fetchone()
        self.assertEqual(tuple(row), ('MODELO X', 'MARCA X', '10'))
    def test_late_older_change_and_retry_keep_newest_installed_model(self):
        self.capture()
        self.upload()
        uid = self.capture(101)
        with fs.local(self.path) as c:
            c.execute("UPDATE FILTROS_CAMBIOS_LOCAL SET fecha='2026-09-20',modelo='ANTERIOR' WHERE uuid=?", (uid,))
        self.assertEqual(self.upload()['uploaded'], 1)
        self.assertEqual(self.server.conn.execute('SELECT MODELO FROM PTBG_FLT.FLT_ELEMENTS').fetchone()[0], 'MODELO X')
        with fs.local(self.path) as c:
            c.execute('UPDATE FILTROS_CAMBIOS_LOCAL SET sincronizado=0 WHERE uuid=?', (uid,))
        self.assertEqual(self.upload()['skipped'], 1)
        self.assertEqual(self.server.conn.execute('SELECT MODELO FROM PTBG_FLT.FLT_ELEMENTS').fetchone()[0], 'MODELO X')
    def test_failed_commit_rolls_back_catalog_with_history(self):
        self.capture()
        self.server.fail_commit = True
        self.assertEqual(self.upload()['failed'], 1)
        self.assertEqual(self.server.conn.execute('SELECT MODELO FROM PTBG_FLT.FLT_ELEMENTS').fetchone()[0], 'SIN DATOS')
        self.assertEqual(self.server.conn.execute('SELECT COUNT(*) FROM PTBG_FLT.FLT_CHANGE').fetchone()[0], 0)
    def test_empty_motor_draft_never_connects_or_uploads(self):
        with fs.local(self.path) as c:
            c.execute("INSERT INTO ORDENES_TRABAJO_LOCAL (odt,fecha,hora,ubicacion) VALUES (1790168727,'2026-09-23','09:05:27',16)")
        with patch('tablet_uploader.connect_mariadb') as connect:
            result = up.upload_pending_work_orders(self.path, log=lambda _: None)
        connect.assert_not_called()
        self.assertEqual(result.uploaded, 0)
        self.assertEqual(self.scalar('SELECT sincronizado FROM ORDENES_TRABAJO_LOCAL'), 0)
    def test_checklists_with_zero_flags_are_real_orders(self):
        for index, table in enumerate(('CHECKLIST_COMPRESOR_LOCAL', 'CHECKLIST_BLACK_START_LOCAL')):
            odt = 200 + index
            with fs.local(self.path) as c:
                c.execute(f'CREATE TABLE {table} (odt INTEGER)')
                c.execute(f'INSERT INTO {table} VALUES (?)', (odt,))
                c.execute("INSERT INTO ORDENES_TRABAJO_LOCAL (odt,fecha,hora,ubicacion) VALUES (?,'2026-09-23','09:05:27',16)", (odt,))
            with patch('tablet_uploader.connect_mariadb', self.connect):
                result = up.upload_pending_work_orders(self.path, log=lambda _: None)
            self.assertEqual(result.uploaded, 1)
        self.assertEqual(self.server.conn.execute('SELECT COUNT(*) FROM MOT_INDICE').fetchone()[0], 2)
    def test_motor_number_collision_remaps_filter_and_reservation(self):
        self.capture()
        self.server.conn.execute('INSERT INTO MOT_INDICE (ODT) VALUES (100)'); self.server.conn.commit()
        self.assertEqual(self.upload()['uploaded'],1)
        self.assertEqual(self.scalar('SELECT odt FROM FILTROS_CAMBIOS_LOCAL'),101)
        self.assertEqual(self.scalar('SELECT odt FROM ORDENES_TRABAJO_LOCAL'),101)
    def test_motor_upload_checks_filter_number_namespace(self):
        self.capture(); self.upload()
        with fs.local(self.path) as c:
            c.execute('DELETE FROM ORDENES_TRABAJO_LOCAL')
            c.execute("INSERT INTO ORDENES_TRABAJO_LOCAL (odt,fecha,hora,ubicacion,tablet_origen,vibracion) VALUES (100,'2026-09-21','12:00:00',3,'Tablet B',1)")
        with patch('tablet_uploader.connect_mariadb', self.connect):
            result = up.upload_pending_work_orders(self.path,log=lambda _:None)
        self.assertEqual(result.uploaded,1)
        self.assertEqual(self.server.conn.execute('SELECT ODT FROM MOT_INDICE').fetchone()[0],101)
        self.assertEqual(self.scalar('SELECT odt FROM FILTROS_CAMBIOS_LOCAL'),100)
    def test_commit_failure_keeps_pending_then_retry(self):
        self.capture(); self.server.fail_commit=True
        self.assertEqual(self.upload()['failed'],1)
        self.assertEqual(len(fs.pending(self.path)),1)
        self.server.fail_commit=False
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM ORDENES_TRABAJO_LOCAL WHERE sincronizado=0'),0)
        self.assertEqual(self.upload()['uploaded'],1)
    def test_commit_succeeded_local_ack_failed_then_retry(self):
        self.capture()
        original=fs.mark
        def fail_ack(path,table,uid,error=None):
            if not error: raise RuntimeError('interrumpido antes de confirmar tablet')
            return original(path,table,uid,error)
        with patch('filter_sync.mark',side_effect=fail_ack): self.assertEqual(self.upload()['failed'],1)
        self.assertEqual(self.upload()['skipped'],1)
    def test_lock_busy_prevents_inserts(self):
        self.capture(); self.server.lock=0
        self.assertEqual(self.upload()['failed'],1)
        self.assertEqual(len(fs.pending(self.path)),1)
        self.assertEqual(self.server.conn.execute('SELECT COUNT(*) FROM PTBG_FLT.FLT_CHANGE').fetchone()[0],0)
    def test_changed_quantity_is_not_silently_overwritten(self):
        self.capture()
        self.server.conn.execute('UPDATE PTBG_FLT.FLT_ELEMENTS SET CANTIDAD=160'); self.server.conn.commit()
        self.assertEqual(self.upload()['failed'],1)
        self.assertEqual(self.scalar('SELECT cantidad FROM FILTROS_CAMBIOS_LOCAL'),152)
    def test_download_preserves_pending_and_removes_deleted_confirmed_only(self):
        self.capture(); self.upload()
        self.capture(101)
        self.server.conn.execute('DELETE FROM PTBG_FLT.FLT_CHANGE'); self.server.conn.commit()
        fs.download(self.path,self.connect,lambda _:None)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM FILTROS_CAMBIOS_LOCAL'),1)
        self.assertEqual(self.scalar('SELECT odt FROM FILTROS_CAMBIOS_LOCAL'),101)
    def test_invalid_catalog_rolls_back_entire_download(self):
        self.server.conn.execute('UPDATE PTBG_DAT.MDB_SUBSYSTEM SET CODE_SYS=99');self.server.conn.commit()
        with self.assertRaises(ValueError): fs.download(self.path,self.connect,lambda _:None)
        self.assertEqual(self.scalar('SELECT CODE_SYS FROM FILTROS_SUBSYSTEM'),1)
        with self.assertRaises(ValueError): fs.validate_catalog([{'ID':1,'NAME_SUB_SYS':'wrong'}],[],[])
    def test_download_marks_even_empty_catalog_as_server_authoritative(self):
        self.assertEqual(self.scalar("SELECT valor FROM FILTROS_META WHERE clave='catalog_source'"),'server')
        for _, table, _ in fs.CATALOGS:
            self.server.conn.execute(f'DELETE FROM {table}')
        self.server.conn.commit()
        fs.download(self.path,self.connect,lambda _:None)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM FILTROS_ELEMENTS'),0)
        self.assertEqual(self.scalar("SELECT valor FROM FILTROS_META WHERE clave='catalog_source'"),'server')
    def request(self,action,payload):
        with fs.local(self.path) as c:
            c.execute('INSERT INTO FILTROS_CATALOGO_PENDING (uuid,accion,payload,responsable,tablet_origen) VALUES (?,?,?,?,?)',
                      (str(uuid4()),action,json.dumps(payload),'ADMIN TEST','Tablet A'))
    def test_admin_activation_no_delete_and_no_local_premature_change(self):
        self.request('subsystem',dict(CODE_SYS=1,CODE_SUB_SYS=1,previous=1,PTBG_FLT=0))
        self.assertEqual(fs.upload_catalog(self.path,self.connect,lambda _:None)['uploaded'],1)
        self.assertEqual(self.scalar('SELECT PTBG_FLT FROM FILTROS_SUBSYSTEM'),1)
        fs.download(self.path,self.connect,lambda _:None)
        self.assertEqual(self.scalar('SELECT PTBG_FLT FROM FILTROS_SUBSYSTEM'),0)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM FILTROS_ELEMENTS'),1)
    def test_admin_server_role_required(self):
        self.request('system',dict(CODE_SYS=1,previous=1,PTBG_FLT=0))
        self.server.conn.execute("UPDATE PTBG_DAT.MDB_USERS SET ROL='USUARIO'");self.server.conn.commit()
        self.assertEqual(fs.upload_catalog(self.path,self.connect,lambda _:None)['failed'],1)
        self.assertEqual(self.server.conn.execute('SELECT PTBG_FLT FROM PTBG_DAT.MDB_SYSTEM').fetchone()[0],1)
    def test_add_is_idempotent_by_full_catalog_identity(self):
        p=dict(TAGNAME='TAG2',CODE_SYS=1,CODE_SUB_SYS=1,ELEMENTO='Filtro 2',CANTIDAD=4,LOCALIZACION=2,MODELO='X',MARCA='Y',ESPECIFICACIONES='10')
        self.request('add',p)
        self.assertEqual(fs.upload_catalog(self.path,self.connect,lambda _:None)['uploaded'],1)
        with fs.local(self.path) as c:c.execute('UPDATE FILTROS_CATALOGO_PENDING SET sincronizado=0')
        self.assertEqual(fs.upload_catalog(self.path,self.connect,lambda _:None)['skipped'],1)
        self.assertEqual(self.server.conn.execute('SELECT COUNT(*) FROM PTBG_FLT.FLT_ELEMENTS').fetchone()[0],2)
    def test_uuid_conflict_not_acknowledged(self):
        self.capture();self.upload()
        with fs.local(self.path) as c:c.execute("UPDATE FILTROS_CAMBIOS_LOCAL SET modelo='OTRO',sincronizado=0")
        self.assertEqual(self.upload()['failed'],1)
        self.assertEqual(len(fs.pending(self.path)),1)


if __name__ == '__main__': unittest.main()
