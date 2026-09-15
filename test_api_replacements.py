"""Pruebas del reemplazo de componentes en la API.

Modelo vigente: las tablas maestras guardan UNA FILA POR PIEZA FISICA.
La pieza que sale conserva su fila con ACTIVO = 0 y el estatus que eligio el
tecnico; la que entra queda con ACTIVO = 1. Antes se sobrescribia la fila y la
pieza retirada desaparecia de la planta: eso es justo lo que estas pruebas
vigilan que no vuelva a pasar.
"""

import unittest

from Api_scv_ptbg import (
    ReplacementItem,
    ReplacementReq,
    _execute_replacements,
)


class FakeCursor:
    """Cursor de mentira que responde segun la forma de cada consulta.

    `instaladas` son las piezas activas por tabla (lo que hay puesto ahora).
    `por_serial` son las piezas que ya existen en la maestra, para probar la
    reactivacion de una pieza que vuelve a montarse.
    """

    def __init__(self, instaladas, por_serial=None, con_localizacion=False):
        self.instaladas = instaladas
        self.por_serial = por_serial or {}
        self.con_localizacion = con_localizacion
        self.calls = []
        self._row = None

    def execute(self, sql, params=None):
        normalized = " ".join(sql.split())
        self.calls.append((normalized, params))

        if "INFORMATION_SCHEMA.COLUMNS" in normalized:
            self._row = {"COLUMN_NAME": "LOCALIZACION"} if self.con_localizacion else None
            return

        if normalized.startswith("SELECT ID, MARCA, MODELO, SERIAL, FECHA FROM"):
            tabla = normalized.split("FROM `", 1)[1].split("`", 1)[0]
            self._row = self.instaladas.get(tabla)
            return

        if normalized.startswith("SELECT ID FROM `"):
            serial = (params or ("",))[0]
            self._row = self.por_serial.get(serial)
            return

        self._row = None

    def fetchone(self):
        return self._row

    # --- ayudas de lectura para las aserciones -------------------------------

    def updates(self):
        return [c for c in self.calls if c[0].startswith("UPDATE")]

    def bitacora(self):
        return [c for c in self.calls if "INSERT INTO MOT_LOG_RPL" in c[0]]

    def altas(self, tabla):
        return [c for c in self.calls if c[0].startswith(f"INSERT INTO `{tabla}`")]

    def retiros(self):
        return [c for c in self.updates() if "SET ACTIVO = 0" in c[0]]

    def instalaciones(self):
        return [c for c in self.updates() if "SET ACTIVO = 1" in c[0]]


def _peticion(componentes, **extra):
    return ReplacementReq(
        localizacion=2, code_conjunto=1, componentes=componentes, **extra
    )


class ReemplazoConservaLaPiezaRetirada(unittest.TestCase):
    def test_la_pieza_que_sale_no_se_borra_queda_inactiva(self):
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD MOTOR",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            }
        )
        request = _peticion([
            ReplacementItem(
                equipo=1,
                marca="WEG",
                modelo="W22",
                serial="NEW-M",
                estado_saliente="AVERIADO",
            )
        ])

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        retiros = cursor.retiros()
        self.assertEqual(1, len(retiros), "la pieza retirada debe desactivarse")
        self.assertIn("AVERIADO", retiros[0][1])
        self.assertEqual(10, retiros[0][1][-1], "debe desactivar la fila vieja")

        # La entrante no existia en la maestra: se da de alta.
        altas = cursor.altas("MOT_DATA")
        self.assertEqual(1, len(altas))
        self.assertIn("NEW-M", altas[0][1])

        self.assertEqual(1, len(cursor.bitacora()))
        self.assertEqual(1, result["actualizados"])

    def test_sin_estado_elegido_la_retirada_queda_disponible(self):
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            }
        )
        request = _peticion([
            ReplacementItem(equipo=1, marca="WEG", modelo="W22", serial="NEW-M")
        ])

        _execute_replacements(cursor, request, fecha="2026-07-21", hora="10:30:00")

        self.assertIn("DISPONIBLE", cursor.retiros()[0][1])

    def test_estado_invalido_no_se_escribe_tal_cual(self):
        """INSTALADO no puede colarse como estatus de una pieza retirada."""
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            }
        )
        request = _peticion([
            ReplacementItem(
                equipo=1,
                marca="WEG",
                modelo="W22",
                serial="NEW-M",
                estado_saliente="INSTALADO",
            )
        ])

        _execute_replacements(cursor, request, fecha="2026-07-21", hora="10:30:00")

        self.assertNotIn("INSTALADO", cursor.retiros()[0][1])
        self.assertIn("DISPONIBLE", cursor.retiros()[0][1])


class PiezaQueVuelveAMontarse(unittest.TestCase):
    def test_un_serial_ya_conocido_se_reactiva_no_se_duplica(self):
        """El serial identifica la pieza: una que vuelve reactiva su fila.

        Si se insertara una fila nueva, el mismo motor apareceria dos veces en
        el inventario y el serial dejaria de identificar una pieza.
        """
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            },
            por_serial={"VIEJO-CONOCIDO": {"ID": 77}},
        )
        request = _peticion([
            ReplacementItem(
                equipo=1, marca="WEG", modelo="W22", serial="viejo-conocido"
            )
        ])

        _execute_replacements(cursor, request, fecha="2026-07-21", hora="10:30:00")

        instalaciones = cursor.instalaciones()
        self.assertEqual(1, len(instalaciones))
        self.assertEqual(77, instalaciones[0][1][-1])
        self.assertEqual(
            0, len(cursor.altas("MOT_DATA")), "no debe insertarse una fila nueva"
        )


class CasosSinPermuta(unittest.TestCase):
    def test_reintento_con_los_mismos_datos_no_duplica_historia(self):
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "WEG",
                    "MODELO": "W22",
                    "SERIAL": "NEW-M",
                    "FECHA": "2026-01-01",
                }
            }
        )
        request = _peticion([
            ReplacementItem(equipo=1, marca="WEG", modelo="W22", serial="NEW-M")
        ])

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        self.assertEqual([], cursor.bitacora())
        self.assertEqual([], cursor.updates())
        self.assertEqual(1, result["sin_cambios"])

    def test_posicion_vacia_da_de_alta_sin_bitacora(self):
        cursor = FakeCursor(instaladas={"MOT_CAJA_DATA": None})
        request = _peticion([
            ReplacementItem(equipo=3, marca="SEW", modelo="R97", serial="NEW-C")
        ])

        result = _execute_replacements(
            cursor, request, fecha="2026-07-21", hora="10:30:00"
        )

        altas = cursor.altas("MOT_CAJA_DATA")
        self.assertEqual(1, len(altas))
        self.assertIn("ACTIVO", altas[0][0])
        self.assertEqual([], cursor.bitacora())
        self.assertEqual(1, result["creados"])


class SitioDeLaPiezaRetirada(unittest.TestCase):
    def test_no_escribe_localizacion_si_la_columna_no_existe(self):
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            },
            con_localizacion=False,
        )
        request = _peticion([
            ReplacementItem(
                equipo=1,
                marca="WEG",
                modelo="W22",
                serial="NEW-M",
                sitio_saliente="TALLER ELECTRICO",
            )
        ])

        _execute_replacements(cursor, request, fecha="2026-07-21", hora="10:30:00")

        self.assertNotIn("LOCALIZACION", cursor.retiros()[0][0])

    def test_escribe_localizacion_cuando_la_columna_existe(self):
        cursor = FakeCursor(
            instaladas={
                "MOT_DATA": {
                    "ID": 10,
                    "MARCA": "OLD",
                    "MODELO": "M1",
                    "SERIAL": "S1",
                    "FECHA": "2024-01-15",
                }
            },
            con_localizacion=True,
        )
        request = _peticion([
            ReplacementItem(
                equipo=1,
                marca="WEG",
                modelo="W22",
                serial="NEW-M",
                sitio_saliente="TALLER ELECTRICO",
            )
        ])

        _execute_replacements(cursor, request, fecha="2026-07-21", hora="10:30:00")

        retiro = cursor.retiros()[0]
        self.assertIn("LOCALIZACION", retiro[0])
        self.assertIn("TALLER ELECTRICO", retiro[1])


if __name__ == "__main__":
    unittest.main()
