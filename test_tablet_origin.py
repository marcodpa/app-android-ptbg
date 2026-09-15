"""Isolated provenance/ODT tests: no connection to the plant database."""
import sqlite3
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

import tablet_uploader as uploader


@contextmanager
def local_db(path):
    conn = sqlite3.connect(path)
    try:
        with conn:
            yield conn
    finally:
        conn.close()


class MariaCursor:
    def __init__(self, db):
        self.db = db

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql, params=()):
        self.result = self.db.conn.execute(sql.replace('%s', '?'), params)

    def fetchone(self):
        row = self.result.fetchone()
        return dict(row) if row else None


class MariaDb:
    def __init__(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.row_factory = sqlite3.Row
        cols = ','.join(f'{c} TEXT' for c in uploader.WORK_ORDER_COLUMNS if c != 'ODT')
        self.conn.execute(f'CREATE TABLE MOT_INDICE (ODT INTEGER PRIMARY KEY,{cols})')
        self.fail_commit = False

    def cursor(self):
        return MariaCursor(self)

    def commit(self):
        if self.fail_commit:
            raise RuntimeError('conexion interrumpida')
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()

    def close(self):
        pass


class TabletOriginTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / 'tablet.db'
        self.maria = MariaDb()
        self.connect = patch('tablet_uploader.connect_mariadb', return_value=self.maria)
        self.connect.start()
        with local_db(self.db) as conn:
            uploader.ensure_work_order_schema(conn)

    def tearDown(self):
        self.connect.stop()
        self.maria.conn.close()
        self.tmp.cleanup()

    def order(self, origin='Tablet A', odt=100, db=None):
        with local_db(db or self.db) as conn:
            uploader.ensure_work_order_schema(conn)
            conn.execute('''INSERT INTO ORDENES_TRABAJO_LOCAL
                (odt,fecha,hora,ubicacion,equipo,vibracion,lubricacion,tablet_origen)
                VALUES (?, '2026-09-10','10:00:00',43,'SEPARADOR',1,1,?)''', (odt, origin))

    def upload(self, db=None):
        return uploader.upload_pending_work_orders(db or self.db, log=lambda _: None)

    def test_additive_migration_keeps_legacy_and_pending_unknown(self):
        self.order(None)
        with local_db(self.db) as conn:
            conn.execute('ALTER TABLE ORDENES_TRABAJO_LOCAL DROP COLUMN tablet_origen')
            uploader.ensure_work_order_schema(conn)
            uploader.ensure_work_order_schema(conn)
            self.assertEqual(conn.execute('SELECT odt,tablet_origen,sincronizado FROM ORDENES_TRABAJO_LOCAL').fetchone(), (100, None, 0))
        self.assertEqual(self.upload().uploaded, 1)
        self.assertIsNone(self.maria.conn.execute('SELECT TABLET_ORIGEN FROM MOT_INDICE').fetchone()[0])

    def test_origin_saved_with_flags_and_repeat_is_idempotent(self):
        self.order()
        self.assertEqual(self.upload().uploaded, 1)
        with local_db(self.db) as conn:
            conn.execute('UPDATE ORDENES_TRABAJO_LOCAL SET sincronizado=0')
        self.assertEqual(self.upload().skipped, 1)
        row = self.maria.conn.execute('SELECT TABLET_ORIGEN,VIBRACION,LUBRICACION FROM MOT_INDICE').fetchone()
        self.assertEqual(tuple(row), ('Tablet A', '1', '1'))
        self.assertEqual(self.maria.conn.execute('SELECT COUNT(*) FROM MOT_INDICE').fetchone()[0], 1)

    def test_different_tablets_same_second_and_equipment_remap_all_services(self):
        self.order()
        self.upload()
        second = Path(self.tmp.name) / 'tablet_b.db'
        self.order('Tablet B', db=second)
        tables = ['MEDICIONES_LOCAL', 'TEMPERATURAS_LOCAL', 'ALINEACIONES_LOCAL',
                  'LUBRICACIONES_LOCAL', 'CAMBIOS_COUPLING_LOCAL', 'REEMPLAZOS_LOCAL',
                  'LIMPIEZAS_PLATO_LOCAL', 'AJUSTES_CORREA_LOCAL',
                  'CHECKLIST_COMPRESOR_LOCAL', 'CHECKLIST_BLACK_START_LOCAL']
        with local_db(second) as conn:
            for table in tables:
                conn.execute(f'CREATE TABLE {table} (odt INTEGER, uuid TEXT)')
                conn.execute(f"INSERT INTO {table} VALUES (100,'uuid-b')")
        self.assertEqual(self.upload(second).uploaded, 1)
        with local_db(second) as conn:
            self.assertEqual(conn.execute('SELECT odt,tablet_origen FROM ORDENES_TRABAJO_LOCAL').fetchone(), (101, 'Tablet B'))
            for table in tables:
                self.assertEqual(conn.execute(f'SELECT odt FROM {table}').fetchone()[0], 101)
        self.assertEqual([tuple(r) for r in self.maria.conn.execute('SELECT ODT,TABLET_ORIGEN FROM MOT_INDICE ORDER BY ODT')], [(100, 'Tablet A'), (101, 'Tablet B')])

    def test_copied_order_keeps_original_capturing_tablet(self):
        self.order('Tablet A')
        # The upload argument is the USB device, NOT the ODT's capture origin.
        with patch('tablet_uploader.upload_equipos_nuevos', return_value=uploader.UploadSummary()), \
             patch('tablet_uploader.upload_checklists_compresor', side_effect=RuntimeError('stop after ODT')):
            with self.assertRaises(RuntimeError):
                uploader.upload_pending_work(self.db, tablet='Tablet B', log=lambda _: None)
        self.assertEqual(self.maria.conn.execute('SELECT TABLET_ORIGEN FROM MOT_INDICE').fetchone()[0], 'Tablet A')

    def test_ambiguous_legacy_collision_does_not_overwrite_origin(self):
        self.order(None)
        self.upload()
        with local_db(self.db) as conn:
            conn.execute("UPDATE ORDENES_TRABAJO_LOCAL SET tablet_origen='Tablet B',sincronizado=0")
        self.assertEqual(self.upload().failed, 1)
        self.assertIsNone(self.maria.conn.execute('SELECT TABLET_ORIGEN FROM MOT_INDICE').fetchone()[0])
        self.assertEqual(len(uploader.fetch_pending_work_orders(self.db)), 1)

    def test_server_failure_keeps_pending_for_retry(self):
        self.order()
        self.maria.fail_commit = True
        self.assertEqual(self.upload().failed, 1)
        self.assertEqual(len(uploader.fetch_pending_work_orders(self.db)), 1)
        self.maria.fail_commit = False
        self.assertEqual(self.upload().uploaded, 1)

    def test_commit_succeeded_but_local_confirmation_failed_then_retry(self):
        self.order()
        original = uploader.mark_work_order_result
        def fail_success(*args, **kwargs):
            if kwargs.get('synced'):
                raise RuntimeError('interrupted after server commit')
            return original(*args, **kwargs)
        with patch('tablet_uploader.mark_work_order_result', side_effect=fail_success):
            self.assertEqual(self.upload().failed, 1)
        self.assertEqual(self.upload().skipped, 1)
        self.assertEqual(self.maria.conn.execute('SELECT COUNT(*) FROM MOT_INDICE').fetchone()[0], 1)

    def test_missing_server_column_holds_services_and_keeps_pending(self):
        self.order()
        self.maria.conn.execute('ALTER TABLE MOT_INDICE DROP COLUMN TABLET_ORIGEN')
        with patch('tablet_uploader.upload_equipos_nuevos', return_value=uploader.UploadSummary()), \
             patch('tablet_uploader.upload_checklists_compresor') as checklists, \
             patch('tablet_uploader.upload_pending') as measurements:
            summary = uploader.upload_pending_work(self.db, log=lambda _: None)
        self.assertEqual(summary.failed, 1)
        checklists.assert_not_called()
        measurements.assert_not_called()
        self.assertEqual(len(uploader.fetch_pending_work_orders(self.db)), 1)

    def test_invalid_origin_is_not_silently_truncated(self):
        self.order('X' * 101)
        self.assertEqual(self.upload().failed, 1)
        self.assertEqual(len(uploader.fetch_pending_work_orders(self.db)), 1)


if __name__ == '__main__':
    unittest.main()
