import os
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import json
from pathlib import Path

from tablet_uploader import (
    Device,
    INSERT_COLUMNS,
    MEASUREMENT_COLUMNS,
    UploadSummary,
    build_insert_values,
    ensure_local_replacement_table,
    fetch_pending_replacements,
    fetch_pending_measurements,
    upload_pending,
    upload_pending_work,
    apply_replacement_row,
    tablet_connection_status,
    update_shared_prefs_xml,
    mark_local_result,
    mark_replacement_operation_result,
    TEMPERATURE_COLUMNS,
    TEMPERATURE_INSERT_COLUMNS,
    build_temperature_insert_values,
    ensure_local_temperature_tables,
    fetch_pending_temperatures,
    mark_temperature_result,
    parse_measurement_datetime,
    perform_usb_upload_for_device,
    sync_latest_temperatures_from_mariadb,
    upload_temperature_rows,
    ALIGNMENT_COLUMNS,
    ALIGNMENT_INSERT_COLUMNS,
    build_alignment_insert_values,
    ensure_alignment_schema,
    fetch_pending_alignments,
    mark_alignment_result,
    sync_alignment_history_from_mariadb,
    upload_alignment_rows,
    upload_pending_alignments,
    pending_rows_for_display,
    COUPLING_INSERT_COLUMNS,
    build_coupling_insert_values,
    ensure_coupling_schema,
    fetch_pending_coupling_changes,
    mark_coupling_result,
    WORK_ORDER_COLUMNS,
    build_work_order_values,
    ensure_work_order_schema,
    fetch_pending_work_orders,
    remap_local_odt,
    upload_pending_work_orders,
    apply_orden_reparacion,
    ensure_ordenes_reparacion_schema,
    fetch_pending_ordenes_reparacion,
    mark_orden_reparacion_result,
    ADMIN_LOG_INSERT_COLUMNS,
    cargar_env_local,
    build_admin_event_insert_values,
    ensure_admin_log_schema,
    fetch_pending_admin_events,
    mark_admin_event_result,
    upload_pending_admin_events,
    ensure_checklist_compresor_schema,
    sync_compressor_checklists_from_mariadb,
    sync_lubrication_history_from_mariadb,
    sync_purge_deleted_from_mariadb,
    BELT_INSERT_COLUMNS,
    build_belt_insert_values,
    ensure_belt_schema,
    fetch_pending_belt_adjustments,
    mark_belt_result,
    upload_pending_belt_adjustments,
)
from equipment_report import _clave_historial, _rows as report_rows, build_equipment_report_pdf


class FakeMariaCursor:
    """Cursor de MariaDB falso, pero respaldado por una SQLite de verdad.

    Los cursores de mentira que solo guardan el SQL sirven para comprobar que
    una sentencia se emitio; no sirven para comprobar que una fila SIGUE
    EXISTIENDO despues del reemplazo, que es justo la regresion que importa
    del modelo por pieza fisica. Por eso aqui las sentencias se ejecutan.

    Traducciones minimas MariaDB -> SQLite:
      - marcador de parametro %s -> ?
      - FOR UPDATE no existe en SQLite y se descarta (no hay concurrencia)
      - INFORMATION_SCHEMA.COLUMNS se responde con PRAGMA table_info
    """

    def __init__(self, conn):
        self._conn = conn
        self._cursor = conn.cursor()
        self._canned = None
        self.calls = []

    def execute(self, sql, params=None):
        compact = " ".join(sql.split())
        self.calls.append((compact, params))
        if "INFORMATION_SCHEMA.COLUMNS" in compact:
            table, column = params
            names = {
                row[1].upper()
                for row in self._conn.execute(f'PRAGMA table_info("{table}")')
            }
            self._canned = [{"COLUMN_NAME": column}] if column.upper() in names else []
            return
        self._canned = None
        self._cursor.execute(
            compact.replace(" FOR UPDATE", "").replace("%s", "?"),
            tuple(params or ()),
        )

    def fetchone(self):
        if self._canned is not None:
            return self._canned[0] if self._canned else None
        row = self._cursor.fetchone()
        # apply_replacement_row usa row.get(...): hace falta un dict, no un Row.
        return dict(row) if row is not None else None

    def fetchall(self):
        if self._canned is not None:
            return list(self._canned)
        return [dict(row) for row in self._cursor.fetchall()]

    def sql_texts(self):
        return [sql for sql, _ in self.calls]


class TabletUploaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp.name) / "scv_ptbg.db"
        self.conn = sqlite3.connect(self.db_path)
        cols = ", ".join(f"{col} REAL" for col in MEASUREMENT_COLUMNS)
        self.conn.execute(
            f"""
            CREATE TABLE MEDICIONES_LOCAL (
              uuid TEXT PRIMARY KEY,
              localizacion INTEGER,
              sistema TEXT,
              fecha TEXT,
              hora TEXT,
              {cols},
              RMS REAL,
              observaciones TEXT,
              sincronizado INTEGER DEFAULT 0,
              error_sync TEXT,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        self.conn.execute(
            """
            INSERT INTO MEDICIONES_LOCAL
            (uuid, localizacion, sistema, fecha, hora, H1, V1, A1, RMS, observaciones, sincronizado)
            VALUES ('u-1', 13, 'TURBINA BG-2', '2026-07-06', '09:00:00', 2.0, 3.0, 4.0, 3.1, 'prueba', 0)
            """
        )
        self.conn.execute(
            """
            INSERT INTO MEDICIONES_LOCAL
            (uuid, localizacion, sistema, fecha, hora, H1, RMS, sincronizado)
            VALUES ('u-2', 4, 'TURBINA BG-1', '2026-07-06', '09:05:00', 1.0, 1.0, 1)
            """
        )
        self.conn.commit()
        ensure_local_replacement_table(self.conn)
        self.conn.execute(
            """
            INSERT INTO REEMPLAZOS_LOCAL
              (uuid, operation_uuid, localizacion, code_conjunto, equipo,
               marca, modelo, serial, fecha, hora, sincronizado)
            VALUES
              ('r-1', 'op-1', 13, 2, 1, 'WEG', 'W22', 'M-NEW',
               '2026-07-21', '13:00:00', 0),
              ('r-2', 'op-1', 13, 2, 3, 'SEW', 'R97', 'C-NEW',
               '2026-07-21', '13:00:00', 0),
              ('r-3', 'op-2', 4, 1, 4, 'HOWDEN', 'FAN', 'F-OLD',
               '2026-07-20', '12:00:00', 1)
            """
        )
        self.conn.commit()

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_coupling_change_local_usb_flow(self):
        ensure_coupling_schema(self.conn)
        self.conn.execute(
            """
            INSERT INTO CAMBIOS_COUPLING_LOCAL
            (uuid, localizacion, sistema, fecha, hora, observaciones,
             responsable, cargo, marca, modelo, serial, odt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "coupling-1", 2, "SISTEMA", "2026-08-03", "08:45:00",
                "Cambio confirmado", "OPERADOR", "MECANICO",
                "MARCA", "MODELO", "SERIAL", 1122,
            ),
        )
        self.conn.commit()

        rows = fetch_pending_coupling_changes(self.db_path)
        self.assertEqual(len(rows), 1)
        values = build_coupling_insert_values(rows[0])
        self.assertEqual(len(values), len(COUPLING_INSERT_COLUMNS))
        # UUID va primero: identifica el cambio para que un reintento tras un
        # corte de USB no lo inserte dos veces en MOT_CPLG_REG.
        self.assertEqual(COUPLING_INSERT_COLUMNS[0], "UUID")
        self.assertEqual(values[0], "coupling-1")
        self.assertEqual(values[COUPLING_INSERT_COLUMNS.index("LOCALIZACION")], 2)
        self.assertEqual(values[4], 2)
        # Por nombre y no por posicion: al final de la tupla se agregaron
        # COUPLING, INSERTO y MODELO_CPLG, y values[-1] dejo de ser la ODT.
        self.assertEqual(values[COUPLING_INSERT_COLUMNS.index("ODT")], 1122)
        # Coupling e inserto viajan como banderas independientes: puede
        # cambiarse uno, el otro o los dos.
        for columna in ("COUPLING", "INSERTO"):
            self.assertIn(
                values[COUPLING_INSERT_COLUMNS.index(columna)],
                (0, 1),
                f"{columna} debe ser 0 o 1",
            )

        mark_coupling_result(self.db_path, "coupling-1", synced=True)
        self.assertEqual(fetch_pending_coupling_changes(self.db_path), [])

    def test_env_local_llena_huecos_sin_pisar_el_entorno(self):
        """El .env es lo que permite conectar en una laptop recien preparada.

        Sin esto la clave quedaba vacia y el programa fallaba al conectar sin
        decir por que. Y lo que ya venga en el entorno real tiene que mandar:
        el .env solo rellena lo que falta.
        """
        env = Path(self.tmp.name) / ".env"
        env.write_text(
            chr(10).join(
                [
                    "# comentario que se ignora",
                    "",
                    "SCV_PRUEBA_HOST=10.0.0.9",
                    'SCV_PRUEBA_USER="con-comillas"',
                    "export SCV_PRUEBA_NAME=con-export",
                    "SCV_PRUEBA_VACIA=",
                    "linea sin igual",
                    "SCV_PRUEBA_YA_PUESTA=del-archivo",
                ]
            ),
            encoding="utf-8",
        )
        os.environ["SCV_PRUEBA_YA_PUESTA"] = "del-entorno"
        for clave in ("SCV_PRUEBA_HOST", "SCV_PRUEBA_USER",
                      "SCV_PRUEBA_NAME", "SCV_PRUEBA_VACIA"):
            os.environ.pop(clave, None)
        self.addCleanup(
            lambda: [
                os.environ.pop(c, None)
                for c in (
                    "SCV_PRUEBA_HOST", "SCV_PRUEBA_USER", "SCV_PRUEBA_NAME",
                    "SCV_PRUEBA_VACIA", "SCV_PRUEBA_YA_PUESTA",
                )
            ]
        )

        cargadas = cargar_env_local(env)

        self.assertEqual(os.environ["SCV_PRUEBA_HOST"], "10.0.0.9")
        # Las comillas y el "export" son como la gente escribe estos archivos.
        self.assertEqual(os.environ["SCV_PRUEBA_USER"], "con-comillas")
        self.assertEqual(os.environ["SCV_PRUEBA_NAME"], "con-export")
        # Una casilla sin llenar no pisa nada ni cuenta como cargada.
        self.assertNotIn("SCV_PRUEBA_VACIA", os.environ)
        self.assertNotIn("SCV_PRUEBA_VACIA", cargadas)
        # El entorno real manda sobre el archivo.
        self.assertEqual(os.environ["SCV_PRUEBA_YA_PUESTA"], "del-entorno")
        self.assertNotIn("SCV_PRUEBA_YA_PUESTA", cargadas)
        # Nunca devuelve valores, solo nombres: esto se escribe en el log.
        self.assertEqual(sorted(cargadas), [
            "SCV_PRUEBA_HOST", "SCV_PRUEBA_NAME", "SCV_PRUEBA_USER",
        ])

    def test_env_local_ausente_no_rompe_el_arranque(self):
        self.assertEqual(
            cargar_env_local(Path(self.tmp.name) / "no-existe.env"), []
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_descarga_trae_historial_por_compresor(self, connect):
        """El "ultima vez" del control de mantenimiento sobrevive a una tablet
        limpia porque la descarga USB lo trae de MOT_COMP_CHKL."""
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute(
            """
            CREATE TABLE MOT_COMP_CHKL (
              ID INTEGER PRIMARY KEY AUTOINCREMENT, UUID TEXT,
              FECHA TEXT, HORA TEXT, EQUIPO TEXT, LOCALIZACION INTEGER,
              SUBSISTEMA TEXT, TAG TEXT, H_INICIO TEXT, H_FIN TEXT,
              N_HORAS INTEGER, N_ARRANQUES INTEGER,
              ACT1 INTEGER, ACT1_OBS TEXT, ACT2 INTEGER, ACT2_OBS TEXT,
              ACT3 INTEGER, ACT3_OBS TEXT, ACT4 INTEGER, ACT4_OBS TEXT,
              ACT5 INTEGER, ACT5_OBS TEXT, ACT6 INTEGER, ACT6_OBS TEXT,
              ACT7 INTEGER, ACT7_OBS TEXT, ACT8 INTEGER, ACT8_OBS TEXT,
              ACT9 INTEGER, ACT9_OBS TEXT, ACT10 INTEGER, ACT10_OBS TEXT,
              ACT11 INTEGER, ACT11_OBS TEXT,
              MTTO_LUB_UF TEXT, MTTO_LUB_UH TEXT, MTTO_LUB_OBS TEXT,
              MTTO_INH_UF TEXT, MTTO_INH_UH TEXT, MTTO_INH_OBS TEXT,
              MTTO_AIR_UF TEXT, MTTO_AIR_UH TEXT, MTTO_AIR_OBS TEXT,
              MTTO_ACE_UF TEXT, MTTO_ACE_UH TEXT, MTTO_ACE_OBS TEXT,
              USUARIO TEXT, CARGO TEXT, ODT INTEGER
            )
            """
        )
        # Tambien debe bajar el anterior: el ultimo puede estar sin tareas.
        base = "(UUID, FECHA, HORA, LOCALIZACION, EQUIPO, MTTO_LUB_UF, MTTO_LUB_UH)"
        maria.execute(
            f"INSERT INTO MOT_COMP_CHKL {base} VALUES "
            "('chk-viejo','2026-07-01','08:00:00',57,'COMPRESOR A','01/06/2026','3000')"
        )
        maria.execute(
            f"INSERT INTO MOT_COMP_CHKL {base} VALUES "
            "('chk-nuevo','2026-08-20','09:00:00',57,'COMPRESOR A','15/08/2026','3450')"
        )
        maria.execute(
            f"INSERT INTO MOT_COMP_CHKL {base} VALUES "
            "('chk-b','2026-08-10','10:00:00',58,'COMPRESOR B','','')"
        )

        # En la tablet ya hay un check list pendiente de subir: no se toca.
        ensure_checklist_compresor_schema(self.conn)
        self.conn.execute(
            "INSERT INTO CHECKLIST_COMPRESOR_LOCAL "
            "(uuid, localizacion, fecha, hora, sincronizado) "
            "VALUES ('chk-local', 57, '2026-09-01', '11:00:00', 0)"
        )
        self.conn.commit()

        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
            def cursor(self): return self.cur
            def close(self): pass

        connect.return_value = Db(maria)
        nuevos = sync_compressor_checklists_from_mariadb(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual(nuevos, 3)

        filas = {
            fila[0]: fila
            for fila in self.conn.execute(
                "SELECT uuid, sincronizado, mtto_lub_uf, mtto_lub_uh "
                "FROM CHECKLIST_COMPRESOR_LOCAL"
            )
        }
        # Bajo el historial de LOC-57 y el de LOC-58,
        # marcados como ya sincronizados para que no intenten subirse.
        self.assertIn("chk-nuevo", filas)
        self.assertIn("chk-viejo", filas)
        self.assertEqual(filas["chk-nuevo"][1], 1)
        self.assertEqual(filas["chk-nuevo"][2], "15/08/2026")
        self.assertEqual(filas["chk-nuevo"][3], "3450")
        self.assertIn("chk-b", filas)
        # El pendiente local sigue pendiente.
        self.assertEqual(filas["chk-local"][1], 0)

        # Una segunda descarga no duplica: sigue habiendo un solo chk-nuevo.
        connect.return_value = Db(maria)
        sync_compressor_checklists_from_mariadb(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT COUNT(*) FROM CHECKLIST_COMPRESOR_LOCAL "
                "WHERE uuid='chk-nuevo'"
            ).fetchone()[0],
            1,
        )

        # Y si en la planta CORRIGEN una fecha mal escrita, la tablet se
        # entera en la siguiente descarga. Antes se quedaba con el dato viejo
        # para siempre porque la insercion ignoraba los UUID ya conocidos.
        maria.execute(
            "UPDATE MOT_COMP_CHKL SET MTTO_LUB_UF='02/06/2026' "
            "WHERE UUID='chk-nuevo'"
        )
        maria.commit()
        connect.return_value = Db(maria)
        sync_compressor_checklists_from_mariadb(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT mtto_lub_uf FROM CHECKLIST_COMPRESOR_LOCAL "
                "WHERE uuid='chk-nuevo'"
            ).fetchone()[0],
            '02/06/2026',
        )
        # El pendiente local sigue intacto: no existe en la planta todavia.
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado FROM CHECKLIST_COMPRESOR_LOCAL "
                "WHERE uuid='chk-local'"
            ).fetchone()[0],
            0,
        )

        # Si la siguiente inspeccion no hizo mantenimiento, sus campos
        # deben seguir vacios en SQLite; el antecedente se consulta al mostrar.
        maria.execute(
            f"INSERT INTO MOT_COMP_CHKL {base} VALUES "
            "('chk-sin-mtto','2026-09-07','08:00:00',57,'COMPRESOR A','','')"
        )
        maria.commit()
        connect.return_value = Db(maria)
        sync_compressor_checklists_from_mariadb(self.db_path, log=lambda _: None)
        self.assertEqual(self.conn.execute(
            "SELECT COALESCE(mtto_lub_uf, '') FROM CHECKLIST_COMPRESOR_LOCAL "
            "WHERE uuid='chk-sin-mtto'"
        ).fetchone()[0], '')
        from compressor_checklist_report import checklist_con_mantenimientos_anteriores
        crudas = [dict(zip([c[0] for c in cursor.description], r))
                  for cursor in [self.conn.execute("SELECT * FROM CHECKLIST_COMPRESOR_LOCAL")]
                  for r in cursor.fetchall()]
        actual = next(r for r in crudas if r['uuid'] == 'chk-sin-mtto')
        resuelto = checklist_con_mantenimientos_anteriores(actual, crudas)
        self.assertEqual(resuelto['MTTO_LUB_UF'], '02/06/2026')
        self.assertEqual(resuelto['MTTO_LUB_UH'], '3450')
        maria.close()

    def test_reporte_ordena_y_depura_igual_que_la_tablet(self):
        """El criterio unico de "los ultimos N": mismas reglas que
        lib/models/historial_servicio.dart. Datos calcados de la tablet real,
        donde el orden alfabetico ponia el 30/01 encima del 14 de julio."""
        self.assertEqual(
            _clave_historial({"fecha": "30/01/2026", "hora": "15:00"}),
            "2026-01-30T15:00:00",
        )
        self.assertEqual(
            _clave_historial({"fecha": "2026-08-25 00:00:00", "hora": "10:07:43"}),
            "2026-08-25T10:07:43",
        )
        self.assertEqual(
            _clave_historial({"fecha": "5/8/2026", "hora": "9:30"}),
            "2026-08-05T09:30:00",
        )
        # El iso normalizado manda; el del epoch (fecha ilegible) no.
        self.assertEqual(
            _clave_historial({"fecha": "x", "hora": "",
                              "fecha_hora_iso": "2026-06-16T12:38:26"}),
            "2026-06-16T12:38:26",
        )
        self.assertEqual(
            _clave_historial({"fecha": "x", "hora": "",
                              "fecha_hora_iso": "1970-01-01T00:00:00"}),
            "0000-01-01T00:00:00",
        )

        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        db.execute(
            "CREATE TABLE MEDICIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "fecha TEXT, hora TEXT, odt INTEGER, observaciones TEXT)"
        )
        db.execute(
            "CREATE TABLE MEDICIONES_REMOTAS (remote_key TEXT, localizacion INTEGER, "
            "fecha TEXT, hora TEXT, fecha_hora_iso TEXT, equipo TEXT)"
        )
        # La medicion sincronizada vive dos veces; la remota trae el nombre
        # del equipo que la local no tiene.
        db.execute(
            "INSERT INTO MEDICIONES_LOCAL VALUES "
            "('u-1', 39, '2026-08-25', '08:15:07', 4521, 'RUIDO LEVE')"
        )
        db.execute(
            "INSERT INTO MEDICIONES_REMOTAS VALUES "
            "('ID:88', 39, '25/08/2026', '08:15:07', '2026-08-25T08:15:07', 'BOMBA 12FO')"
        )
        # Historial viejo del sistema anterior, solo remoto, en formato d/m.
        db.execute(
            "INSERT INTO MEDICIONES_REMOTAS VALUES "
            "('ID:12', 39, '30/01/2026', '15:00', '2026-01-30T15:00:00', 'BOMBA 12FO')"
        )
        db.execute(
            "INSERT INTO MEDICIONES_REMOTAS VALUES "
            "('ID:40', 39, '27/03/2026', '08:00', '2026-03-27T08:00:00', 'BOMBA 12FO')"
        )
        db.commit()

        rows = report_rows(db, ("MEDICIONES_LOCAL", "MEDICIONES_REMOTAS"), 39)
        self.assertEqual(len(rows), 3)
        # Orden real, no alfabetico: agosto > marzo > enero.
        self.assertEqual(
            [r.get("uuid") or r.get("remote_key") for r in rows],
            ["u-1", "ID:40", "ID:12"],
        )
        # La local mando en el duplicado, pero se completo con lo remoto.
        self.assertEqual(rows[0]["observaciones"], "RUIDO LEVE")
        self.assertEqual(rows[0]["equipo"], "BOMBA 12FO")
        self.assertEqual(rows[0]["odt"], 4521)

    @patch("tablet_uploader.connect_mariadb")
    def test_descarga_trae_historial_de_lubricacion(self, connect):
        """Era el unico servicio sin bajada por USB: la tablet solo-USB
        mostraba el historial de lubricacion vacio aunque MariaDB lo tuviera."""
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute(
            "CREATE TABLE MOT_LUB_REG (ID INTEGER PRIMARY KEY, UUID TEXT, "
            "FECHA TEXT, HORA TEXT, SISTEMA TEXT, LOCALIZACION INTEGER, "
            "L1 REAL, L2 REAL, L3 REAL, L4 REAL, L5 REAL, L6 REAL, L7 REAL, "
            "L8 REAL, L9 REAL, OBSERVACIONES TEXT, USUARIO TEXT, CARGO TEXT, "
            "MARCA TEXT, MODELO TEXT, SERIAL TEXT, ODT INTEGER)"
        )
        maria.execute(
            "INSERT INTO MOT_LUB_REG (UUID, FECHA, HORA, SISTEMA, LOCALIZACION, L1) "
            "VALUES ('lub-1', '2026-08-03', '09:10:00', 'AGUA POTABLE', 2, 12.5)"
        )
        maria.commit()

        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
            def cursor(self): return self.cur
            def close(self): pass

        connect.return_value = Db(maria)
        # El ORDER BY con STR_TO_DATE es de MariaDB; el cursor falso corre
        # sobre SQLite, asi que se ejecuta la consulta simplificada.
        import tablet_uploader as tu
        original = CursorConWith.execute
        def execute(self, sql, params=None):
            if "STR_TO_DATE" in sql:
                sql = "SELECT * FROM MOT_LUB_REG ORDER BY ID DESC LIMIT 500"
            return original(self, sql, params)
        CursorConWith.execute = execute
        try:
            n = sync_lubrication_history_from_mariadb(
                self.db_path, log=lambda _: None,
            )
        finally:
            CursorConWith.execute = original
        self.assertEqual(n, 1)

        fila = self.conn.execute(
            "SELECT remote_key, localizacion, fecha, hora, fecha_hora_iso, L1 "
            "FROM LUBRICACIONES_REMOTAS"
        ).fetchone()
        self.assertEqual(fila[0], "ID:1")
        self.assertEqual(fila[1], 2)
        self.assertEqual(fila[4], "2026-08-03T09:10:00")
        self.assertEqual(fila[5], 12.5)

    def test_reporte_vibracion_trae_grafica_por_punto(self):
        """El PDF lleva una grafica por punto (H/V/A en el tiempo), no una
        sola con las 18 lineas cruzadas."""
        db = sqlite3.connect(self.db_path)
        db.execute(
            "CREATE TABLE EQUIPOS (ID INTEGER, CODE_SYS INTEGER, EQUIPO TEXT, "
            "LOCALIZACION INTEGER, QR_CODE TEXT, PUNTOS INTEGER, PT_EQ INTEGER, "
            "SISTEMA TEXT, SUBSISTEMA TEXT, SCADA TEXT)"
        )
        db.execute(
            "INSERT INTO EQUIPOS VALUES (39, 3, 'BOMBA FUEL OIL', 39, "
            "'12-FO-CP-004C', 4, 4, 'FUEL OIL', NULL, NULL)"
        )
        db.execute("ALTER TABLE MEDICIONES_LOCAL ADD COLUMN odt INTEGER")
        db.execute(
            "INSERT INTO MEDICIONES_LOCAL (uuid, localizacion, fecha, hora, H1, V1, A1) "
            "VALUES ('g-1', 39, '2026-08-21', '10:07:43', 2.1, 1.4, 0.9)"
        )
        db.execute(
            "INSERT INTO MEDICIONES_LOCAL (uuid, localizacion, fecha, hora, H1, V1, A1) "
            "VALUES ('g-2', 39, '2026-07-14', '10:07:43', 1.8, 1.2, 0.8)"
        )
        db.commit()
        db.close()

        salida = Path(self.tmp.name) / "reportes"
        pdf = build_equipment_report_pdf(self.db_path, 39, "vibration", salida, 5)
        self.assertTrue(pdf.exists())
        self.assertGreater(pdf.stat().st_size, 5000)

    @patch("tablet_uploader.connect_mariadb")
    def test_purga_borra_lo_eliminado_pero_jamas_lo_pendiente(self, connect):
        """Lo que se borro a mano en MariaDB desaparece de la tablet en la
        descarga; lo capturado en campo sin subir no se toca nunca."""
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute("CREATE TABLE MOT_EQUIPO (LOCALIZACION INTEGER)")
        maria.execute("INSERT INTO MOT_EQUIPO VALUES (48)")
        # 57 fue borrado de la planta a proposito.
        for tabla in ("MOT_VIBR_MUES", "MOT_TEMP_MUES", "MOT_ALN_REG",
                      "MOT_LUB_REG", "MOT_CPLG_REG", "MOT_COMP_CHKL",
                      "MOT_BLKS_CHKL"):
            maria.execute(f"CREATE TABLE {tabla} (UUID TEXT, SERIAL TEXT)")
        maria.execute("INSERT INTO MOT_VIBR_MUES (UUID) VALUES ('u-viva')")
        for tabla in ("MOT_DATA", "MOT_BOMB_DATA", "MOT_CAJA_DATA",
                      "MOT_VENT_DATA", "MOT_LOG_RPL"):
            maria.execute(f"CREATE TABLE {tabla} (SERIAL TEXT)")
        maria.execute("INSERT INTO MOT_DATA VALUES ('S-VIVA')")

        # La tablet: un equipo vivo, uno borrado, y mediciones en tres estados.
        self.conn.execute(
            "CREATE TABLE EQUIPOS (ID INTEGER, LOCALIZACION INTEGER, EQUIPO TEXT)"
        )
        self.conn.execute("CREATE TABLE EQUIPO_INFO (localizacion INTEGER)")
        self.conn.execute(
            "CREATE TABLE EQUIPOS_NUEVOS_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        self.conn.execute("INSERT INTO EQUIPOS VALUES (1, 48, 'VIVO')")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (2, 57, 'BORRADO EN PLANTA')")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (3, 90, 'ALTA DE CAMPO')")
        self.conn.execute("INSERT INTO EQUIPO_INFO VALUES (57)")
        # El alta de campo pendiente protege su equipo aunque no este en planta.
        self.conn.execute(
            "INSERT INTO EQUIPOS_NUEVOS_LOCAL VALUES ('nuevo-1', 90, 0)"
        )
        self.conn.execute(
            "CREATE TABLE CATALOGO_COMPONENTES (tipo INTEGER, serial TEXT)"
        )
        self.conn.execute("INSERT INTO CATALOGO_COMPONENTES VALUES (1, 'S-VIVA')")
        self.conn.execute("INSERT INTO CATALOGO_COMPONENTES VALUES (1, 'S-BORRADA')")
        # Mediciones: viva y sincronizada, borrada y sincronizada, pendiente.
        self.conn.execute(
            "INSERT INTO MEDICIONES_LOCAL (uuid, localizacion, fecha, hora, sincronizado) "
            "VALUES ('u-viva', 48, '2026-08-25', '08:00:00', 1)"
        )
        self.conn.execute(
            "INSERT INTO MEDICIONES_LOCAL (uuid, localizacion, fecha, hora, sincronizado) "
            "VALUES ('u-borrada', 48, '2026-08-20', '08:00:00', 1)"
        )
        self.conn.execute(
            "INSERT INTO MEDICIONES_LOCAL (uuid, localizacion, fecha, hora, sincronizado) "
            "VALUES ('u-pendiente', 48, '2026-09-01', '08:00:00', 0)"
        )
        self.conn.commit()

        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
            def cursor(self): return self.cur
            def close(self): pass

        connect.return_value = Db(maria)
        sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        equipos = {r[0] for r in self.conn.execute("SELECT LOCALIZACION FROM EQUIPOS")}
        self.assertEqual(equipos, {48, 90})
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM EQUIPO_INFO").fetchone()[0], 0
        )
        mediciones = {
            r[0] for r in self.conn.execute("SELECT uuid FROM MEDICIONES_LOCAL")
        }
        # u-1 es la semilla pendiente del setUp: pendiente = intocable.
        # u-2 (semilla ya sincronizada) no esta en MariaDB: purgada, correcto.
        self.assertEqual(mediciones, {"u-viva", "u-pendiente", "u-1"})
        seriales = {
            r[0] for r in self.conn.execute("SELECT serial FROM CATALOGO_COMPONENTES")
        }
        self.assertEqual(seriales, {"S-VIVA"})

    @patch("tablet_uploader.connect_mariadb")
    def test_purga_se_cancela_si_el_maestro_llega_vacio(self, connect):
        """Un MOT_EQUIPO vacio huele a fallo de lectura, no a planta sin
        equipos: no se borra nada."""
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute("CREATE TABLE MOT_EQUIPO (LOCALIZACION INTEGER)")
        for tabla in ("MOT_VIBR_MUES", "MOT_TEMP_MUES", "MOT_ALN_REG",
                      "MOT_LUB_REG", "MOT_CPLG_REG", "MOT_COMP_CHKL",
                      "MOT_BLKS_CHKL"):
            maria.execute(f"CREATE TABLE {tabla} (UUID TEXT)")
        for tabla in ("MOT_DATA", "MOT_BOMB_DATA", "MOT_CAJA_DATA",
                      "MOT_VENT_DATA", "MOT_LOG_RPL"):
            maria.execute(f"CREATE TABLE {tabla} (SERIAL TEXT)")

        self.conn.execute("CREATE TABLE EQUIPOS (LOCALIZACION INTEGER)")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (48)")
        self.conn.commit()

        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
            def cursor(self): return self.cur
            def close(self): pass

        connect.return_value = Db(maria)
        borradas = sync_purge_deleted_from_mariadb(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual(borradas, 0)
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM EQUIPOS").fetchone()[0], 1
        )

    def test_ajuste_correa_viaje_completo_a_mariadb(self):
        """El ajuste de correa de un ventilador sube a MOT_AJC_REG."""
        ensure_belt_schema(self.conn)
        self.conn.execute(
            """
            INSERT INTO AJUSTES_CORREA_LOCAL
            (uuid, localizacion, sistema, fecha, hora, ajustada, tension,
             observaciones, responsable, cargo, marca, modelo, serial, odt)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            ("correa-1", 15, "TURBINA BG-1", "2026-09-02", "08:30:00", 1,
             42.5, "CORREA FLOJA", "ALEXI AVILA", "SUP.MECANICO",
             "WEG", "QX-11", "C0049856", 4521),
        )
        self.conn.commit()

        rows = fetch_pending_belt_adjustments(self.db_path)
        self.assertEqual(len(rows), 1)
        valores = build_belt_insert_values(rows[0])
        self.assertEqual(len(valores), len(BELT_INSERT_COLUMNS))
        por_nombre = dict(zip(BELT_INSERT_COLUMNS, valores))
        self.assertEqual(BELT_INSERT_COLUMNS[0], "UUID")
        self.assertEqual(por_nombre["UUID"], "correa-1")
        self.assertEqual(por_nombre["LOCALIZACION"], 15)
        # La tension viaja como numero, no como texto: la columna es DECIMAL.
        self.assertEqual(por_nombre["TENSION"], 42.5)
        self.assertIsInstance(por_nombre["TENSION"], float)
        self.assertEqual(por_nombre["USUARIO"], "ALEXI AVILA")
        self.assertEqual(por_nombre["ODT"], 4521)
        # MOT_AJC_REG no tiene columna para el "se ajusto o no": se dice en la
        # observacion para que el registro no quede mudo.
        self.assertIn("CORREA AJUSTADA", por_nombre["OBSERVACIONES"])
        self.assertIn("CORREA FLOJA", por_nombre["OBSERVACIONES"])

        mark_belt_result(self.db_path, "correa-1", synced=True)
        self.assertEqual(fetch_pending_belt_adjustments(self.db_path), [])

    def test_ajuste_correa_sin_ajustar_lo_dice_en_la_observacion(self):
        """Un NO tambien es un registro: se reviso y no hizo falta tocarla."""
        ensure_belt_schema(self.conn)
        self.conn.execute(
            "INSERT INTO AJUSTES_CORREA_LOCAL "
            "(uuid, localizacion, fecha, hora, ajustada) VALUES (?,?,?,?,?)",
            ("correa-2", 17, "2026-09-02", "09:00:00", 0),
        )
        self.conn.commit()
        fila = fetch_pending_belt_adjustments(self.db_path)[0]
        self.assertIn("SIN AJUSTE", fila["OBSERVACIONES"])
        self.assertIsNone(fila["TENSION"])

    @patch("tablet_uploader.connect_mariadb")
    def test_ajuste_correa_no_se_duplica_al_reintentar(self, connect):
        ensure_belt_schema(self.conn)
        self.conn.execute(
            "INSERT INTO AJUSTES_CORREA_LOCAL "
            "(uuid, localizacion, fecha, hora, ajustada, tension) "
            "VALUES (?,?,?,?,?,?)",
            ("correa-3", 15, "2026-09-02", "08:30:00", 1, 42.5),
        )
        self.conn.commit()

        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute(
            "CREATE TABLE MOT_AJC_REG (ID INTEGER PRIMARY KEY AUTOINCREMENT, "
            "UUID TEXT UNIQUE, FECHA TEXT, HORA TEXT, SISTEMA TEXT, "
            "LOCALIZACION INTEGER, TENSION REAL, OBSERVACIONES TEXT, "
            "USUARIO TEXT, CARGO TEXT, MARCA TEXT, MODELO TEXT, SERIAL TEXT, "
            "ODT INTEGER)"
        )

        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
                self._conn = conn
            def cursor(self): return self.cur
            def commit(self): self._conn.commit()
            def rollback(self): self._conn.rollback()
            def close(self): pass

        connect.return_value = Db(maria)
        primera = upload_pending_belt_adjustments(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual((primera.uploaded, primera.failed), (1, 0))
        guardado = maria.execute(
            "SELECT LOCALIZACION, TENSION FROM MOT_AJC_REG"
        ).fetchall()
        self.assertEqual(len(guardado), 1)
        self.assertEqual(guardado[0]["TENSION"], 42.5)

        # Corte de USB justo despues del INSERT: el reintento no duplica.
        mark_belt_result(self.db_path, "correa-3", synced=False, error="corte")
        connect.return_value = Db(maria)
        segunda = upload_pending_belt_adjustments(
            self.db_path, log=lambda _: None,
        )
        self.assertEqual((segunda.uploaded, segunda.skipped), (0, 1))
        self.assertEqual(
            maria.execute("SELECT COUNT(*) FROM MOT_AJC_REG").fetchone()[0], 1
        )

    def test_admin_event_local_usb_flow(self):
        """La bitacora del admin viaja como cualquier otro pendiente."""
        ensure_admin_log_schema(self.conn)
        self.conn.execute(
            """
            INSERT INTO EVENTOS_ADMIN
            (uuid, fecha, hora, usuario, cargo, accion, servicio,
             localizacion, uuid_medicion, detalle)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "evt-1", "2026-09-01", "10:15:00", "DANIEL BERRUETA", "ADMIN",
                "EDICION", "temperatura", 48, "uuid-t1",
                "T2: 88.0 -> 90.5",
            ),
        )
        self.conn.commit()

        rows = fetch_pending_admin_events(self.db_path)
        self.assertEqual(len(rows), 1)
        values = build_admin_event_insert_values(rows[0], "TABR70000000012091")
        self.assertEqual(len(values), len(ADMIN_LOG_INSERT_COLUMNS))
        # El UUID va primero: es lo que evita duplicar el evento si la subida
        # se corta a la mitad y se reintenta.
        self.assertEqual(ADMIN_LOG_INSERT_COLUMNS[0], "UUID")
        self.assertEqual(values[0], "evt-1")
        por_nombre = dict(zip(ADMIN_LOG_INSERT_COLUMNS, values))
        self.assertEqual(por_nombre["USUARIO"], "DANIEL BERRUETA")
        self.assertEqual(por_nombre["ACCION"], "EDICION")
        self.assertEqual(por_nombre["LOCALIZACION"], 48)
        self.assertEqual(por_nombre["UUID_MEDICION"], "uuid-t1")
        self.assertEqual(por_nombre["DETALLE"], "T2: 88.0 -> 90.5")
        # La tablet de origen se sella al subir, no la escribe la app.
        self.assertEqual(por_nombre["TABLET"], "TABR70000000012091")

        mark_admin_event_result(self.db_path, "evt-1", synced=True)
        self.assertEqual(fetch_pending_admin_events(self.db_path), [])

    def test_admin_log_schema_upgrades_first_version_table(self):
        """Una tablet con la primera version de EVENTOS_ADMIN no rompe la subida.

        Esa version no tenia columnas de sincronizacion, asi que la consulta de
        pendientes reventaria y frenaria el resto de los trabajos.
        """
        self.conn.execute(
            """
            CREATE TABLE EVENTOS_ADMIN (
              uuid TEXT PRIMARY KEY, fecha TEXT NOT NULL, hora TEXT NOT NULL,
              usuario TEXT NOT NULL, accion TEXT NOT NULL, servicio TEXT,
              localizacion INTEGER, uuid_medicion TEXT, detalle TEXT
            )
            """
        )
        self.conn.execute(
            """INSERT INTO EVENTOS_ADMIN
            (uuid, fecha, hora, usuario, accion) VALUES (?,?,?,?,?)""",
            ("evt-viejo", "2026-08-31", "09:00:00", "ADMIN", "FECHA MANUAL"),
        )
        self.conn.commit()

        rows = fetch_pending_admin_events(self.db_path)
        self.assertEqual([row["uuid"] for row in rows], ["evt-viejo"])

    @patch("tablet_uploader.connect_mariadb")
    def test_admin_event_upload_does_not_duplicate_on_retry(self, connect):
        ensure_admin_log_schema(self.conn)
        self.conn.execute(
            """INSERT INTO EVENTOS_ADMIN
            (uuid, fecha, hora, usuario, cargo, accion, servicio, localizacion)
            VALUES (?,?,?,?,?,?,?,?)""",
            ("evt-2", "2026-09-01", "11:00:00", "DANIEL BERRUETA", "ADMIN",
             "FECHA MANUAL", "lubricacion", 2),
        )
        self.conn.commit()

        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute(
            """
            CREATE TABLE MOT_LOG_ADM (
              ID INTEGER PRIMARY KEY AUTOINCREMENT, UUID TEXT UNIQUE,
              FECHA TEXT, HORA TEXT, USUARIO TEXT, CARGO TEXT, ACCION TEXT,
              SERVICIO TEXT, LOCALIZACION INTEGER, UUID_MEDICION TEXT,
              DETALLE TEXT, TABLET TEXT
            )
            """
        )

        # upload_pending_admin_events abre el cursor con `with`, como el
        # resto de las subidas; FakeMariaCursor no es context manager.
        class CursorConWith(FakeMariaCursor):
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self, conn):
                self.cur = CursorConWith(conn)
                self._conn = conn
            def cursor(self): return self.cur
            def commit(self): self._conn.commit()
            def rollback(self): self._conn.rollback()
            def close(self): pass

        connect.return_value = Db(maria)
        primera = upload_pending_admin_events(
            self.db_path, tablet="TAB-1", log=lambda _: None,
        )
        self.assertEqual((primera.uploaded, primera.failed), (1, 0))
        guardado = maria.execute(
            "SELECT USUARIO, ACCION, TABLET FROM MOT_LOG_ADM"
        ).fetchall()
        self.assertEqual(len(guardado), 1)
        self.assertEqual(guardado[0]["USUARIO"], "DANIEL BERRUETA")
        self.assertEqual(guardado[0]["TABLET"], "TAB-1")

        # Se vuelve a marcar pendiente, como si el USB se hubiera cortado
        # justo despues del INSERT: el reintento no debe duplicar la fila.
        mark_admin_event_result(self.db_path, "evt-2", synced=False, error="corte")
        connect.return_value = Db(maria)
        segunda = upload_pending_admin_events(
            self.db_path, tablet="TAB-1", log=lambda _: None,
        )
        self.assertEqual((segunda.uploaded, segunda.skipped), (0, 1))
        self.assertEqual(
            maria.execute("SELECT COUNT(*) FROM MOT_LOG_ADM").fetchone()[0], 1
        )
        self.assertEqual(fetch_pending_admin_events(self.db_path), [])

    def test_work_order_flags_and_odt_remap_are_shared_by_services(self):
        ensure_work_order_schema(self.conn)
        self.conn.execute("ALTER TABLE MEDICIONES_LOCAL ADD COLUMN odt INTEGER")
        self.conn.execute(
            """INSERT INTO ORDENES_TRABAJO_LOCAL
            (odt,fecha,hora,equipo,ubicacion,code_conjunto,vibracion,
             temperatura,alineacion,lubricacion,coupling_rpl,correa_ajt,reemplazo)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (1785747000, "2026-08-03", "09:00:00", "BOMBA", 13, 7,
             1, 1, 0, 1, 0, 0, 0),
        )
        self.conn.execute(
            "UPDATE MEDICIONES_LOCAL SET odt=? WHERE uuid='u-1'",
            (1785747000,),
        )
        self.conn.commit()

        rows = fetch_pending_work_orders(self.db_path)
        self.assertEqual(len(rows), 1)
        values = build_work_order_values(rows[0])
        self.assertEqual(len(values), len(WORK_ORDER_COLUMNS))
        self.assertEqual(values[6:13], (1, 1, 0, 1, 0, 0, 0))

        remap_local_odt(self.db_path, 1785747000, 1785747001)
        order = self.conn.execute(
            "SELECT odt FROM ORDENES_TRABAJO_LOCAL"
        ).fetchone()
        measurement = self.conn.execute(
            "SELECT odt FROM MEDICIONES_LOCAL WHERE uuid='u-1'"
        ).fetchone()
        self.assertEqual(order[0], 1785747001)
        self.assertEqual(measurement[0], 1785747001)

    @patch("tablet_uploader.connect_mariadb")
    def test_work_order_upload_inserts_all_service_flags(self, connect):
        ensure_work_order_schema(self.conn)
        self.conn.execute(
            """INSERT INTO ORDENES_TRABAJO_LOCAL
            (odt,fecha,hora,equipo,ubicacion,code_conjunto,vibracion,
             temperatura,alineacion,lubricacion,coupling_rpl,correa_ajt,reemplazo)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (1785747100, "2026-08-03", "09:15:00", "BOMBA", 13, 7,
             1, 1, 1, 1, 1, 0, 1),
        )
        self.conn.commit()

        class Cursor:
            def __init__(self):
                self.calls = []
            def execute(self, sql, params=None):
                self.calls.append((" ".join(sql.split()), params))
            def fetchone(self):
                return None
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self):
                self.cur = Cursor()
                self.commits = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): pass
            def close(self): pass

        db = Db()
        connect.return_value = db
        summary = upload_pending_work_orders(self.db_path, log=lambda _: None)

        self.assertEqual((summary.uploaded, summary.failed), (1, 0))
        insert = next(call for call in db.cur.calls if "INSERT INTO MOT_INDICE" in call[0])
        self.assertEqual(insert[1][6:13], (1, 1, 1, 1, 1, 0, 1))
        self.assertEqual(db.commits, 1)
        synced = self.conn.execute(
            "SELECT sincronizado FROM ORDENES_TRABAJO_LOCAL WHERE odt=1785747100"
        ).fetchone()
        self.assertEqual(synced, (1,))

    def test_fetch_pending_measurements_returns_only_unsynced_rows(self):
        rows = fetch_pending_measurements(self.db_path)

        self.assertEqual([row["uuid"] for row in rows], ["u-1"])
        self.assertEqual(rows[0]["OBSERVACIONES"], "prueba")
        self.assertEqual(rows[0]["RMS"], 3.1)

    @patch("tablet_uploader.upload_measurement_rows")
    def test_upload_pending_never_sends_synced_local_history(self, upload_rows):
        upload_rows.return_value = UploadSummary(total=1, uploaded=1)

        upload_pending(self.db_path)

        sent_rows = upload_rows.call_args.args[1]
        self.assertEqual([row["uuid"] for row in sent_rows], ["u-1"])

    @patch("tablet_uploader.upload_pending_alignments")
    @patch("tablet_uploader.upload_pending_temperatures")
    @patch("tablet_uploader.upload_pending_replacements")
    @patch("tablet_uploader.upload_pending")
    def test_combined_usb_sync_uses_only_pending_queues(
        self,
        upload_measurements,
        upload_replacements,
        upload_temperatures,
        upload_alignments,
    ):
        upload_measurements.return_value = UploadSummary(total=1, uploaded=1)
        upload_replacements.return_value = UploadSummary(total=2, uploaded=2)
        upload_temperatures.return_value = UploadSummary(total=3, uploaded=2, skipped=1)
        upload_alignments.return_value = UploadSummary(total=4, uploaded=3, failed=1)

        summary = upload_pending_work(self.db_path)

        upload_measurements.assert_called_once()
        upload_replacements.assert_called_once()
        upload_temperatures.assert_called_once()
        upload_alignments.assert_called_once()
        self.assertEqual(summary.total, 10)
        self.assertEqual(summary.uploaded, 8)
        self.assertEqual(summary.skipped, 1)
        self.assertEqual(summary.failed, 1)

    def test_alignment_schema_upgrade_preserves_pending_rows_and_adds_history_cache(self):
        self.conn.execute(
            """
            CREATE TABLE ALINEACIONES_LOCAL (
              uuid TEXT PRIMARY KEY,
              localizacion INTEGER,
              sistema TEXT,
              fecha TEXT,
              hora TEXT,
              AMB_ANGULO_V REAL,
              sincronizado INTEGER DEFAULT 0
            )
            """
        )
        self.conn.execute(
            """
            INSERT INTO ALINEACIONES_LOCAL
              (uuid, localizacion, sistema, fecha, hora, AMB_ANGULO_V, sincronizado)
            VALUES ('a-legacy', 13, 'TURBINA BG-2', '2026-07-28', '10:00:00', -1.03, 0)
            """
        )

        ensure_alignment_schema(self.conn)

        columns = {
            row[1] for row in self.conn.execute("PRAGMA table_info(ALINEACIONES_LOCAL)")
        }
        self.assertTrue(
            {
                *ALIGNMENT_COLUMNS,
                "observaciones", "responsable", "cargo", "marca", "modelo", "serial", "odt",
                "puntos", "sincronizado", "error_sync", "created_at",
            }.issubset(columns)
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT uuid, AMB_ANGULO_V, sincronizado FROM ALINEACIONES_LOCAL WHERE uuid='a-legacy'"
            ).fetchone(),
            ("a-legacy", -1.03, 0),
        )
        self.assertIsNotNone(
            self.conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='ALINEACIONES_REMOTAS'"
            ).fetchone()
        )

    def _insert_alignment(self, uuid="a-1", synced=0, angle=-1.03):
        ensure_alignment_schema(self.conn)
        self.conn.execute(
            """
            INSERT INTO ALINEACIONES_LOCAL
              (uuid, localizacion, sistema, fecha, hora,
               AMB_ANGULO_V, AMB_ANGULO_H, AMB_COMPENSACION_V, AMB_COMPENSACION_H,
               observaciones, responsable, cargo, marca, modelo, serial, odt, sincronizado)
            VALUES (?, 13, 'TURBINA BG-2', '2026-07-28', '10:15:00',
                    ?, 0.05, 0, 2.5,
                    'alineacion prueba', 'Ana  Perez', 'Inspectora', 'WEG', 'W22', 'M-1', NULL, ?)
            """,
            (uuid, angle, synced),
        )
        self.conn.commit()

    def test_fetch_pending_alignments_and_insert_order_keep_non_applicable_values_null(self):
        self._insert_alignment()
        self._insert_alignment(uuid="a-synced", synced=1)

        rows = fetch_pending_alignments(self.db_path)
        values = build_alignment_insert_values(rows[0])

        self.assertEqual([row["uuid"] for row in rows], ["a-1"])
        self.assertEqual(
            ALIGNMENT_INSERT_COLUMNS,
            (
                "UUID",
                "FECHA", "HORA", "SISTEMA", "LOCALIZACION",
                "AMB_ANGULO_V", "AMB_ANGULO_H", "AMB_COMPENSACION_V", "AMB_COMPENSACION_H",
                "ACM_ANGULO_V", "ACM_ANGULO_H", "ACM_COMPENSACION_V", "ACM_COMPENSACION_H",
                "ACB_ANGULO_V", "ACB_ANGULO_H", "ACB_COMPENSACION_V", "ACB_COMPENSACION_H",
                "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
            ),
        )
        # UUID encabeza la tupla y lleva el uuid local: es la identidad que
        # permite reintentar el envio sin duplicar la alineacion en MOT_ALN_REG.
        self.assertEqual(ALIGNMENT_INSERT_COLUMNS[0], "UUID")
        self.assertEqual(values[0], "a-1")
        # Los valores corren una posicion respecto al orden anterior.
        self.assertEqual(values[1:9], ("2026-07-28", "10:15:00", "TURBINA BG-2", 13, -1.03, 0.05, 0.0, 2.5))
        self.assertEqual(values[9:17], (None,) * 8)
        self.assertEqual(values[-1], None)
        self.assertEqual(len(values), len(ALIGNMENT_INSERT_COLUMNS))

    def test_pending_display_includes_alignment_rows(self):
        self._insert_alignment()

        rows = pending_rows_for_display(self.db_path)

        alignment = next(row for row in rows if str(row.get("OBSERVACIONES", "")).startswith("Alineacion:"))
        self.assertEqual(alignment["LOCALIZACION"], 13)
        self.assertIn("AMB_ANGULO_V=-1.03", alignment["OBSERVACIONES"])

    def test_mark_alignment_result_updates_only_alignment_queue(self):
        self._insert_alignment()

        mark_alignment_result(self.db_path, "a-1", synced=False, error="USB desconectado")
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM ALINEACIONES_LOCAL WHERE uuid='a-1'"
            ).fetchone(),
            (0, "USB desconectado"),
        )
        mark_alignment_result(self.db_path, "a-1", synced=True)
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM ALINEACIONES_LOCAL WHERE uuid='a-1'"
            ).fetchone(),
            (1, None),
        )
        self.assertEqual(
            self.conn.execute("SELECT sincronizado FROM MEDICIONES_LOCAL WHERE uuid='u-1'").fetchone(),
            (0,),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_upload_alignment_is_idempotent_only_for_full_normalized_signature(self, connect):
        self._insert_alignment()

        class Cursor:
            def __init__(self): self.calls = []
            def execute(self, sql, params=None): self.calls.append((" ".join(sql.split()), params))
            def fetchall(self):
                return [{
                    "LOCALIZACION": 13, "FECHA": "2026-07-28", "HORA": "10:15:00",
                    "SISTEMA": " turbina   bg-2 ",
                    "AMB_ANGULO_V": "-1.030", "AMB_ANGULO_H": ".050", "AMB_COMPENSACION_V": 0,
                    "AMB_COMPENSACION_H": "2.500", "ACM_ANGULO_V": None, "ACM_ANGULO_H": None,
                    "ACM_COMPENSACION_V": None, "ACM_COMPENSACION_H": None,
                    "ACB_ANGULO_V": None, "ACB_ANGULO_H": None,
                    "ACB_COMPENSACION_V": None, "ACB_COMPENSACION_H": None,
                    "OBSERVACIONES": " Alineacion   Prueba ", "USUARIO": "ANA PEREZ",
                    "CARGO": "inspectora", "MARCA": "weg", "MODELO": "w22", "SERIAL": "m-1", "ODT": None,
                }]
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def __init__(self): self.cur = Cursor()
            def cursor(self): return self.cur
            def commit(self): raise AssertionError("duplicate must not insert")
            def rollback(self): pass
            def close(self): pass
        db = Db()
        connect.return_value = db

        summary = upload_alignment_rows(
            self.db_path, fetch_pending_alignments(self.db_path), log=lambda _: None
        )

        self.assertEqual((summary.uploaded, summary.skipped, summary.failed), (0, 1, 0))
        self.assertEqual(
            self.conn.execute("SELECT sincronizado FROM ALINEACIONES_LOCAL WHERE uuid='a-1'").fetchone(),
            (1,),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_upload_alignment_same_timestamp_with_different_values_inserts_and_commits(self, connect):
        self._insert_alignment()

        class Cursor:
            def __init__(self): self.calls = []
            def execute(self, sql, params=None): self.calls.append((" ".join(sql.split()), params))
            def fetchall(self):
                return [{
                    "LOCALIZACION": 13, "FECHA": "2026-07-28", "HORA": "10:15:00",
                    "SISTEMA": "TURBINA BG-2", "AMB_ANGULO_V": -1.02, "AMB_ANGULO_H": 0.05,
                    "AMB_COMPENSACION_V": 0, "AMB_COMPENSACION_H": 2.5,
                    "ACM_ANGULO_V": None, "ACM_ANGULO_H": None, "ACM_COMPENSACION_V": None,
                    "ACM_COMPENSACION_H": None, "ACB_ANGULO_V": None, "ACB_ANGULO_H": None,
                    "ACB_COMPENSACION_V": None, "ACB_COMPENSACION_H": None,
                    "OBSERVACIONES": "alineacion prueba", "USUARIO": "Ana Perez", "CARGO": "Inspectora",
                    "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-1", "ODT": None,
                }]
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def __init__(self): self.cur = Cursor(); self.commits = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): pass
            def close(self): pass
        db = Db()
        connect.return_value = db
        expected_values = build_alignment_insert_values(
            fetch_pending_alignments(self.db_path)[0]
        )

        summary = upload_alignment_rows(self.db_path, fetch_pending_alignments(self.db_path), log=lambda _: None)

        self.assertEqual((summary.uploaded, summary.skipped, summary.failed), (1, 0, 0))
        self.assertEqual(db.commits, 1)
        insert = next(params for sql, params in db.cur.calls if sql.startswith("INSERT INTO MOT_ALN_REG"))
        self.assertEqual(insert, expected_values)

    @patch("tablet_uploader.connect_mariadb")
    def test_alignment_row_failure_rolls_back_stays_pending_and_continues(self, connect):
        self._insert_alignment(uuid="a-fails")
        self._insert_alignment(uuid="a-next", angle=-0.5)

        class Cursor:
            def __init__(self): self.calls = []
            def execute(self, sql, params=None):
                compact = " ".join(sql.split()); self.calls.append((compact, params))
                # Con UUID al frente los valores corren una posicion: HORA pasa
                # de params[1] a params[2] y AMB_ANGULO_V de params[4] a params[5].
                # Solo debe reventar la fila a-1 (angulo -1.03), no la a-next.
                if compact.startswith("INSERT INTO MOT_ALN_REG") and params[2] == "10:15:00" and params[5] == -1.03:
                    raise RuntimeError("alineacion rechazada")
            def fetchall(self): return []
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def __init__(self): self.cur = Cursor(); self.commits = 0; self.rollbacks = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): self.rollbacks += 1
            def close(self): pass
        db = Db()
        connect.return_value = db

        summary = upload_alignment_rows(self.db_path, fetch_pending_alignments(self.db_path), log=lambda _: None)

        self.assertEqual((summary.uploaded, summary.failed), (1, 1))
        self.assertEqual((db.commits, db.rollbacks), (1, 1))
        # Cada INSERT lleva en params[0] el uuid de su propia alineacion: es lo
        # que permite identificar la fila que fallo sin mirar fecha ni hora.
        inserts = [
            params for sql, params in db.cur.calls
            if sql.startswith("INSERT INTO MOT_ALN_REG")
        ]
        self.assertEqual([params[0] for params in inserts], ["a-fails", "a-next"])
        self.assertEqual(
            self.conn.execute("SELECT sincronizado, error_sync FROM ALINEACIONES_LOCAL WHERE uuid='a-fails'").fetchone(),
            (0, "alineacion rechazada"),
        )
        self.assertEqual(
            self.conn.execute("SELECT sincronizado FROM ALINEACIONES_LOCAL WHERE uuid='a-next'").fetchone(),
            (1,),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_alignment_history_is_bounded_ordered_and_does_not_touch_local_pending_rows(self, connect):
        self._insert_alignment()
        remote_rows = [{
            "ID": 700, "LOCALIZACION": 13, "SISTEMA": "TURBINA BG-2", "FECHA": "2026-07-27", "HORA": "09:00:00",
            "AMB_ANGULO_V": -1.0, "AMB_ANGULO_H": 0.0, "AMB_COMPENSACION_V": 0.0, "AMB_COMPENSACION_H": 2.0,
            "OBSERVACIONES": "anterior", "USUARIO": "Luis", "CARGO": "Tecnico", "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-1", "ODT": None,
        }]
        class Cursor:
            def __init__(self): self.queries = []
            def execute(self, sql, params=None): self.queries.append(" ".join(sql.split()))
            def fetchall(self): return remote_rows
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def __init__(self): self.cur = Cursor()
            def cursor(self): return self.cur
            def close(self): pass
        db = Db()
        connect.return_value = db

        count = sync_alignment_history_from_mariadb(self.db_path, log=lambda _: None)

        self.assertEqual(count, 1)
        self.assertTrue(any("FROM MOT_ALN_REG" in query and "LIMIT 500" in query for query in db.cur.queries))
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM ALINEACIONES_REMOTAS").fetchone(), (1,))
        self.assertEqual(
            self.conn.execute(
                "SELECT puntos FROM ALINEACIONES_REMOTAS WHERE localizacion=13"
            ).fetchone(),
            (1,),
        )
        self.assertEqual(self.conn.execute("SELECT sincronizado FROM ALINEACIONES_LOCAL WHERE uuid='a-1'").fetchone(), (0,))

    def test_temperature_schema_upgrade_preserves_pending_rows(self):
        self.conn.execute(
            """
            CREATE TABLE TEMPERATURAS_LOCAL (
              uuid TEXT PRIMARY KEY,
              localizacion INTEGER,
              sistema TEXT,
              fecha TEXT,
              hora TEXT,
              T1 REAL,
              sincronizado INTEGER DEFAULT 0,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        self.conn.execute(
            """
            INSERT INTO TEMPERATURAS_LOCAL
              (uuid, localizacion, sistema, fecha, hora, T1, sincronizado)
            VALUES ('t-legacy', 13, 'TURBINA BG-2', '2026-07-22', '11:00:00', 44.5, 0)
            """
        )
        ensure_local_temperature_tables(self.conn)

        columns = {
            row[1] for row in self.conn.execute("PRAGMA table_info(TEMPERATURAS_LOCAL)")
        }
        self.assertTrue(
            {
                *TEMPERATURE_COLUMNS,
                "observaciones",
                "responsable",
                "cargo",
                "marca",
                "modelo",
                "serial",
                "odt",
                "error_sync",
            }.issubset(columns)
        )
        row = self.conn.execute(
            "SELECT uuid, T1, sincronizado FROM TEMPERATURAS_LOCAL WHERE uuid='t-legacy'"
        ).fetchone()
        self.assertEqual(row, ("t-legacy", 44.5, 0))

    def _insert_temperature(self, uuid="t-1", synced=0, t1=42.25, t2=None):
        ensure_local_temperature_tables(self.conn)
        self.conn.execute(
            """
            INSERT INTO TEMPERATURAS_LOCAL
              (uuid, localizacion, sistema, fecha, hora, T1, T2,
               observaciones, responsable, cargo, marca, modelo, serial, odt,
               sincronizado)
            VALUES (?, 13, 'TURBINA BG-2', '2026-07-22', '11:30:00', ?, ?,
                    'lectura térmica', 'Ana', 'Inspectora', 'WEG', 'W22', 'M-1', 8401, ?)
            """,
            (uuid, t1, t2, synced),
        )
        self.conn.commit()

    def test_fetch_pending_temperatures_defaults_missing_or_null_points_to_zero(self):
        self._insert_temperature()
        self._insert_temperature(uuid="t-synced", synced=1, t1=99.0)

        rows = fetch_pending_temperatures(self.db_path)

        self.assertEqual([row["uuid"] for row in rows], ["t-1"])
        self.assertEqual(rows[0]["T1"], 42.25)
        self.assertEqual(rows[0]["T2"], 0.0)
        self.assertEqual(rows[0]["T10"], 0.0)
        self.assertEqual(rows[0]["USUARIO"], "Ana")
        self.assertEqual(rows[0]["ODT"], 8401)

    def test_temperature_insert_values_match_mot_temp_mues_order(self):
        self._insert_temperature()
        row = fetch_pending_temperatures(self.db_path)[0]

        values = build_temperature_insert_values(row)

        self.assertEqual(
            TEMPERATURE_INSERT_COLUMNS,
            (
                "UUID",
                "FECHA", "HORA", "SISTEMA", "LOCALIZACION",
                "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10",
                "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
            ),
        )
        # UUID encabeza la tupla y viaja con el uuid local: sin el, un reintento
        # tras un corte de USB duplicaria la lectura en MOT_TEMP_MUES.
        self.assertEqual(TEMPERATURE_INSERT_COLUMNS[0], "UUID")
        self.assertEqual(values[0], "t-1")
        self.assertEqual(
            values,
            (
                "t-1",
                "2026-07-22", "11:30:00", "TURBINA BG-2", 13,
                42.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                "lectura térmica", "Ana", "Inspectora", "WEG", "W22", "M-1", 8401,
            ),
        )

    def test_mark_temperature_result_updates_only_temperature_queue(self):
        self._insert_temperature()

        mark_temperature_result(self.db_path, "t-1", synced=False, error="sin red")
        failed = self.conn.execute(
            "SELECT sincronizado, error_sync FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
        ).fetchone()
        mark_temperature_result(self.db_path, "t-1", synced=True)
        synced = self.conn.execute(
            "SELECT sincronizado, error_sync FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
        ).fetchone()

        self.assertEqual(failed, (0, "sin red"))
        self.assertEqual(synced, (1, None))
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado FROM MEDICIONES_LOCAL WHERE uuid='u-1'"
            ).fetchone(),
            (0,),
        )

    @patch("tablet_uploader.temperature_measurement_exists", return_value=False)
    @patch("tablet_uploader.connect_mariadb")
    def test_upload_temperature_inserts_commits_and_marks_synced(self, connect, _exists):
        self._insert_temperature()

        class Cursor:
            def __init__(self):
                self.calls = []
            def execute(self, sql, params=None):
                self.calls.append((" ".join(sql.split()), params))
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self):
                self.cur = Cursor(); self.commits = 0; self.rollbacks = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): self.rollbacks += 1
            def close(self): pass

        db = Db()
        connect.return_value = db

        summary = upload_temperature_rows(
            self.db_path, fetch_pending_temperatures(self.db_path), log=lambda _: None
        )

        self.assertEqual((summary.uploaded, summary.skipped, summary.failed), (1, 0, 0))
        self.assertEqual(db.commits, 1)
        self.assertEqual(db.rollbacks, 0)
        self.assertTrue(any(call[0].startswith("INSERT INTO MOT_TEMP_MUES") for call in db.cur.calls))
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
            ).fetchone(),
            (1, None),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_upload_temperature_identical_signature_is_idempotently_skipped(self, connect):
        self._insert_temperature()

        class Cursor:
            def execute(self, sql, params=None): pass
            def fetchone(self): return {"ID": 71}
            def fetchall(self):
                return [{
                    "LOCALIZACION": 13,
                    "FECHA": "2026-07-22",
                    "HORA": "11:30:00",
                    "SISTEMA": "TURBINA BG-2",
                    "T1": 42.25,
                    "T2": None,
                    "OBSERVACIONES": "lectura térmica",
                    "USUARIO": "Ana",
                    "CARGO": "Inspectora",
                    "MARCA": "WEG",
                    "MODELO": "W22",
                    "SERIAL": "M-1",
                    "ODT": "8401",
                }]
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def cursor(self): return Cursor()
            def commit(self): raise AssertionError("duplicate must not insert")
            def rollback(self): pass
            def close(self): pass
        connect.return_value = Db()

        summary = upload_temperature_rows(
            self.db_path, fetch_pending_temperatures(self.db_path), log=lambda _: None
        )

        self.assertEqual((summary.uploaded, summary.skipped, summary.failed), (0, 1, 0))
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
            ).fetchone(),
            (1,),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_upload_temperature_same_timestamp_but_different_value_inserts(self, connect):
        self._insert_temperature()

        class Cursor:
            def __init__(self): self.calls = []
            def execute(self, sql, params=None): self.calls.append((" ".join(sql.split()), params))
            def fetchone(self): return {"ID": 71}
            def fetchall(self):
                return [{
                    "LOCALIZACION": 13,
                    "FECHA": "2026-07-22",
                    "HORA": "11:30:00",
                    "SISTEMA": "TURBINA BG-2",
                    "T1": 42.24,
                    "T2": 0,
                    "OBSERVACIONES": "lectura térmica",
                    "USUARIO": "Ana",
                    "CARGO": "Inspectora",
                    "MARCA": "WEG",
                    "MODELO": "W22",
                    "SERIAL": "M-1",
                    "ODT": 8401,
                }]
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self): self.cur = Cursor(); self.commits = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): pass
            def close(self): pass
        db = Db()
        connect.return_value = db

        summary = upload_temperature_rows(
            self.db_path, fetch_pending_temperatures(self.db_path), log=lambda _: None
        )

        self.assertEqual((summary.uploaded, summary.skipped, summary.failed), (1, 0, 0))
        self.assertEqual(db.commits, 1)
        self.assertTrue(
            any(sql.startswith("INSERT INTO MOT_TEMP_MUES") for sql, _ in db.cur.calls)
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_temperature_row_failure_rolls_back_stays_pending_and_continues(self, connect):
        self._insert_temperature(uuid="t-fails", t1=50.0)
        ensure_local_temperature_tables(self.conn)
        self.conn.execute(
            """
            INSERT INTO TEMPERATURAS_LOCAL
              (uuid, localizacion, sistema, fecha, hora, T1, sincronizado)
            VALUES ('t-next', 14, 'TURBINA BG-2', '2026-07-22', '11:31:00', 51.0, 0)
            """
        )
        self.conn.commit()

        class Cursor:
            def __init__(self):
                self.calls = []
                self._found = None
            def execute(self, sql, params=None):
                compact = " ".join(sql.split())
                self.calls.append((compact, params))
                if compact.startswith("SELECT ID FROM MOT_TEMP_MUES"):
                    self._found = None
                # Con UUID al frente los valores corren una posicion: HORA pasa
                # de params[1] a params[2]. Solo revienta t-fails (11:30:00).
                elif compact.startswith("INSERT INTO MOT_TEMP_MUES") and params[2] == "11:30:00":
                    raise RuntimeError("temperatura rechazada")
            def fetchone(self): return self._found
            def fetchall(self): return []
            def __enter__(self): return self
            def __exit__(self, *args): return False

        class Db:
            def __init__(self):
                self.cur = Cursor(); self.commits = 0; self.rollbacks = 0
            def cursor(self): return self.cur
            def commit(self): self.commits += 1
            def rollback(self): self.rollbacks += 1
            def close(self): pass

        db = Db()
        connect.return_value = db

        summary = upload_temperature_rows(
            self.db_path, fetch_pending_temperatures(self.db_path), log=lambda _: None
        )

        self.assertEqual((summary.uploaded, summary.failed), (1, 1))
        self.assertEqual((db.commits, db.rollbacks), (1, 1))
        # Cada INSERT lleva su propio uuid en params[0]: la fila que fallo se
        # identifica por identidad, no por la fecha/hora que comparten.
        inserts = [
            params for sql, params in db.cur.calls
            if sql.startswith("INSERT INTO MOT_TEMP_MUES")
        ]
        self.assertEqual([params[0] for params in inserts], ["t-fails", "t-next"])
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM TEMPERATURAS_LOCAL WHERE uuid='t-fails'"
            ).fetchone(),
            (0, "temperatura rechazada"),
        )
        self.assertEqual(
            [row["uuid"] for row in fetch_pending_temperatures(self.db_path)],
            ["t-fails"],
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM TEMPERATURAS_LOCAL WHERE uuid='t-next'"
            ).fetchone(),
            (1, None),
        )

    @patch("tablet_uploader.sync_alignment_history_from_mariadb")
    @patch("tablet_uploader.sync_latest_temperatures_from_mariadb")
    @patch("tablet_uploader.sync_latest_measurements_from_mariadb")
    @patch("tablet_uploader.sync_users_from_mariadb")
    @patch("tablet_uploader.sync_equipo_info_from_mariadb")
    @patch("tablet_uploader.read_tablet_operator", return_value=("Ana", "Inspectora"))
    @patch("tablet_uploader.push_tablet_database")
    @patch("tablet_uploader.pull_tablet_database")
    @patch("tablet_uploader.set_tablet_usb_status")
    @patch("tablet_uploader.connect_mariadb")
    def test_device_upload_integrates_temperature_queue_counts_and_pushes_result(
        self,
        connect,
        set_status,
        pull_db,
        push_db,
        _operator,
        _sync_equipment,
        _sync_users,
        _sync_vibration,
        sync_temperature_history,
        sync_alignment_history,
    ):
        self.conn.execute("UPDATE MEDICIONES_LOCAL SET sincronizado=1")
        self.conn.execute("UPDATE REEMPLAZOS_LOCAL SET sincronizado=1")
        self.conn.commit()
        self._insert_temperature()
        pull_db.return_value = self.db_path

        class Cursor:
            def __init__(self): self._found = None
            def execute(self, sql, params=None):
                if "SELECT ID" in sql:
                    self._found = None
            def fetchone(self): return self._found
            def fetchall(self): return []
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def cursor(self): return Cursor()
            def commit(self): pass
            def rollback(self): pass
            def close(self): pass
        connect.return_value = Db()
        logs = []

        summary = perform_usb_upload_for_device(
            Device("TAB-TEMP", "device"), Path(self.tmp.name), log=logs.append
        )

        self.assertEqual((summary.total, summary.uploaded, summary.failed), (1, 1, 0))
        self.assertIn("Temperaturas pendientes encontradas: 1", logs)
        self.assertIn("Resumen temperaturas: 1 subidas, 0 existentes, 0 errores.", logs)
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
            ).fetchone(),
            (1,),
        )
        sync_temperature_history.assert_called_once_with(self.db_path, log=logs.append)
        sync_alignment_history.assert_called_once_with(self.db_path, log=logs.append)
        push_db.assert_called_once_with("TAB-TEMP", self.db_path)
        self.assertEqual(set_status.call_args_list[-1].kwargs["status"], "DONE")

    @patch("tablet_uploader.connect_mariadb")
    def test_remote_temperature_refresh_keeps_newer_pending_as_latest(self, connect):
        self._insert_temperature()
        remote_rows = [
            {
                "ID": 71, "LOCALIZACION": 13, "SISTEMA": "TURBINA BG-2",
                "FECHA": "2026-07-21", "HORA": "08:00:00", "T1": 38.0,
                "OBSERVACIONES": "anterior", "USUARIO": "Luis", "CARGO": "Técnico",
                "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-1", "ODT": 8300,
            },
            {
                "ID": 72, "LOCALIZACION": 13, "SISTEMA": "TURBINA BG-2",
                "FECHA": "2026-07-22", "HORA": "10:00:00", "T1": 41.0,
                "OBSERVACIONES": "última", "USUARIO": "Ana", "CARGO": "Inspectora",
                "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-1", "ODT": 8399,
            },
        ]

        class Cursor:
            def execute(self, sql, params=None): pass
            def fetchall(self): return remote_rows
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def cursor(self): return Cursor()
            def close(self): pass
        connect.return_value = Db()

        latest_count = sync_latest_temperatures_from_mariadb(self.db_path, log=lambda _: None)

        self.assertEqual(latest_count, 1)
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM TEMPERATURAS_REMOTAS").fetchone(),
            (2,),
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT T1, fecha, hora FROM ULTIMA_TEMPERATURA WHERE localizacion=13"
            ).fetchone(),
            (42.25, "2026-07-22", "11:30:00"),
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, T1 FROM TEMPERATURAS_LOCAL WHERE uuid='t-1'"
            ).fetchone(),
            (0, 42.25),
        )

    @patch("tablet_uploader.connect_mariadb")
    def test_remote_temperature_queries_bound_history_and_latest_per_location(self, connect):
        class Cursor:
            def __init__(self): self.queries = []
            def execute(self, sql, params=None): self.queries.append(" ".join(sql.split()))
            def fetchall(self): return []
            def __enter__(self): return self
            def __exit__(self, *args): return False
        class Db:
            def __init__(self): self.cur = Cursor()
            def cursor(self): return self.cur
            def close(self): pass
        db = Db()
        connect.return_value = db

        sync_latest_temperatures_from_mariadb(self.db_path, log=lambda _: None)

        history_queries = [
            query for query in db.cur.queries
            if query.startswith("SELECT * FROM MOT_TEMP_MUES")
        ]
        self.assertEqual(len(history_queries), 1)
        chronological_order = (
            "COALESCE("
            "STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'), "
            "STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')"
            ") DESC, ID DESC"
        )
        self.assertIn(f"ORDER BY {chronological_order} LIMIT 500", history_queries[0])
        self.assertTrue(
            any(
                "ROW_NUMBER() OVER" in query
                and "PARTITION BY LOCALIZACION" in query
                and f"ORDER BY {chronological_order}" in query
                and "WHERE chronological_rank = 1" in query
                for query in db.cur.queries
            )
        )
        self.assertFalse(any("MAX(ID)" in query for query in db.cur.queries))

    def test_temperature_datetime_formats_cross_year_chronologically(self):
        old_spanish = parse_measurement_datetime("31/12/2025", "23:59:59")
        new_iso = parse_measurement_datetime("2026-01-01", "00:00:00")

        self.assertGreater(new_iso, old_spanish)

    def test_build_insert_values_matches_mariadb_column_order(self):
        row = fetch_pending_measurements(self.db_path)[0]

        values = build_insert_values(row)

        # UUID va primero en MOT_VIBR_MUES: identifica la medicion para que un
        # reintento no la duplique. Todo lo demas corre una posicion.
        self.assertEqual(INSERT_COLUMNS[0], "UUID")
        self.assertEqual(values[0], "u-1")
        self.assertEqual(values[1:5], ("2026-07-06", "09:00:00", "TURBINA BG-2", 13))
        self.assertEqual(values[5:8], (2.0, 3.0, 4.0))
        self.assertEqual(values[INSERT_COLUMNS.index("H1")], 2.0)
        self.assertEqual(values[INSERT_COLUMNS.index("RMS")], 3.1)
        self.assertEqual(values[INSERT_COLUMNS.index("OBSERVACIONES")], "prueba")
        self.assertEqual(len(values), len(INSERT_COLUMNS))

    def test_mark_local_result_updates_synced_and_error_state(self):
        mark_local_result(self.db_path, "u-1", synced=True)
        row = self.conn.execute(
            "SELECT sincronizado, error_sync FROM MEDICIONES_LOCAL WHERE uuid = 'u-1'"
        ).fetchone()

        self.assertEqual(row, (1, None))

        mark_local_result(self.db_path, "u-1", synced=False, error="fallo")
        row = self.conn.execute(
            "SELECT sincronizado, error_sync FROM MEDICIONES_LOCAL WHERE uuid = 'u-1'"
        ).fetchone()

        self.assertEqual(row, (0, "fallo"))

    def test_fetch_pending_replacements_keeps_operation_group(self):
        rows = fetch_pending_replacements(self.db_path)

        self.assertEqual([row["uuid"] for row in rows], ["r-1", "r-2"])
        self.assertEqual({row["operation_uuid"] for row in rows}, {"op-1"})

    def test_first_replacement_load_inserts_current_without_history(self):
        class Cursor:
            def __init__(self):
                self.calls = []

            def execute(self, sql, params=None):
                self.calls.append((" ".join(sql.split()), params))

            def fetchone(self):
                return None

        cursor = Cursor()
        result = apply_replacement_row(
            cursor,
            {
                "localizacion": 13,
                "code_conjunto": 2,
                "equipo": 3,
                "marca": "SEW",
                "modelo": "R97",
                "serial": "C-NEW",
                "fecha": "2026-07-21",
                "hora": "13:00:00",
            },
        )

        self.assertEqual("created", result)
        self.assertTrue(
            any(call[0].startswith("INSERT INTO `MOT_CAJA_DATA`") for call in cursor.calls)
        )
        self.assertFalse(any("MOT_LOG_RPL" in call[0] for call in cursor.calls))

    def test_motor_replacement_writes_complete_mot_data_plate(self):
        class Cursor:
            def __init__(self):
                self.calls = []

            def execute(self, sql, params=None):
                self.calls.append((" ".join(sql.split()), params))

            def fetchone(self):
                return None

        cursor = Cursor()
        result = apply_replacement_row(
            cursor,
            {
                "localizacion": 13,
                "code_conjunto": 2,
                "equipo": 1,
                "marca": "WEG",
                "modelo": "W22",
                "serial": "M-NEW",
                "actualizar_especificaciones": 1,
                "voltaje": "440",
                "corriente": "18.5",
                "rpm": "1780",
                "sf": "1.15",
                "hp": "15",
                "frame": "254T",
                "brgs_drive": "6309",
                "brgs_opp": "6208",
                "ciclo": "60",
                "arranque": "DIRECTO",
                "ph": "3",
                "tension": "12",
                "lubricacion": "GRASA",
                "fecha": "2026-07-22",
                "hora": "09:00:00",
            },
        )

        self.assertEqual("created", result)
        insert = next(
            call for call in cursor.calls if call[0].startswith("INSERT INTO `MOT_DATA`")
        )
        self.assertIn("VOLTAJE", insert[0])
        self.assertIn("BRGS_DRIVE", insert[0])
        self.assertIn("LUBRICACION", insert[0])
        self.assertIn("440", insert[1])
        self.assertIn("GRASA", insert[1])

    def _fake_master_db(self, rows=()):
        """Monta una maestra MOT_DATA + la bitacora MOT_LOG_RPL en memoria."""
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        self.addCleanup(conn.close)
        conn.execute(
            """
            CREATE TABLE `MOT_DATA` (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              FECHA TEXT, HORA TEXT,
              MARCA TEXT, MODELO TEXT, SERIAL TEXT,
              UBICACION INTEGER, CODE_CONJUNTO INTEGER,
              ACTIVO INTEGER, ESTADO TEXT, LOCALIZACION TEXT,
              VOLTAJE TEXT, CORRIENTE TEXT, RPM TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE MOT_LOG_RPL (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              FECHA TEXT, HORA TEXT,
              MARCA TEXT, MODELO TEXT, SERIAL TEXT,
              EQUIPO INTEGER, UBICACION INTEGER, CODE_CONJUNTO INTEGER,
              ODT INTEGER, USUARIO TEXT, CARGO TEXT, MOTIVO TEXT,
              LOCALIZACION TEXT, ESTADO TEXT, FECHA_INSTALACION TEXT,
              OBSERVACIONES TEXT, UUID TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE MOT_ORD_REP (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              UUID TEXT, EQUIPO TEXT, SERIAL TEXT, MARCA TEXT, MODELO TEXT,
              UBICACION_ORIGEN INTEGER, DESTINO TEXT, MOTIVO TEXT,
              FECHA_SALIDA TEXT, HORA_SALIDA TEXT, USUARIO_SALIDA TEXT,
              CARGO_SALIDA TEXT, ODT INTEGER, ESTADO_ORDEN TEXT,
              FECHA_RETORNO TEXT, HORA_RETORNO TEXT, USUARIO_CIERRE TEXT,
              CARGO_CIERRE TEXT, TRABAJO TEXT, RESULTADO TEXT,
              UBICACION_FINAL TEXT, OBSERVACIONES TEXT
            )
            """
        )
        for row in rows:
            columns = ", ".join(row)
            marks = ", ".join("?" * len(row))
            conn.execute(
                f"INSERT INTO `MOT_DATA` ({columns}) VALUES ({marks})",
                tuple(row.values()),
            )
        conn.commit()
        return conn

    def _motor_rows(self, conn):
        return [
            dict(row)
            for row in conn.execute(
                "SELECT * FROM `MOT_DATA` ORDER BY ID"
            ).fetchall()
        ]

    def test_motor_replacement_keeps_technical_data_when_user_says_no(self):
        # El tecnico permuta el motor pero contesta que NO quiere reescribir la
        # placa tecnica. Ninguna de las dos filas puede acabar con los datos
        # tecnicos pisados o borrados.
        conn = self._fake_master_db(
            [
                {
                    "FECHA": "2025-01-10", "HORA": "08:00:00",
                    "MARCA": "WEG", "MODELO": "OLD", "SERIAL": "OLD-1",
                    "UBICACION": 13, "CODE_CONJUNTO": 2,
                    "ACTIVO": 1, "ESTADO": "INSTALADO",
                    "VOLTAJE": "440", "CORRIENTE": "18.5", "RPM": "1780",
                }
            ]
        )
        cursor = FakeMariaCursor(conn)

        result = apply_replacement_row(
            cursor,
            {
                "localizacion": 13,
                "code_conjunto": 2,
                "equipo": 1,
                "marca": "MARATHON",
                "modelo": "NEW",
                "serial": "NEW-1",
                "actualizar_especificaciones": 0,
                "voltaje": "",
                "estado_saliente": "AVERIADO",
                "sitio_saliente": "TALLER CENTRAL",
                "fecha": "2026-07-22",
                "hora": "10:00:00",
            },
        )

        self.assertEqual("created", result)
        # Ninguna sentencia contra la maestra puede mencionar columnas tecnicas:
        # el usuario dijo que no. Ese "no" es lo que este test protege.
        for sql in cursor.sql_texts():
            if "`MOT_DATA`" in sql and not sql.startswith("SELECT"):
                self.assertNotIn("VOLTAJE", sql)
                self.assertNotIn("CORRIENTE", sql)
                self.assertNotIn("RPM", sql)
        # La baja del motor saliente tampoco toca su placa comercial.
        baja = next(
            sql for sql in cursor.sql_texts()
            if sql.startswith("UPDATE `MOT_DATA` SET ACTIVO = 0")
        )
        self.assertNotIn("MARCA", baja)
        self.assertNotIn("MODELO", baja)
        self.assertNotIn("SERIAL", baja)

        saliente, entrante = self._motor_rows(conn)
        self.assertEqual(
            (saliente["MARCA"], saliente["MODELO"], saliente["SERIAL"]),
            ("WEG", "OLD", "OLD-1"),
        )
        self.assertEqual(
            (saliente["VOLTAJE"], saliente["CORRIENTE"], saliente["RPM"]),
            ("440", "18.5", "1780"),
        )
        self.assertEqual((saliente["ACTIVO"], saliente["ESTADO"]), (0, "AVERIADO"))
        self.assertEqual(
            (entrante["MARCA"], entrante["MODELO"], entrante["SERIAL"]),
            ("MARATHON", "NEW", "NEW-1"),
        )
        # El motor entrante entra sin especificaciones inventadas.
        self.assertEqual(
            (entrante["VOLTAJE"], entrante["CORRIENTE"], entrante["RPM"]),
            (None, None, None),
        )

    def test_bitacora_guarda_todo_el_contexto_del_reemplazo(self):
        # Regresion real: la ruta USB escribia MOT_LOG_RPL con solo 8 columnas
        # y ODT, USUARIO, CARGO, MOTIVO, LOCALIZACION, ESTADO,
        # FECHA_INSTALACION y UUID quedaban en NULL. El historial existia pero
        # no servia para auditar quien hizo que, ni por que.
        conn = self._fake_master_db(
            [
                {
                    "FECHA": "2025-03-04", "HORA": "07:30:00",
                    "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-SALE",
                    "UBICACION": 21, "CODE_CONJUNTO": 3,
                    "ACTIVO": 1, "ESTADO": "INSTALADO",
                }
            ]
        )
        cursor = FakeMariaCursor(conn)

        apply_replacement_row(
            cursor,
            {
                "localizacion": 21,
                "code_conjunto": 3,
                "equipo": 1,
                "marca": "SIEMENS",
                "modelo": "1LE",
                "serial": "M-ENTRA",
                "motivo": "Rodamiento",
                "estado_saliente": "AVERIADO",
                "sitio_saliente": "TALLER ELECTRICO",
                "observaciones": "Ruido en lado acople",
                "odt": 4471,
                # La app sufija el uuid por componente: 38 caracteres, dos mas
                # de los que acepta el CHAR(36) de la bitacora. Debe usarse
                # operation_uuid, que identifica la operacion y mide 36.
                "uuid": "da4e3747-3a90-42ef-be35-0134c268a090-1",
                "operation_uuid": "da4e3747-3a90-42ef-be35-0134c268a090",
                "fecha": "2026-08-13",
                "hora": "09:15:00",
            },
            usuario="ALEXI AVILA",
            cargo="SUP.MECANICO",
        )

        log = conn.execute(
            "SELECT * FROM MOT_LOG_RPL ORDER BY ID DESC LIMIT 1"
        ).fetchone()
        self.assertIsNotNone(log)
        self.assertEqual(log["SERIAL"], "M-SALE", "se anota la pieza que SALE")
        self.assertEqual(log["ODT"], 4471)
        self.assertEqual(log["USUARIO"], "ALEXI AVILA")
        self.assertEqual(log["CARGO"], "SUP.MECANICO")
        self.assertEqual(log["MOTIVO"], "Rodamiento")
        self.assertEqual(log["ESTADO"], "AVERIADO")
        self.assertEqual(log["LOCALIZACION"], "TALLER ELECTRICO")
        self.assertEqual(log["OBSERVACIONES"], "Ruido en lado acople")
        self.assertEqual(log["UUID"], "da4e3747-3a90-42ef-be35-0134c268a090")
        self.assertLessEqual(len(log["UUID"]), 36, "no cabe en el CHAR(36)")
        # Con la fecha de instalacion y la de retiro se saca el tiempo que la
        # pieza estuvo en servicio, que es para lo que existe la columna.
        self.assertEqual(log["FECHA_INSTALACION"], "2025-03-04")
        self.assertEqual(log["FECHA"], "2026-08-13")

    def test_replaced_part_row_survives_in_master_with_status_and_site(self):
        # Regresion principal del modelo por pieza fisica: antes el reemplazo
        # SOBRESCRIBIA la fila y la pieza retirada desaparecia del inventario.
        conn = self._fake_master_db(
            [
                {
                    "FECHA": "2025-01-10", "HORA": "08:00:00",
                    "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-OLD",
                    "UBICACION": 13, "CODE_CONJUNTO": 2,
                    "ACTIVO": 1, "ESTADO": "INSTALADO",
                    "VOLTAJE": "440",
                }
            ]
        )
        cursor = FakeMariaCursor(conn)

        result = apply_replacement_row(
            cursor,
            {
                "localizacion": 13,
                "code_conjunto": 2,
                "equipo": 1,
                "marca": "MARATHON",
                "modelo": "M-NUEVO",
                "serial": "M-NEW",
                "estado_saliente": "AVERIADO",
                "sitio_saliente": "TALLER CENTRAL",
                "fecha": "2026-07-22",
                "hora": "10:00:00",
            },
        )

        self.assertEqual("created", result)
        # Nadie borra filas de la maestra: el historico de piezas es acumulativo.
        self.assertFalse(any("DELETE" in sql for sql in cursor.sql_texts()))

        rows = self._motor_rows(conn)
        self.assertEqual(len(rows), 2)
        saliente = next(row for row in rows if row["SERIAL"] == "M-OLD")
        entrante = next(row for row in rows if row["SERIAL"] == "M-NEW")

        # La pieza retirada conserva su fila, su placa y sus especificaciones,
        # y queda trazable: en que estado quedo y a donde se la llevaron.
        self.assertEqual(saliente["ACTIVO"], 0)
        self.assertEqual(saliente["ESTADO"], "AVERIADO")
        self.assertEqual(saliente["LOCALIZACION"], "TALLER CENTRAL")
        self.assertEqual((saliente["MARCA"], saliente["MODELO"]), ("WEG", "W22"))
        self.assertEqual(saliente["VOLTAJE"], "440")
        # No se le tocan FECHA ni HORA: son las de su instalacion original.
        self.assertEqual((saliente["FECHA"], saliente["HORA"]), ("2025-01-10", "08:00:00"))

        # La entrante ocupa la posicion, activa e instalada.
        self.assertEqual(entrante["ACTIVO"], 1)
        self.assertEqual(entrante["ESTADO"], "INSTALADO")
        self.assertEqual(
            (entrante["UBICACION"], entrante["CODE_CONJUNTO"]), (13, 2)
        )
        self.assertEqual((entrante["FECHA"], entrante["HORA"]), ("2026-07-22", "10:00:00"))

        # Solo una pieza activa por posicion: si quedaran dos, el formato
        # oficial impreso podria llevar el serial equivocado.
        activos = conn.execute(
            "SELECT COUNT(*) FROM `MOT_DATA` WHERE UBICACION=13 AND CODE_CONJUNTO=2 AND ACTIVO=1"
        ).fetchone()[0]
        self.assertEqual(activos, 1)

        # MOT_LOG_RPL sigue siendo bitacora: anota la pieza que salio.
        bitacora = [dict(row) for row in conn.execute("SELECT * FROM MOT_LOG_RPL")]
        self.assertEqual(len(bitacora), 1)
        self.assertEqual(bitacora[0]["SERIAL"], "M-OLD")
        self.assertEqual(bitacora[0]["EQUIPO"], 1)

    def test_returning_part_is_reactivated_instead_of_duplicating_serial(self):
        # Una pieza reparada que vuelve a planta reutiliza su fila: la identidad
        # de la pieza es el SERIAL, asi que dos filas con el mismo serial serian
        # dos historiales distintos para un mismo motor.
        conn = self._fake_master_db(
            [
                {
                    "FECHA": "2025-01-10", "HORA": "08:00:00",
                    "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-ACTUAL",
                    "UBICACION": 13, "CODE_CONJUNTO": 2,
                    "ACTIVO": 1, "ESTADO": "INSTALADO",
                },
                {
                    "FECHA": "2024-05-02", "HORA": "07:00:00",
                    "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-VUELVE",
                    "UBICACION": 9, "CODE_CONJUNTO": 1,
                    "ACTIVO": 0, "ESTADO": "AVERIADO", "LOCALIZACION": "TALLER CENTRAL",
                    "VOLTAJE": "440",
                },
            ]
        )
        cursor = FakeMariaCursor(conn)

        result = apply_replacement_row(
            cursor,
            {
                "localizacion": 13,
                "code_conjunto": 2,
                "equipo": 1,
                "marca": "WEG",
                "modelo": "W22",
                "serial": "M-VUELVE",
                "estado_saliente": "DISPONIBLE",
                "sitio_saliente": "ALMACEN",
                "fecha": "2026-07-22",
                "hora": "11:00:00",
            },
        )

        self.assertEqual("updated", result)
        rows = self._motor_rows(conn)
        self.assertEqual(len(rows), 2)
        self.assertEqual(
            [row["SERIAL"] for row in rows].count("M-VUELVE"), 1
        )

        vuelve = next(row for row in rows if row["SERIAL"] == "M-VUELVE")
        self.assertEqual((vuelve["ACTIVO"], vuelve["ESTADO"]), (1, "INSTALADO"))
        self.assertEqual((vuelve["UBICACION"], vuelve["CODE_CONJUNTO"]), (13, 2))
        # Ya no esta en el taller: al volver a un equipo pierde el sitio.
        self.assertIsNone(vuelve["LOCALIZACION"])
        # Reactivar no le borra la placa tecnica que ya tenia.
        self.assertEqual(vuelve["VOLTAJE"], "440")

        # La que sale conserva su fila con el estado y el sitio que eligio el tecnico.
        sale = next(row for row in rows if row["SERIAL"] == "M-ACTUAL")
        self.assertEqual((sale["ACTIVO"], sale["ESTADO"]), (0, "DISPONIBLE"))
        self.assertEqual(sale["LOCALIZACION"], "ALMACEN")

    # ── Ordenes de reparacion de componentes ──────────────────────────────
    #
    # Una orden saca UNA pieza a un taller. Mientras vive, la pieza queda EN
    # REPARACION; al cerrar, el RESULTADO decide con que estatus vuelve al
    # inventario. Nada de esto puede tocar ACTIVO ni UBICACION: que una pieza
    # este montada en un equipo lo decide unicamente el reemplazo.

    def _maestra_con_pieza_retirada(self, **extra):
        base = {
            "FECHA": "2026-01-10", "HORA": "08:00:00",
            "MARCA": "WEG", "MODELO": "W22", "SERIAL": "M-TALLER",
            "UBICACION": 13, "CODE_CONJUNTO": 2,
            "ACTIVO": 0, "ESTADO": "AVERIADO", "LOCALIZACION": "ALMACEN PRINCIPAL",
            "VOLTAJE": "440",
        }
        base.update(extra)
        return self._fake_master_db([base])

    def _ordenes(self, conn):
        return [
            dict(row)
            for row in conn.execute("SELECT * FROM MOT_ORD_REP ORDER BY ID")
        ]

    def _fila_orden(self, **extra):
        fila = {
            "uuid": "ord-1",
            "tipo": 1,
            "serial": "M-TALLER",
            "marca": "WEG",
            "modelo": "W22",
            "ubicacion_origen": 13,
            "destino": "TALLER ELECTRICO",
            "motivo": "Rodamiento trabado",
            "fecha_salida": "2026-08-01",
            "hora_salida": "09:00:00",
            "usuario_salida": "JPEREZ",
            "cargo_salida": "MECANICO",
            "odt": 4321,
            "estado_orden": "ABIERTA",
        }
        fila.update(extra)
        return fila

    def test_orden_reparacion_abierta_deja_la_pieza_en_reparacion(self):
        conn = self._maestra_con_pieza_retirada()
        cursor = FakeMariaCursor(conn)

        self.assertEqual("created", apply_orden_reparacion(cursor, self._fila_orden()))

        ordenes = self._ordenes(conn)
        self.assertEqual(len(ordenes), 1)
        self.assertEqual(ordenes[0]["UUID"], "ord-1")
        self.assertEqual(ordenes[0]["ESTADO_ORDEN"], "ABIERTA")
        self.assertEqual(ordenes[0]["DESTINO"], "TALLER ELECTRICO")
        self.assertEqual(ordenes[0]["ODT"], 4321)
        # EQUIPO es TEXT en MOT_ORD_REP, igual que en MOT_LOG_RPL.
        self.assertEqual(ordenes[0]["EQUIPO"], "1")

        pieza = self._motor_rows(conn)[0]
        self.assertEqual(pieza["ESTADO"], "EN REPARACION")
        # El inventario debe poder decir en que taller esta sin abrir la orden.
        self.assertEqual(pieza["LOCALIZACION"], "TALLER ELECTRICO")
        # Una orden no monta ni desmonta nada: ACTIVO y UBICACION son del reemplazo.
        self.assertEqual((pieza["ACTIVO"], pieza["UBICACION"]), (0, 13))
        # Tampoco es una permuta, asi que la bitacora de reemplazos no se toca.
        self.assertEqual(list(conn.execute("SELECT * FROM MOT_LOG_RPL")), [])

    def test_cierre_reparado_deja_la_pieza_disponible(self):
        conn = self._maestra_con_pieza_retirada()
        cursor = FakeMariaCursor(conn)
        apply_orden_reparacion(cursor, self._fila_orden())

        # La tablet reenvia la MISMA orden ya cerrada: es un UPSERT por UUID,
        # no puede quedar una segunda orden para la misma salida de la pieza.
        outcome = apply_orden_reparacion(
            cursor,
            self._fila_orden(
                estado_orden="CERRADA",
                fecha_retorno="2026-08-09",
                hora_retorno="15:30:00",
                usuario_cierre="LGOMEZ",
                cargo_cierre="SUPERVISOR",
                trabajo_realizado="Cambio de rodamientos",
                resultado="REPARADO",
                ubicacion_final="ALMACEN DE MOTORES",
            ),
        )

        self.assertEqual("updated", outcome)
        ordenes = self._ordenes(conn)
        self.assertEqual(len(ordenes), 1)
        self.assertEqual(ordenes[0]["ESTADO_ORDEN"], "CERRADA")
        self.assertEqual(ordenes[0]["RESULTADO"], "REPARADO")
        self.assertEqual(ordenes[0]["FECHA_RETORNO"], "2026-08-09")
        self.assertEqual(ordenes[0]["USUARIO_CIERRE"], "LGOMEZ")
        # Los datos de salida siguen ahi: el cierre no borra como salio la pieza.
        self.assertEqual(ordenes[0]["FECHA_SALIDA"], "2026-08-01")
        self.assertEqual(ordenes[0]["MOTIVO"], "Rodamiento trabado")

        pieza = self._motor_rows(conn)[0]
        self.assertEqual(pieza["ESTADO"], "DISPONIBLE")
        self.assertEqual(pieza["LOCALIZACION"], "ALMACEN DE MOTORES")
        self.assertEqual((pieza["ACTIVO"], pieza["UBICACION"]), (0, 13))
        # Reparar no le inventa ni le borra la placa tecnica.
        self.assertEqual(pieza["VOLTAJE"], "440")

    def test_cierre_no_reparable_deja_la_pieza_desechada(self):
        conn = self._maestra_con_pieza_retirada()
        cursor = FakeMariaCursor(conn)

        outcome = apply_orden_reparacion(
            cursor,
            self._fila_orden(
                uuid="ord-2",
                estado_orden="CERRADA",
                fecha_retorno="2026-08-09",
                hora_retorno="16:00:00",
                resultado="NO REPARABLE",
                ubicacion_final="ALMACEN PRINCIPAL",
            ),
        )

        # La tablet pudo abrir Y cerrar la orden sin señal: llega ya cerrada.
        self.assertEqual("created", outcome)
        self.assertEqual(self._ordenes(conn)[0]["ESTADO_ORDEN"], "CERRADA")
        pieza = self._motor_rows(conn)[0]
        self.assertEqual(pieza["ESTADO"], "DESECHADO")
        self.assertEqual(pieza["LOCALIZACION"], "ALMACEN PRINCIPAL")

    def test_cierre_sin_intervencion_devuelve_la_pieza_averiada(self):
        conn = self._maestra_con_pieza_retirada()
        cursor = FakeMariaCursor(conn)

        apply_orden_reparacion(
            cursor,
            self._fila_orden(
                uuid="ord-3",
                estado_orden="CERRADA",
                resultado="SIN INTERVENCION",
                ubicacion_final="ALMACEN DE MOTORES",
            ),
        )

        # El taller no la toco: vuelve averiada, no disponible.
        self.assertEqual(self._motor_rows(conn)[0]["ESTADO"], "AVERIADO")

    def test_orden_reparacion_rechaza_pieza_instalada(self):
        # Una pieza montada no puede estar en el taller a la vez. Retirarla es
        # trabajo del reemplazo, y solo el reemplazo mueve ACTIVO.
        conn = self._maestra_con_pieza_retirada(ACTIVO=1, ESTADO="INSTALADO")
        cursor = FakeMariaCursor(conn)

        with self.assertRaises(ValueError) as ctx:
            apply_orden_reparacion(cursor, self._fila_orden())

        self.assertIn("reemplazo", str(ctx.exception))
        # La orden se valida antes de escribir: no queda a medias en la base.
        self.assertEqual(self._ordenes(conn), [])
        pieza = self._motor_rows(conn)[0]
        self.assertEqual((pieza["ACTIVO"], pieza["ESTADO"]), (1, "INSTALADO"))

    def test_orden_reparacion_rechaza_resultado_y_destino_invalidos(self):
        conn = self._maestra_con_pieza_retirada()

        with self.assertRaises(ValueError):
            apply_orden_reparacion(
                FakeMariaCursor(conn), self._fila_orden(destino="TALLER DE LA ESQUINA")
            )
        # Cerrar sin un resultado valido dejaria a la pieza sin estatus real.
        with self.assertRaises(ValueError):
            apply_orden_reparacion(
                FakeMariaCursor(conn),
                self._fila_orden(estado_orden="CERRADA", resultado=""),
            )
        self.assertEqual(self._ordenes(conn), [])
        self.assertEqual(self._motor_rows(conn)[0]["ESTADO"], "AVERIADO")

    def test_cola_local_de_ordenes_reparacion_solo_devuelve_pendientes(self):
        ensure_ordenes_reparacion_schema(self.conn)
        self.conn.executemany(
            """
            INSERT INTO ORDENES_REPARACION_LOCAL
              (uuid, tipo, serial, destino, estado_orden, sincronizado, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ("o-1", 1, "M-1", "TALLER ELECTRICO", "ABIERTA", 0, "2026-08-01 09:00:00"),
                ("o-2", 2, "B-1", "TALLER EXTERNO", "CERRADA", 1, "2026-08-02 09:00:00"),
                ("o-3", 1, "M-2", "TALLER MECANICO", "ABIERTA", 0, "2026-07-30 09:00:00"),
            ],
        )
        self.conn.commit()

        pendientes = fetch_pending_ordenes_reparacion(self.db_path)
        # Las ya sincronizadas no se reenvian y las viejas suben primero.
        self.assertEqual([row["uuid"] for row in pendientes], ["o-3", "o-1"])

        mark_orden_reparacion_result(
            self.db_path, "o-1", synced=False, error="pieza instalada"
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM ORDENES_REPARACION_LOCAL WHERE uuid='o-1'"
            ).fetchone(),
            (0, "pieza instalada"),
        )
        mark_orden_reparacion_result(self.db_path, "o-1", synced=True)
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM ORDENES_REPARACION_LOCAL WHERE uuid='o-1'"
            ).fetchone(),
            (1, None),
        )

    @patch("tablet_uploader.upload_pending_temperatures")
    @patch("tablet_uploader.upload_pending_replacements")
    @patch("tablet_uploader.upload_pending")
    @patch("tablet_uploader.connect_mariadb")
    def test_las_ordenes_de_reparacion_entran_en_la_subida_completa(
        self, connect, upload_measurements, upload_replacements, upload_temperatures
    ):
        vacio = UploadSummary()
        upload_measurements.return_value = vacio
        upload_replacements.return_value = vacio
        upload_temperatures.return_value = vacio
        ensure_ordenes_reparacion_schema(self.conn)
        self.conn.execute(
            """
            INSERT INTO ORDENES_REPARACION_LOCAL
              (uuid, tipo, serial, destino, estado_orden, sincronizado)
            VALUES ('o-9', 1, 'M-9', 'TALLER EXTERNO', 'ABIERTA', 0)
            """
        )
        self.conn.commit()
        connect.side_effect = RuntimeError("sin red")

        summary = upload_pending_work(self.db_path, log=lambda *_: None)

        # La orden pendiente cuenta en el resumen general: sin engancharla en
        # upload_pending_work se quedaria para siempre en la tablet.
        self.assertEqual((summary.total, summary.failed), (1, 1))
        self.assertEqual(
            self.conn.execute(
                "SELECT sincronizado, error_sync FROM ORDENES_REPARACION_LOCAL WHERE uuid='o-9'"
            ).fetchone(),
            (0, "sin red"),
        )

    def test_marks_every_component_in_replacement_operation_as_synced(self):
        mark_replacement_operation_result(
            self.db_path,
            "op-1",
            synced=True,
        )
        rows = self.conn.execute(
            """
            SELECT sincronizado, error_sync
            FROM REEMPLAZOS_LOCAL
            WHERE operation_uuid = 'op-1'
            ORDER BY uuid
            """
        ).fetchall()

        self.assertEqual(rows, [(1, None), (1, None)])

    def test_tablet_connection_status_reports_online_only_for_ready_device(self):
        self.assertEqual(tablet_connection_status([]), ("OFFLINE", "Tablet no conectada"))
        self.assertEqual(
            tablet_connection_status([Device("TAB1", "unauthorized")]),
            ("OFFLINE", "Tablet sin autorizar: acepte Permitir depuracion USB"),
        )
        self.assertEqual(
            tablet_connection_status([Device("TAB1", "device")]),
            ("ONLINE", "TAB1"),
        )

    def test_update_shared_prefs_xml_writes_flutter_usb_status_keys(self):
        updated = update_shared_prefs_xml(
            "<map><string name=\"flutter.username\">admin</string></map>",
            {
                "flutter.usb_sync_status": "ONLINE",
                "flutter.usb_sync_serial": "TAB1",
                "flutter.usb_sync_detail": "Laptop conectada",
                "flutter.usb_sync_last_seen": "2026-07-06T09:30:00",
            },
        )

        self.assertIn('name="flutter.username"', updated)
        self.assertIn('name="flutter.usb_sync_status">ONLINE</string>', updated)
        self.assertIn('name="flutter.usb_sync_serial">TAB1</string>', updated)

    def test_usb_status_json_contract_matches_flutter_reader(self):
        payload = {
            "status": "ONLINE",
            "serial": "TAB1",
            "detail": "Laptop conectada",
            "last_seen": "2026-07-06T09:30:00",
        }

        encoded = json.dumps(payload, ensure_ascii=False)
        decoded = json.loads(encoded)

        self.assertEqual(decoded["status"], "ONLINE")
        self.assertEqual(decoded["serial"], "TAB1")
        self.assertEqual(decoded["last_seen"], "2026-07-06T09:30:00")


class CursorConWithGlobal(FakeMariaCursor):
    """El cursor falso como context manager, igual que el de pymysql."""

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class MariaFalsa:
    """Conexion MariaDB de mentira sobre una SQLite en memoria."""

    def __init__(self, conn, cursor_cls=CursorConWithGlobal):
        self._conn = conn
        self.cur = cursor_cls(conn)

    def cursor(self):
        return self.cur

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        pass


class PruebasAdversariasTests(unittest.TestCase):
    """Casos limite pensados para romper la purga, las bajadas y el reporte.

    Aqui no hay caminos felices: valores numericos con decimales, tablas que
    no existen, uuid vacios y fechas imposibles. Lo que la planta real va a
    tirar tarde o temprano.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp.name) / "scv_ptbg.db"
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def _maria_purga_minima(self, loc_planta_sql="INSERT INTO MOT_EQUIPO VALUES (48)"):
        """MariaDB minima para que la purga no se cancele: solo el maestro.

        Las tablas MOT_* de uuids y seriales se dejan fuera a proposito: la
        purga las tolera ausentes y asi cada prueba crea solo lo que estresa.
        """
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute("CREATE TABLE MOT_EQUIPO (LOCALIZACION INTEGER)")
        if loc_planta_sql:
            maria.execute(loc_planta_sql)
        return maria

    # ------------------------------------------------------------------
    # Purga: LOCALIZACION numerica con decimales en MariaDB
    # ------------------------------------------------------------------

    def test_purga_localizacion_decimal_conserva_equipo_vivo(self):
        # REGRESION: sync_purge_deleted_from_mariadb (tablet_uploader.py, funcion
        # columna() ~linea 4212 + DELETE con CAST ~linea 4305) compara texto
        # contra texto sin normalizar el numero. Si la columna LOCALIZACION de
        # MOT_EQUIPO es DECIMAL o FLOAT, pymysql devuelve Decimal('48.0') o
        # 48.0 y str() produce "48.0"; el lado local hace
        # CAST(LOCALIZACION AS TEXT) sobre un INTEGER y produce "48".
        # "48" != "48.0" y el equipo VIVO se borra de la tablet junto con su
        # ficha tecnica. Gravedad ALTA: la purga destruye el catalogo entero
        # de equipos con solo cambiar el tipo de la columna en la planta.
        # Reproducir: MOT_EQUIPO.LOCALIZACION REAL con 48.0 y EQUIPOS local
        # con 48; tras la purga EQUIPOS queda vacia.
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        # REAL en SQLite juega el papel de DECIMAL/FLOAT en MariaDB: el
        # fetchall entrega 48.0 (float), igual que pymysql con esos tipos.
        maria.execute("CREATE TABLE MOT_EQUIPO (LOCALIZACION REAL)")
        maria.execute("INSERT INTO MOT_EQUIPO VALUES (48.0)")

        self.conn.execute("CREATE TABLE EQUIPOS (LOCALIZACION INTEGER, EQUIPO TEXT)")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (48, 'VIVO EN PLANTA')")
        self.conn.execute("CREATE TABLE EQUIPO_INFO (localizacion INTEGER)")
        self.conn.execute("INSERT INTO EQUIPO_INFO VALUES (48)")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        # El equipo sigue vivo en la planta: no puede desaparecer de la
        # tablet solo porque el numero viajo con ".0" pegado.
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM EQUIPOS").fetchone()[0], 1
        )
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM EQUIPO_INFO").fetchone()[0], 1
        )

    # ------------------------------------------------------------------
    # Purga: tabla MOT_* ausente en MariaDB
    # ------------------------------------------------------------------

    def test_purga_salta_tabla_uuid_ausente_pero_purga_el_resto(self):
        """Si MOT_LUB_REG no existe (planta con esquema viejo), la purga no
        puede saber que lubricaciones siguen vivas: esa tabla local se deja
        en paz. Pero las mediciones, cuya tabla remota SI se leyo, se purgan
        igual. Un fallo parcial no congela toda la limpieza."""
        maria = self._maria_purga_minima()
        maria.execute("CREATE TABLE MOT_VIBR_MUES (UUID TEXT)")
        maria.execute("INSERT INTO MOT_VIBR_MUES VALUES ('u-viva')")
        # MOT_LUB_REG no se crea: el SELECT sobre ella revienta.

        self.conn.execute(
            "CREATE TABLE MEDICIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        self.conn.execute("INSERT INTO MEDICIONES_LOCAL VALUES ('u-viva', 48, 1)")
        self.conn.execute("INSERT INTO MEDICIONES_LOCAL VALUES ('u-borrada', 48, 1)")
        self.conn.execute(
            "CREATE TABLE LUBRICACIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        # Sincronizada y sin espejo legible en MariaDB: en la duda, se queda.
        self.conn.execute("INSERT INTO LUBRICACIONES_LOCAL VALUES ('lub-huerfana', 48, 1)")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        mediciones = {
            r[0] for r in self.conn.execute("SELECT uuid FROM MEDICIONES_LOCAL")
        }
        self.assertEqual(mediciones, {"u-viva"})
        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM LUBRICACIONES_LOCAL").fetchone()[0],
            1,
        )

    def test_purga_con_catalogo_ilegible_conserva_piezas_vivas(self):
        # REGRESION: sync_purge_deleted_from_mariadb (tablet_uploader.py ~linea
        # 4246-4255 y 4333-4339) junta los seriales de MOT_DATA, MOT_BOMB_DATA,
        # MOT_CAJA_DATA, MOT_VENT_DATA y MOT_LOG_RPL en UN solo conjunto. Si
        # una de esas tablas no se puede leer (no existe, permiso, etc.) se
        # salta con un log... pero el conjunto queda PARCIAL y sigue no-vacio,
        # asi que el DELETE de CATALOGO_COMPONENTES borra todas las piezas del
        # catalogo ilegible aunque esten vivas en la planta. La proteccion de
        # "conjunto vacio = no borrar" solo cubre el caso de que fallen TODAS.
        # Gravedad MEDIA-ALTA: perder MOT_DATA un dia vacia el inventario de
        # motores de la tablet. Reproducir: MariaDB sin MOT_DATA pero con
        # MOT_BOMB_DATA poblada; la pieza tipo motor desaparece del catalogo.
        maria = self._maria_purga_minima()
        maria.execute("CREATE TABLE MOT_BOMB_DATA (SERIAL TEXT)")
        maria.execute("INSERT INTO MOT_BOMB_DATA VALUES ('B-VIVA')")
        # MOT_DATA (motores) no existe: sus seriales no se pudieron leer.

        self.conn.execute(
            "CREATE TABLE CATALOGO_COMPONENTES (tipo INTEGER, serial TEXT)"
        )
        self.conn.execute("INSERT INTO CATALOGO_COMPONENTES VALUES (1, 'M-VIVA')")
        self.conn.execute("INSERT INTO CATALOGO_COMPONENTES VALUES (2, 'B-VIVA')")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        seriales = {
            r[0] for r in self.conn.execute("SELECT serial FROM CATALOGO_COMPONENTES")
        }
        # El motor M-VIVA esta vivo: que su catalogo no se haya podido leer
        # no es prueba de que lo borraran en la planta.
        self.assertEqual(seriales, {"M-VIVA", "B-VIVA"})

    # ------------------------------------------------------------------
    # Purga: uuid NULL o vacio en filas locales ya sincronizadas
    # ------------------------------------------------------------------

    def test_purga_fila_sincronizada_con_uuid_null_sobrevive(self):
        """Una fila legado sin uuid no se puede verificar contra MariaDB.
        Con uuid NULL el `uuid NOT IN (...)` de SQL evalua a NULL y el DELETE
        no la toca: comportamiento conservador correcto (de chiripa, pero
        correcto). Esta prueba lo clava para que nadie lo rompa "arreglando"
        el NULL con un COALESCE."""
        maria = self._maria_purga_minima()
        maria.execute("CREATE TABLE MOT_VIBR_MUES (UUID TEXT)")
        maria.execute("INSERT INTO MOT_VIBR_MUES VALUES ('u-viva')")

        self.conn.execute(
            "CREATE TABLE MEDICIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        self.conn.execute("INSERT INTO MEDICIONES_LOCAL VALUES (NULL, 48, 1)")
        self.conn.execute("INSERT INTO MEDICIONES_LOCAL VALUES ('u-viva', 48, 1)")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM MEDICIONES_LOCAL").fetchone()[0],
            2,
        )

    def test_purga_fila_sincronizada_con_uuid_vacio_sobrevive(self):
        # REGRESION: sync_purge_deleted_from_mariadb (tablet_uploader.py ~linea
        # 4327-4331). Una fila local sincronizada con uuid = '' (cadena vacia,
        # tipico de datos migrados de versiones sin uuid) SI se borra: '' es
        # comparable y nunca esta en _PURGA_VIVOS porque columna() descarta
        # los vacios. Igual que con NULL, esa fila no se puede verificar
        # contra MariaDB, asi que borrarla es perder historial local sin
        # evidencia de que lo borraran en la planta. Ademas queda la
        # inconsistencia: NULL sobrevive y '' muere, dos formas del mismo
        # "sin uuid" con destinos opuestos. Gravedad MEDIA: solo afecta filas
        # legado, pero la perdida es silenciosa e irreversible.
        # Reproducir: fila con uuid='' y sincronizado=1; tras la purga ya no
        # esta, aunque MariaDB no diga nada de ella.
        maria = self._maria_purga_minima()
        maria.execute("CREATE TABLE MOT_VIBR_MUES (UUID TEXT)")
        maria.execute("INSERT INTO MOT_VIBR_MUES VALUES ('u-viva')")

        self.conn.execute(
            "CREATE TABLE MEDICIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        self.conn.execute("INSERT INTO MEDICIONES_LOCAL VALUES ('', 48, 1)")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        self.assertEqual(
            self.conn.execute("SELECT COUNT(*) FROM MEDICIONES_LOCAL").fetchone()[0],
            1,
        )

    # ------------------------------------------------------------------
    # Purga: la ficha tecnica del alta de campo pendiente
    # ------------------------------------------------------------------

    def test_purga_respeta_ficha_del_equipo_protegido_por_alta_pendiente(self):
        """El alta de campo pendiente protege a su equipo en EQUIPOS; su
        ficha en EQUIPO_INFO debe gozar de la misma proteccion, porque la
        purga de fichas reutiliza la misma tabla temporal de vivos."""
        maria = self._maria_purga_minima()

        self.conn.execute("CREATE TABLE EQUIPOS (LOCALIZACION INTEGER)")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (48)")
        self.conn.execute("INSERT INTO EQUIPOS VALUES (90)")
        self.conn.execute("CREATE TABLE EQUIPO_INFO (localizacion INTEGER)")
        # La ficha del alta de campo (90) y una ficha huerfana de verdad (57).
        self.conn.execute("INSERT INTO EQUIPO_INFO VALUES (90)")
        self.conn.execute("INSERT INTO EQUIPO_INFO VALUES (57)")
        self.conn.execute(
            "CREATE TABLE EQUIPOS_NUEVOS_LOCAL (uuid TEXT, localizacion INTEGER, "
            "sincronizado INTEGER DEFAULT 0)"
        )
        self.conn.execute("INSERT INTO EQUIPOS_NUEVOS_LOCAL VALUES ('n-1', 90, 0)")
        self.conn.commit()

        with patch("tablet_uploader.connect_mariadb", return_value=MariaFalsa(maria)):
            sync_purge_deleted_from_mariadb(self.db_path, log=lambda _: None)

        equipos = {r[0] for r in self.conn.execute("SELECT LOCALIZACION FROM EQUIPOS")}
        self.assertEqual(equipos, {48, 90})
        fichas = {r[0] for r in self.conn.execute("SELECT localizacion FROM EQUIPO_INFO")}
        # La ficha del alta pendiente vive; la del equipo 57, que no existe
        # ni en planta ni como alta pendiente, se va.
        self.assertEqual(fichas, {90})

    # ------------------------------------------------------------------
    # Reporte: claves de historial con fechas y horas rotas
    # ------------------------------------------------------------------

    def test_clave_historial_hora_vacia_y_fechas_imposibles(self):
        # Hora vacia: la fila vale, solo que ordena al inicio del dia.
        self.assertEqual(
            _clave_historial({"fecha": "2026-08-25", "hora": ""}),
            "2026-08-25T00:00:00",
        )
        # 29/02/2026 no existe en el calendario (2026 no es bisiesto), pero
        # la clave solo valida rangos (dia<=31, mes<=12): produce un texto
        # ordenable entre el 28/02 y el 01/03, que es lo que el orden
        # necesita. Se documenta el comportamiento, no es un fallo.
        self.assertEqual(
            _clave_historial({"fecha": "29/02/2026", "hora": "10:00"}),
            "2026-02-29T10:00:00",
        )
        # 99/99/9999 esta fuera de todo rango: cae a la clave del epoch y la
        # fila se hunde al final del historial en vez de flotar arriba.
        self.assertEqual(
            _clave_historial({"fecha": "99/99/9999", "hora": "10:00"}),
            "0000-01-01T00:00:00",
        )
        # Basura total en fecha y hora tampoco revienta.
        self.assertEqual(
            _clave_historial({"fecha": "sin fecha", "hora": "mediodia"}),
            "0000-01-01T00:00:00",
        )

    def test_rows_no_colapsa_filas_que_difieren_en_un_segundo(self):
        """El dedupe agrupa por instante exacto. Dos capturas a un segundo de
        distancia son mediciones distintas y las DOS deben salir, sin que la
        remota le pegue sus campos a la local ajena."""
        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        db.execute(
            "CREATE TABLE MEDICIONES_LOCAL (uuid TEXT, localizacion INTEGER, "
            "fecha TEXT, hora TEXT, observaciones TEXT)"
        )
        db.execute(
            "CREATE TABLE MEDICIONES_REMOTAS (remote_key TEXT, localizacion INTEGER, "
            "fecha TEXT, hora TEXT, fecha_hora_iso TEXT, equipo TEXT)"
        )
        db.execute(
            "INSERT INTO MEDICIONES_LOCAL VALUES "
            "('u-a', 39, '2026-08-25', '08:15:07', 'obs local')"
        )
        db.execute(
            "INSERT INTO MEDICIONES_REMOTAS VALUES "
            "('ID:9', 39, '25/08/2026', '08:15:08', '2026-08-25T08:15:08', 'BOMBA')"
        )
        db.commit()

        rows = report_rows(db, ("MEDICIONES_LOCAL", "MEDICIONES_REMOTAS"), 39)

        self.assertEqual(len(rows), 2)
        # La remota (08:15:08) es mas nueva y va primero.
        self.assertEqual(
            [r.get("uuid") or r.get("remote_key") for r in rows],
            ["ID:9", "u-a"],
        )
        # Nada de la remota se filtro a la local: son instantes distintos.
        self.assertIn(rows[1].get("equipo"), (None, ""))
        self.assertEqual(rows[1]["observaciones"], "obs local")

    # ------------------------------------------------------------------
    # Bajada de lubricacion: fila sin ID en MariaDB
    # ------------------------------------------------------------------

    @patch("tablet_uploader.connect_mariadb")
    def test_lubricacion_sin_id_usa_clave_alternativa_y_colapsa_gemelas(self, connect):
        """Una vista o una tabla legado puede venir sin columna ID: la fila
        baja igual con la clave LOC|FECHA|HORA. Dos filas identicas en ese
        trio colapsan en una por el INSERT OR REPLACE: consecuencia asumida
        de no tener ID, no perdida silenciosa de otra cosa."""
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row
        maria.execute(
            "CREATE TABLE MOT_LUB_REG (UUID TEXT, FECHA TEXT, HORA TEXT, "
            "SISTEMA TEXT, LOCALIZACION INTEGER, L1 REAL, OBSERVACIONES TEXT)"
        )
        maria.execute(
            "INSERT INTO MOT_LUB_REG VALUES "
            "('lub-a', '2026-08-03', '09:10:00', 'AGUA POTABLE', 2, 12.5, 'primera')"
        )
        maria.execute(
            "INSERT INTO MOT_LUB_REG VALUES "
            "('lub-b', '2026-08-03', '09:10:00', 'AGUA POTABLE', 2, 13.0, 'gemela')"
        )
        maria.execute(
            "INSERT INTO MOT_LUB_REG VALUES "
            "('lub-c', '2026-08-04', '10:00:00', 'AGUA POTABLE', 2, 9.0, 'otra')"
        )
        maria.commit()

        # El ORDER BY con STR_TO_DATE es de MariaDB y ademas pide ID, que
        # aqui no existe: se sustituye por la consulta plana.
        class CursorSinStrToDate(CursorConWithGlobal):
            def execute(self, sql, params=None):
                if "STR_TO_DATE" in sql:
                    sql = "SELECT * FROM MOT_LUB_REG LIMIT 500"
                return super().execute(sql, params)

        connect.return_value = MariaFalsa(maria, cursor_cls=CursorSinStrToDate)
        n = sync_lubrication_history_from_mariadb(self.db_path, log=lambda _: None)
        # La funcion reporta lo que leyo de MariaDB, no lo que sobrevivio al
        # colapso de claves.
        self.assertEqual(n, 3)

        filas = {
            fila[0]: fila
            for fila in self.conn.execute(
                "SELECT remote_key, localizacion, L1 FROM LUBRICACIONES_REMOTAS"
            )
        }
        # Sin ID la clave es LOC|FECHA|HORA; las dos gemelas comparten clave
        # y queda la ultima insertada.
        self.assertEqual(
            set(filas),
            {"LOC:2|2026-08-03|09:10:00", "LOC:2|2026-08-04|10:00:00"},
        )
        self.assertEqual(filas["LOC:2|2026-08-03|09:10:00"][2], 13.0)
        self.assertEqual(filas["LOC:2|2026-08-04|10:00:00"][1], 2)

    # ------------------------------------------------------------------
    # Bitacora del admin: MOT_LOG_ADM no existe en MariaDB
    # ------------------------------------------------------------------

    @patch("tablet_uploader.connect_mariadb")
    def test_admin_events_sin_tabla_destino_quedan_pendientes_con_error(self, connect):
        """Una planta con esquema viejo no tiene MOT_LOG_ADM. Cada evento
        falla POR FILA, queda pendiente con su error_sync, y la corrida no
        revienta: al dia siguiente, con la tabla creada, se reintenta."""
        ensure_admin_log_schema(self.conn)
        for uuid, hora in (("evt-a", "10:00:00"), ("evt-b", "10:05:00")):
            self.conn.execute(
                """INSERT INTO EVENTOS_ADMIN
                (uuid, fecha, hora, usuario, cargo, accion, servicio, localizacion)
                VALUES (?,?,?,?,?,?,?,?)""",
                (uuid, "2026-09-01", hora, "DANIEL BERRUETA", "ADMIN",
                 "EDICION", "vibracion", 48),
            )
        self.conn.commit()

        # MariaDB sin MOT_LOG_ADM: hasta el SELECT de duplicados revienta.
        maria = sqlite3.connect(":memory:")
        maria.row_factory = sqlite3.Row

        connect.return_value = MariaFalsa(maria)
        summary = upload_pending_admin_events(
            self.db_path, tablet="TAB-1", log=lambda _: None,
        )

        self.assertEqual((summary.uploaded, summary.failed), (0, 2))
        # Los dos siguen pendientes y con el error anotado para diagnostico.
        pendientes = fetch_pending_admin_events(self.db_path)
        self.assertEqual(sorted(r["uuid"] for r in pendientes), ["evt-a", "evt-b"])
        errores = [
            r[0] for r in self.conn.execute(
                "SELECT error_sync FROM EVENTOS_ADMIN ORDER BY uuid"
            )
        ]
        for error in errores:
            self.assertIn("MOT_LOG_ADM", error or "")


if __name__ == "__main__":
    unittest.main()
