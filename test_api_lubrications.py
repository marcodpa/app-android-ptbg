import unittest
from unittest.mock import patch

from pydantic import ValidationError

import Api_scv_ptbg as api


class FakeCursor:
    def __init__(self, rows=None):
        self.rows = list(rows or [])
        self.calls = []
        self.lastrowid = 91

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, sql, params=None):
        self.calls.append((" ".join(sql.split()), params))

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return list(self.rows)


class FakeConnection:
    def __init__(self, rows=None):
        self.cursor_instance = FakeCursor(rows)
        self.committed = False
        self.closed = False

    def cursor(self):
        return self.cursor_instance

    def commit(self):
        self.committed = True

    def rollback(self):
        pass

    def close(self):
        self.closed = True


def request(**overrides):
    values = {
        "uuid": "lub-1",
        "localizacion": 13,
        "sistema": "TURBINA BG-2",
        "fecha": "2026-07-29",
        "hora": "12:00:00",
        "L1": 12.5,
        "L2": 12.5,
        "L5": 20,
        "L6": 20,
        "OBSERVACIONES": "Trabajo completado",
        "USUARIO": "OPERADOR",
        "CARGO": "MECANICO",
        "MARCA": "WEG",
        "MODELO": "W22",
        "SERIAL": "M-13",
        "ODT": 701,
    }
    values.update(overrides)
    return api.LubricationReq(**values)


class LubricationApiTests(unittest.TestCase):
    def test_rejects_non_positive_location(self):
        with self.assertRaises(ValidationError):
            request(localizacion=0)

    def test_insert_uses_mot_lub_reg_and_l1_to_l9_order(self):
        db = FakeConnection()
        with patch.object(api, "get_db", return_value=db):
            result = api.insert_lubrication(request(), payload={})

        sql, params = db.cursor_instance.calls[-1]
        self.assertIn("INSERT INTO MOT_LUB_REG", sql)
        self.assertIn("L1,L2,L3,L4,L5,L6,L7,L8,L9", sql.replace(" ", ""))
        # El UUID es la primera columna: identifica la medicion para que un
        # reintento no la duplique. Por eso los valores van desde params[1].
        self.assertEqual("lub-1", params[0])
        self.assertEqual(12.5, params[5])
        self.assertIsNone(params[7])
        self.assertEqual(20, params[9])
        self.assertEqual(701, params[-1])
        self.assertTrue(db.committed)
        self.assertEqual({"status": "ok", "uuid": "lub-1", "id": 91}, result)

    def test_retry_skips_existing_timestamp(self):
        db = FakeConnection([{"ID": 81}])
        with patch.object(api, "get_db", return_value=db):
            result = api.insert_lubrication(request(), payload={})

        self.assertEqual("skipped", result["status"])
        self.assertEqual(81, result["id"])
        self.assertEqual(1, len(db.cursor_instance.calls))
        self.assertFalse(db.committed)

    def test_history_filters_location_and_limit(self):
        db = FakeConnection([{"ID": 1, "LOCALIZACION": 13, "L1": 12.5}])
        with patch.object(api, "get_db", return_value=db):
            rows = api.get_lubrications(
                localizacion=13,
                limit=25,
                payload={},
            )

        self.assertEqual(12.5, rows[0]["L1"])
        sql, params = db.cursor_instance.calls[0]
        self.assertIn("FROM MOT_LUB_REG", sql)
        self.assertIn("WHERE LOCALIZACION = %s", sql)
        self.assertEqual((13, 25), params)

    def test_routes_are_registered(self):
        routes = {
            (route.path, method)
            for route in api.app.routes
            for method in getattr(route, "methods", set())
        }
        self.assertIn(("/lubricaciones", "POST"), routes)
        self.assertIn(("/lubricaciones", "GET"), routes)


if __name__ == "__main__":
    unittest.main()
