import unittest

from reporte_texto import observacion


class TestObservacion(unittest.TestCase):
    def test_pasa_a_mayusculas(self):
        self.assertEqual(observacion("equipo disponible"), "EQUIPO DISPONIBLE")

    def test_respeta_los_acentos(self):
        # "ALINEACION" sin tilde seria una falta en un documento controlado.
        self.assertEqual(
            observacion("se corrigió la alineación"),
            "SE CORRIGIÓ LA ALINEACIÓN",
        )
        self.assertEqual(observacion("mañana"), "MAÑANA")

    def test_quita_los_espacios_de_los_bordes(self):
        # El teclado de la tablet deja espacios al final con facilidad, y en
        # una celda centrada del formato eso corre el texto.
        self.assertEqual(observacion("  ruido leve  "), "RUIDO LEVE")

    def test_sin_observacion_devuelve_vacio(self):
        # Vacio y no "NONE": lo que se escribe en el papel cuando no hay
        # observacion es nada.
        self.assertEqual(observacion(None), "")
        self.assertEqual(observacion(""), "")
        self.assertEqual(observacion("   "), "")

    def test_acepta_lo_que_no_es_texto(self):
        # Las columnas de observacion son TEXT, pero una fila vieja puede
        # traer un numero y no vale la pena tumbar una impresion por eso.
        self.assertEqual(observacion(123), "123")

    def test_lo_que_ya_venia_en_mayusculas_no_cambia(self):
        self.assertEqual(observacion("EQUIPO OPERATIVO"), "EQUIPO OPERATIVO")


if __name__ == "__main__":
    unittest.main()
