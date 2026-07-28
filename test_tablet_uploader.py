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
)


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
                "FECHA", "HORA", "SISTEMA", "LOCALIZACION",
                "AMB_ANGULO_V", "AMB_ANGULO_H", "AMB_COMPENSACION_V", "AMB_COMPENSACION_H",
                "ACM_ANGULO_V", "ACM_ANGULO_H", "ACM_COMPENSACION_V", "ACM_COMPENSACION_H",
                "ACB_ANGULO_V", "ACB_ANGULO_H", "ACB_COMPENSACION_V", "ACB_COMPENSACION_H",
                "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
            ),
        )
        self.assertEqual(values[:8], ("2026-07-28", "10:15:00", "TURBINA BG-2", 13, -1.03, 0.05, 0.0, 2.5))
        self.assertEqual(values[8:16], (None,) * 8)
        self.assertEqual(values[-1], None)

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
                if compact.startswith("INSERT INTO MOT_ALN_REG") and params[1] == "10:15:00" and params[4] == -1.03:
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
                "FECHA", "HORA", "SISTEMA", "LOCALIZACION",
                "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10",
                "OBSERVACIONES", "USUARIO", "CARGO", "MARCA", "MODELO", "SERIAL", "ODT",
            ),
        )
        self.assertEqual(
            values,
            (
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
                elif compact.startswith("INSERT INTO MOT_TEMP_MUES") and params[1] == "11:30:00":
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

        self.assertEqual(values[0:4], ("2026-07-06", "09:00:00", "TURBINA BG-2", 13))
        self.assertEqual(values[4:7], (2.0, 3.0, 4.0))
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

    def test_motor_replacement_keeps_technical_data_when_user_says_no(self):
        class Cursor:
            def __init__(self):
                self.calls = []

            def execute(self, sql, params=None):
                self.calls.append((" ".join(sql.split()), params))

            def fetchone(self):
                return {
                    "ID": 9,
                    "MARCA": "WEG",
                    "MODELO": "OLD",
                    "SERIAL": "OLD-1",
                }

        cursor = Cursor()
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
                "fecha": "2026-07-22",
                "hora": "10:00:00",
            },
        )

        self.assertEqual("updated", result)
        update = next(
            call for call in cursor.calls if call[0].startswith("UPDATE `MOT_DATA`")
        )
        self.assertNotIn("VOLTAJE", update[0])
        self.assertNotIn("CORRIENTE", update[0])
        self.assertIn("MARCA", update[0])

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


if __name__ == "__main__":
    unittest.main()
