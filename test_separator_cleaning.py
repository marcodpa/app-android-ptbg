import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import separator_cleaning as plate
import tablet_uploader as uploader
from test_tablet_uploader import FakeMariaCursor


class Cursor(FakeMariaCursor):
    def __enter__(self): return self
    def __exit__(self, *args): return False


class Remote:
    def __init__(self, conn): self.conn = conn
    def cursor(self): return Cursor(self.conn)
    def commit(self): self.conn.commit()
    def rollback(self): self.conn.rollback()
    def close(self): pass


class PlateSyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'tablet.db'
        self.local = sqlite3.connect(self.path)
        self.local.row_factory = sqlite3.Row
        plate.ensure_schema(self.local)
        uploader.ensure_work_order_schema(self.local)
        self.local.execute("INSERT INTO ORDENES_TRABAJO_LOCAL (odt,fecha,hora,ubicacion,limpieza_plato) VALUES (123,'2026-09-08','10:22:23',43,1)")
        self.local.execute(f"INSERT INTO {plate.TABLE} (uuid,localizacion,fecha,hora,horas_funcionamiento,odt,marca,modelo,serial) VALUES ('u1',43,'2026-09-08','10:22:23',0,123,'MOTOR','M1','SERIAL')")
        self.local.commit()
        self.maria = sqlite3.connect(':memory:')
        self.maria.row_factory = sqlite3.Row
        self.maria.execute('CREATE TABLE MOT_INDICE (ODT INTEGER, UBICACION INTEGER, LIMPIEZA_PLATO INTEGER)')
        self.maria.execute('INSERT INTO MOT_INDICE VALUES (123,43,0)')
        self.maria.execute('CREATE TABLE MOT_SEP_REG (ID INTEGER PRIMARY KEY AUTOINCREMENT, '
            'FECHA TEXT,HORA TEXT,HORAS_FUNCIONAMIENTO INTEGER,OBSERVACIONES TEXT,USUARIO TEXT,'
            'CARGO TEXT,MARCA TEXT,MODELO TEXT,SERIAL TEXT,ODT INTEGER,UUID TEXT)')
        self.maria.commit()
        self.connect = lambda: Remote(self.maria)

    def tearDown(self):
        self.local.close()
        self.maria.close()
        self.tmp.cleanup()

    def test_upload_vincula_odt_y_preserva_cero_motor_fecha(self):
        result = plate.upload(self.path, self.connect, lambda _: None)
        self.assertEqual(result['uploaded'], 1)
        row = self.maria.execute('SELECT * FROM MOT_SEP_REG').fetchone()
        self.assertEqual((row['HORAS_FUNCIONAMIENTO'], row['MARCA'], row['FECHA'], row['HORA'], row['ODT']),
                         (0, 'MOTOR', '2026-09-08', '10:22:23', 123))
        self.assertEqual(self.maria.execute('SELECT LIMPIEZA_PLATO FROM MOT_INDICE').fetchone()[0], 1)
        self.assertEqual(self.local.execute(f'SELECT sincronizado FROM {plate.TABLE}').fetchone()[0], 1)

    def test_reintento_no_duplica_si_servidor_ya_guardo(self):
        plate.upload(self.path, self.connect)
        self.local.execute(f'UPDATE {plate.TABLE} SET sincronizado=0')
        self.local.commit()
        result = plate.upload(self.path, self.connect)
        self.assertEqual(result['skipped'], 1)
        self.assertEqual(self.maria.execute('SELECT COUNT(*) FROM MOT_SEP_REG').fetchone()[0], 1)

    def test_odt_inexistente_o_de_otro_equipo_no_envia(self):
        self.maria.execute('UPDATE MOT_INDICE SET UBICACION=44')
        self.maria.commit()
        result = plate.upload(self.path, self.connect, lambda _: None)
        self.assertEqual(result['failed'], 1)
        self.assertEqual(self.maria.execute('SELECT COUNT(*) FROM MOT_SEP_REG').fetchone()[0], 0)
        row = self.local.execute(f'SELECT * FROM {plate.TABLE}').fetchone()
        self.assertEqual(row['sincronizado'], 0)
        self.assertTrue(row['error_sync'])

    def test_fallo_actualizando_indice_revierte_detalle(self):
        self.maria.execute("CREATE TRIGGER fallo BEFORE UPDATE ON MOT_INDICE BEGIN SELECT RAISE(ABORT,'fallo simulado'); END")
        self.maria.commit()
        self.assertEqual(plate.upload(self.path, self.connect, lambda _: None)['failed'], 1)
        self.assertEqual(self.maria.execute('SELECT COUNT(*) FROM MOT_SEP_REG').fetchone()[0], 0)

    def test_descarga_refleja_correcciones_borrados_y_no_borra_pendientes(self):
        plate.upload(self.path, self.connect)
        self.maria.execute("UPDATE MOT_SEP_REG SET HORAS_FUNCIONAMIENTO=321, OBSERVACIONES='Corregido', FECHA='08/09/2026'")
        self.maria.commit()
        plate.download(self.path, self.connect, lambda _: None)
        row = self.local.execute(f'SELECT * FROM {plate.TABLE}').fetchone()
        self.assertEqual((row['horas_funcionamiento'], row['observaciones'], row['fecha']), (321, 'Corregido', '2026-09-08'))
        self.local.execute(f"INSERT INTO {plate.TABLE} (uuid,localizacion,fecha,hora,horas_funcionamiento,odt) VALUES ('pendiente',43,'2026-09-08','12:00',400,123)")
        self.local.commit()
        self.maria.execute('DELETE FROM MOT_SEP_REG')
        self.maria.commit()
        plate.download(self.path, self.connect, lambda _: None)
        rows = self.local.execute(f'SELECT uuid FROM {plate.TABLE}').fetchall()
        self.assertEqual([r[0] for r in rows], ['pendiente'])

    def test_descarga_fallida_no_vacia_datos(self):
        plate.upload(self.path, self.connect)
        self.maria.execute('UPDATE MOT_SEP_REG SET HORAS_FUNCIONAMIENTO=NULL')
        self.maria.commit()
        with self.assertRaises(ValueError): plate.download(self.path, self.connect)
        self.assertEqual(self.local.execute(f'SELECT COUNT(*) FROM {plate.TABLE}').fetchone()[0], 1)

    def test_colision_odt_reasigna_tambien_limpieza(self):
        uploader.remap_local_odt(self.path, 123, 456)
        self.assertEqual(self.local.execute(f'SELECT odt FROM {plate.TABLE}').fetchone()[0], 456)
        self.assertEqual(self.local.execute('SELECT odt FROM ORDENES_TRABAJO_LOCAL').fetchone()[0], 456)

    def test_indice_flag_y_uploader_seguro_incluyen_nuevo_servicio(self):
        row = dict(self.local.execute('SELECT * FROM ORDENES_TRABAJO_LOCAL').fetchone())
        values = dict(zip(uploader.WORK_ORDER_COLUMNS, uploader.build_work_order_values(row)))
        self.assertEqual(values['LIMPIEZA_PLATO'], 1)
        with patch.object(uploader, 'connect_mariadb', self.connect):
            result = uploader.upload_pending_plate_cleanings(self.path, log=lambda _: None)
        self.assertEqual(result.uploaded, 1)

    def test_esquema_idempotente_no_pierde_registros(self):
        plate.ensure_schema(self.local)
        uploader.ensure_work_order_schema(self.local)
        self.assertEqual(self.local.execute(f'SELECT COUNT(*) FROM {plate.TABLE}').fetchone()[0], 1)


if __name__ == '__main__': unittest.main()
