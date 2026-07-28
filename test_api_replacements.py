import unittest

from Api_scv_ptbg import (
    ReplacementItem,
    ReplacementReq,
    _execute_replacements,
)


class FakeCursor:
    def __init__(self, current_rows):
        self.current_rows = current_rows
        self.calls = []
        self._row = None

    def execute(self, sql, params=None):
        normalized = " ".join(sql.split())
        self.calls.append((normalized, params))
        if normalized.startswith("SELECT ID, MARCA, MODELO, SERIAL FROM"):
            table = normalized.split("FROM `", 1)[1].split("`", 1)[0]
            self._row = self.current_rows.get(table)

    def fetchone(self):
        return self._row


class ReplacementTransactionTests(unittest.TestCase):
    def test_archives_old_data_before_updating_each_component(self):
        cursor = FakeCursor(
            {
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD MOTOR",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                },
                "MOT_BOMB_DATA": {
                    "ID": 20,
                    "MARCA": "OLD PUMP",
                    "MODELO": "P1",
                    "SERIAL": "PS1",
                },
            }
        )
        request = ReplacementReq(
            localizacion=2,
            code_conjunto=1,
            componentes=[
                ReplacementItem(
                    equipo=1, marca="WEG", modelo="W22", serial="NEW-M"
                ),
                ReplacementItem(
                    equipo=2, marca="KSB", modelo="ETA", serial="NEW-P"
                ),
            ],
        )

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        inserts = [call for call in cursor.calls if "INSERT INTO MOT_LOG_RPL" in call[0]]
        updates = [call for call in cursor.calls if call[0].startswith("UPDATE")]
        self.assertEqual(2, len(inserts))
        self.assertEqual(2, len(updates))
        self.assertEqual("OLD MOTOR", inserts[0][1][2])
        self.assertEqual(1, inserts[0][1][5])
        self.assertEqual("WEG", updates[0][1][2])
        self.assertEqual(2, result["actualizados"])

    def test_retry_with_same_current_data_does_not_duplicate_history(self):
        cursor = FakeCursor(
            {
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "WEG",
                    "MODELO": "W22",
                    "SERIAL": "NEW-M",
                }
            }
        )
        request = ReplacementReq(
            localizacion=2,
            code_conjunto=1,
            componentes=[
                ReplacementItem(
                    equipo=1, marca="WEG", modelo="W22", serial="NEW-M"
                )
            ],
        )

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        self.assertFalse(any("INSERT INTO MOT_LOG_RPL" in c[0] for c in cursor.calls))
        self.assertFalse(any(c[0].startswith("UPDATE") for c in cursor.calls))
        self.assertEqual(1, result["sin_cambios"])

    def test_first_load_creates_current_component_without_history(self):
        cursor = FakeCursor({"MOT_CAJA_DATA": None})
        request = ReplacementReq(
            localizacion=2,
            code_conjunto=1,
            componentes=[
                ReplacementItem(
                    equipo=3, marca="SEW", modelo="R97", serial="NEW-C"
                )
            ],
        )

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        current_inserts = [
            call
            for call in cursor.calls
            if call[0].startswith("INSERT INTO `MOT_CAJA_DATA`")
        ]
        self.assertEqual(1, len(current_inserts))
        self.assertFalse(any("INSERT INTO MOT_LOG_RPL" in c[0] for c in cursor.calls))
        self.assertEqual(1, result["creados"])


if __name__ == "__main__":
    unittest.main()
