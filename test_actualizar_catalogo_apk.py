import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

from actualizar_catalogo_apk import (
    SQL_CATALOGO, actualizar_catalogo, descargar_catalogo, generar_dart,
    literal_dart, normalizar_catalogo,
)


def fila(loc=1, **cambios):
    return dict(ID=loc, CODE_SYS=1, EQUIPO="Motor", LOCALIZACION=loc,
                CODE_QR=f"QR-{loc}", PUNTOS=6, TAGNAME="MOT-01",
                sistema="TURBINA", subsistema="Auxiliar", FAMILIA_COMPAT=None,
                **cambios)


class CatalogoApkTest(unittest.TestCase):
    def test_no_limita_la_cantidad_ni_excluye_sistemas(self):
        for cantidad in (51, 56, 57, 120):
            with self.subTest(cantidad=cantidad):
                filas = [fila(i) for i in range(1, cantidad + 1)]
                filas[-1].update(CODE_SYS=9, PUNTOS=0)
                equipos = normalizar_catalogo(filas)
                contenido = generar_dart(equipos)
                self.assertEqual(contenido.count("const Equipo("), cantidad)
                self.assertIn(f"catalogoBaseCantidad = {cantidad};", contenido)
                self.assertEqual(equipos[-1]["codeSys"], 9)
                self.assertEqual(equipos[-1]["ptEq"], 0)

    def test_copia_qr_puntos_subsistema_y_familia(self):
        datos = fila()
        datos.update(FAMILIA_COMPAT=4, PUNTOS=8)
        equipo = normalizar_catalogo([datos])[0]
        self.assertEqual(equipo["qrCode"], "QR-1")
        self.assertEqual(equipo["scada"], "MOT-01")
        self.assertEqual(equipo["subsistema"], "Auxiliar")
        self.assertEqual(equipo["familiaCompat"], 4)
        self.assertEqual(equipo["puntos"], equipo["ptEq"])
        self.assertEqual(equipo["ptEq"], 8)

    def test_rechaza_vacio_y_duplicados(self):
        for filas in ([], [fila(), fila()], [fila(1), dict(fila(2), ID=1)]):
            with self.assertRaises(ValueError):
                normalizar_catalogo(filas)

    def test_rechaza_filas_invalidas_sin_omitirlas_silenciosamente(self):
        for campo, valor in (("ID", None), ("LOCALIZACION", 0),
                             ("LOCALIZACION", 1.5), ("PUNTOS", "NaN"),
                             ("CODE_SYS", -1), ("EQUIPO", " ")):
            with self.subTest(campo=campo, valor=valor):
                with self.assertRaises(ValueError):
                    normalizar_catalogo([dict(fila(), **{campo: valor})])

    def test_escapa_texto_para_dart(self):
        self.assertEqual(literal_dart('A "$motor"\n\\'), '"A \\"\\$motor\\"\\n\\\\"')
        self.assertEqual(literal_dart(None), "null")

    def test_version_estable_y_crece_cuando_cambia_catalogo(self):
        equipos = normalizar_catalogo([fila()])
        inicial = generar_dart(equipos, "const int catalogoBaseVersion = 2;")
        self.assertIn("catalogoBaseVersion = 3;", inicial)
        self.assertEqual(generar_dart(equipos, inicial), inicial)
        nuevos = normalizar_catalogo([fila(), fila(2)])
        self.assertIn("catalogoBaseVersion = 4;", generar_dart(nuevos, inicial))

    def test_orden_no_cambia_version(self):
        equipos = normalizar_catalogo([fila(2), fila(1)])
        inicial = generar_dart(equipos)
        self.assertEqual(generar_dart(normalizar_catalogo([fila(1), fila(2)]), inicial), inicial)

    def test_actualizacion_atomica_solo_catalogo(self):
        with tempfile.TemporaryDirectory() as temporal:
            destino = Path(temporal) / "mock_data.dart"
            self.assertEqual(actualizar_catalogo(normalizar_catalogo([fila()]), destino), 1)
            self.assertIn("const Equipo(", destino.read_text(encoding="utf-8"))
            self.assertFalse(destino.with_suffix(".dart.tmp").exists())

    def test_lectura_mariadb_no_escribe_y_cierra_conexion(self):
        db = MagicMock()
        cur = db.cursor.return_value.__enter__.return_value
        cur.fetchall.return_value = [fila()]
        driver = MagicMock()
        driver.connect.return_value = db
        uploader = SimpleNamespace(pymysql=driver, DB_HOST="host", DB_PORT=3306,
                                   DB_USER="user", DB_PASS="secret", DB_NAME="db")
        equipos = descargar_catalogo(uploader)
        self.assertEqual(len(equipos), 1)
        self.assertEqual([c.args[0] for c in cur.execute.call_args_list],
                         ["START TRANSACTION READ ONLY", SQL_CATALOGO])
        db.commit.assert_not_called()
        db.close.assert_called_once()
        self.assertNotIn("secret", generar_dart(equipos))

    def test_cierra_conexion_si_falla_la_lectura(self):
        db = MagicMock()
        db.cursor.return_value.__enter__.return_value.execute.side_effect = RuntimeError("fallo")
        driver = MagicMock()
        driver.connect.return_value = db
        uploader = SimpleNamespace(pymysql=driver, DB_HOST="host", DB_PORT=3306,
                                   DB_USER="user", DB_PASS="secret", DB_NAME="db")
        with self.assertRaises(RuntimeError):
            descargar_catalogo(uploader)
        db.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
