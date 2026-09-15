import unittest
from decimal import Decimal
from inspect import signature
from unittest.mock import patch

from pydantic import ValidationError

import Api_scv_ptbg as api


class FakeCursor:
    def __init__(self, rows=None, uuid_row=None):
        self.rows = list(rows or [])
        # La deduplicacion por UUID es una consulta aparte de la de
        # localizacion+fecha+hora. Sin separarlas, el fake devolveria la fila
        # preparada para la segunda y todo pareceria un reintento.
        self.uuid_row = uuid_row
        self.calls = []
        self.lastrowid = 77
        self._ultima_por_uuid = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, sql, params=None):
        normalizada = " ".join(sql.split())
        self.calls.append((normalizada, params))
        self._ultima_por_uuid = "WHERE UUID = %s" in normalizada

    def fetchall(self):
        return list(self.rows)

    def fetchone(self):
        if self._ultima_por_uuid:
            return self.uuid_row
        return self.rows[0] if self.rows else None


class FakeConnection:
    def __init__(self, rows=None, uuid_row=None):
        self.cursor_instance = FakeCursor(rows, uuid_row=uuid_row)
        self.committed = False
        self.rolled_back = False
        self.closed = False

    def cursor(self):
        return self.cursor_instance

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


def temperature_request(**overrides):
    values = {
        "uuid": "temp-1",
        "localizacion": 4,
        "sistema": "FIN-FAN",
        "fecha": "2026-07-22",
        "hora": "10:30:00",
        "T1": 41.5,
        "T10": 55.25,
        "OBSERVACIONES": "Correa estable",
        "USUARIO": "OPERADOR",
        "CARGO": "MECANICO",
        "MARCA": "WEG",
        "MODELO": "W22",
        "SERIAL": "ABC-1",
        "ODT": None,
    }
    values.update(overrides)
    return api.TemperatureReq(**values)


class TemperatureApiTests(unittest.TestCase):
    def test_request_rejects_non_positive_location(self):
        with self.assertRaises(ValidationError):
            temperature_request(localizacion=0)

    def test_request_defaults_missing_and_null_temperatures_to_zero(self):
        request = temperature_request(T2=None)

        self.assertEqual(0.0, request.T2)
        self.assertEqual(0.0, request.T9)

    def test_insert_uses_mot_temp_column_order_and_nullable_odt(self):
        db = FakeConnection()
        with patch.object(api, "get_db", return_value=db):
            result = api.insert_temperature(temperature_request(), payload={})

        sql, params = db.cursor_instance.calls[-1]
        self.assertIn("INSERT INTO MOT_TEMP_MUES", sql)
        expected_columns = (
            "UUID,FECHA,HORA,SISTEMA,LOCALIZACION,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,"
            "OBSERVACIONES,USUARIO,CARGO,MARCA,MODELO,SERIAL,ODT"
        )
        self.assertIn(expected_columns, sql.replace(" ", ""))
        # UUID va primero: identifica la medicion para que un reintento no la
        # duplique. El resto de los valores corre una posicion.
        self.assertEqual("temp-1", params[0])
        self.assertEqual("2026-07-22", params[1])
        self.assertEqual(41.5, params[5])
        self.assertEqual(0.0, params[6])
        self.assertEqual(55.25, params[14])
        self.assertIsNone(params[-1])
        self.assertTrue(db.committed)
        self.assertEqual({"status": "ok", "uuid": "temp-1", "id": 77}, result)

    def test_insert_retry_skips_existing_location_date_and_time(self):
        db = FakeConnection([{
            "ID": 55,
            "SISTEMA": " FIN-FAN ",
            "T1": Decimal("41.50"),
            "T2": Decimal("0.00"),
            "T3": Decimal("0.00"),
            "T4": Decimal("0.00"),
            "T5": Decimal("0.00"),
            "T6": Decimal("0.00"),
            "T7": Decimal("0.00"),
            "T8": Decimal("0.00"),
            "T9": Decimal("0.00"),
            "T10": Decimal("55.25"),
            "OBSERVACIONES": "Correa estable",
            "USUARIO": "operador",
            "CARGO": "MECANICO",
            "MARCA": "WEG",
            "MODELO": "W22",
            "SERIAL": "ABC-1",
            "ODT": None,
        }])
        with patch.object(api, "get_db", return_value=db):
            result = api.insert_temperature(temperature_request(), payload={})

        self.assertEqual("skipped", result["status"])
        self.assertEqual("already_exists", result["reason"])
        self.assertEqual(55, result["id"])
        # +1 consulta: la deduplicacion por UUID va antes que la de fecha/hora.
        self.assertEqual(2, len(db.cursor_instance.calls))
        sql, params = next(
            c for c in db.cursor_instance.calls if "LOCALIZACION = %s" in c[0]
        )
        self.assertIn("FROM MOT_TEMP_MUES", sql)
        self.assertIn("LOCALIZACION = %s", sql)
        self.assertIn("FECHA = %s", sql)
        self.assertIn("HORA = %s", sql)
        self.assertEqual((4, "2026-07-22", "10:30:00"), params)
        self.assertFalse(db.committed)

    def test_same_timestamp_with_different_temperature_inserts_new_row(self):
        db = FakeConnection([{
            "ID": 55,
            "SISTEMA": "FIN-FAN",
            "T1": Decimal("40.00"),
            "T10": Decimal("55.25"),
            "OBSERVACIONES": "Correa estable",
            "USUARIO": "OPERADOR",
            "CARGO": "MECANICO",
            "MARCA": "WEG",
            "MODELO": "W22",
            "SERIAL": "ABC-1",
            "ODT": None,
        }])
        with patch.object(api, "get_db", return_value=db):
            result = api.insert_temperature(temperature_request(), payload={})

        self.assertEqual("ok", result["status"])
        self.assertTrue(db.committed)
        # +1 consulta: la deduplicacion por UUID va antes que la de fecha/hora.
        self.assertEqual(3, len(db.cursor_instance.calls))
        insert_sql, _ = next(
            c for c in db.cursor_instance.calls if c[0].startswith("INSERT INTO")
        )
        self.assertIn("INSERT INTO MOT_TEMP_MUES", insert_sql)

    def test_latest_endpoint_orders_and_limits_in_sql(self):
        rows = [
            {"ID": 4, "LOCALIZACION": 4, "FECHA": "2026-07-22", "HORA": "09:00:00", "T1": Decimal("40.5")},
        ]
        db = FakeConnection(rows)
        with patch.object(api, "get_db", return_value=db):
            result = api.get_latest_temperature(4)

        self.assertEqual(4, result["ID"])
        self.assertEqual(40.5, result["T1"])
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("WHERE LOCALIZACION = %s", sql)
        self.assertIn("ORDER BY", sql)
        self.assertIn("ID DESC", sql)
        self.assertIn("LIMIT 1", sql)
        self.assertEqual((4,), params)

    def test_latest_rows_returns_one_json_mapped_row_per_location(self):
        rows = [
            {"ID": 2, "LOCALIZACION": 2, "FECHA": "2026-07-22", "HORA": "08:00:00", "T1": Decimal("39.5"), "ODT": None},
            {"ID": 3, "LOCALIZACION": 4, "FECHA": "2026-07-21", "HORA": "09:00:00", "T10": Decimal("52.25"), "ODT": 701},
        ]
        db = FakeConnection(rows)
        with patch.object(api, "get_db", return_value=db):
            result = api.get_latest_temperatures(limit=50)

        self.assertEqual([2, 4], [row["LOCALIZACION"] for row in result])
        self.assertEqual(39.5, result[0]["T1"])
        self.assertIsNone(result[0]["ODT"])
        self.assertEqual(52.25, result[1]["T10"])
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("ROW_NUMBER() OVER", sql)
        self.assertIn("PARTITION BY LOCALIZACION", sql)
        self.assertIn("WHERE rn = 1", sql)
        self.assertIn("LIMIT %s", sql)
        self.assertEqual((50,), params)

    def test_history_filters_orders_and_limits_in_sql(self):
        db = FakeConnection([
            {"ID": 8, "LOCALIZACION": 4, "FECHA": "2026-07-22", "HORA": "10:00:00", "T1": Decimal("42.0")},
        ])
        with patch.object(api, "get_db", return_value=db):
            result = api.get_temperatures(localizacion=4, limit=12, payload={})

        self.assertEqual(42.0, result[0]["T1"])
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("WHERE LOCALIZACION = %s", sql)
        self.assertIn("ORDER BY", sql)
        self.assertIn("ID DESC", sql)
        self.assertIn("LIMIT %s", sql)
        self.assertEqual((4, 12), params)

    def test_temperature_routes_are_registered(self):
        routes = {(route.path, method) for route in api.app.routes for method in getattr(route, "methods", set())}

        self.assertIn(("/temperaturas", "POST"), routes)
        self.assertIn(("/temperaturas", "GET"), routes)
        self.assertIn(("/temperaturas/ultimas", "GET"), routes)
        self.assertIn(("/temperaturas/ultima/{localizacion}", "GET"), routes)

    def test_latest_temperature_gets_require_token(self):
        latest_all_parameters = signature(api.get_latest_temperatures).parameters
        latest_one_parameters = signature(api.get_latest_temperature).parameters

        self.assertIn("payload", latest_all_parameters)
        self.assertIn("payload", latest_one_parameters)
        latest_all_dependency = latest_all_parameters["payload"].default.dependency
        latest_one_dependency = latest_one_parameters["payload"].default.dependency

        self.assertIs(api.verify_token, latest_all_dependency)
        self.assertIs(api.verify_token, latest_one_dependency)


class VibrationContractRegressionTests(unittest.TestCase):
    def test_single_latest_vibration_orders_by_id_and_limits_in_sql(self):
        db = FakeConnection([{"ID": 12, "LOCALIZACION": 4}])
        with patch.object(api, "get_db", return_value=db):
            result = api.get_ultima_medicion(4)

        self.assertEqual(12, result["ID"])
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("WHERE LOCALIZACION = %s", sql)
        self.assertIn("ORDER BY ID DESC", sql)
        self.assertIn("LIMIT 1", sql)
        self.assertEqual((4,), params)

    def test_global_latest_vibrations_order_and_limit_in_sql(self):
        rows = [
            {"ID": 20, "LOCALIZACION": 4},
            {"ID": 19, "LOCALIZACION": 4},
        ]
        db = FakeConnection(rows)
        with patch.object(api, "get_db", return_value=db):
            result = api.get_ultimas_mediciones(limit=2)

        self.assertEqual(rows, result)
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("ORDER BY ID DESC", sql)
        self.assertIn("LIMIT %s", sql)
        self.assertEqual((2,), params)


if __name__ == "__main__":
    unittest.main()
