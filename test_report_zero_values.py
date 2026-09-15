"""Regresion: cero no tomado en papel, decimales y datos originales intactos."""
import copy
from decimal import Decimal
from pathlib import Path
import tempfile
import unittest

import fitz
from reporte_texto import medicion
import official_form_report as official
import black_start_report as black
import compressor_checklist_report as compressor
import equipment_report as equipment


class MeasurementTextTest(unittest.TestCase):
    def test_solo_cero_exacto_es_slash(self):
        for value in (0, 0.0, -0.0, "0", "0.0", " 0.000 ", "0,0", "-0.00", Decimal("0")):
            with self.subTest(value=value):
                self.assertEqual(medicion(value), "/")
                self.assertEqual(official._number(value), "/")
                self.assertEqual(official._texto_tension(value), "/")
                self.assertEqual(black._con_unidad(value, "VOLTAJE (V)"), "/")

    def test_decimales_no_se_redondean_ni_se_ocultan(self):
        for value in (0.1, 0.03, 0.001, -0.03, "0,03", "0.00001", "1e-9999", Decimal("0.030"), 10):
            with self.subTest(value=value):
                self.assertEqual(medicion(value), str(value))
                self.assertEqual(official._number(value), str(value))
                self.assertEqual(official._texto_tension(value), str(value))
                self.assertEqual(black._con_unidad(value, "VOLTAJE (V)"), f"{value} V")

    def test_vacios_texto_y_metadatos(self):
        self.assertEqual(medicion(None), "")
        self.assertEqual(official._number(None), "/")
        self.assertEqual(medicion("42 N"), "42 N")
        self.assertEqual(medicion(False), "False")
        self.assertEqual(official._text("0"), "0")
        self.assertEqual(equipment._reading("serial", "0"), "0")
        self.assertEqual(equipment._reading("H1", "0"), "/")

    def test_tabla_comparativa_y_graficas_no_clasifican_cero_como_lectura(self):
        rows = [{"H1": 0, "H2": 0.03, "serial": "0", "odt": 0}]
        before = copy.deepcopy(rows)
        table = equipment._comparative_table(rows, ["H1", "H2", "serial"], {}, " mm/s", equipment._styles())
        self.assertEqual(table._cellvalues[1][1].getPlainText(), "/")
        self.assertEqual(table._cellvalues[2][1].getPlainText(), "0.03 mm/s")
        self.assertEqual(table._cellvalues[3][1].getPlainText(), "0 mm/s")
        self.assertEqual(table._cellvalues[4][1].getPlainText(), "0")
        self.assertIsNone(equipment._trend_chart("Prueba", rows, [("H1", "H1")], "", equipment._styles()))
        self.assertEqual(rows, before)


class PrintedZeroTest(unittest.TestCase):
    def test_celdas_de_las_cinco_plantillas_oficiales(self):
        with tempfile.TemporaryDirectory() as tmp:
            for points in (1, 4, 5, 6, 7):
                with self.subTest(points=points):
                    name = official.TEMPLATE_BY_POINTS[points]
                    data = official.sample_data(points)
                    data["vibration"].update(H1=0.0, V1=0.1, A1=0.03)
                    data["temperature"]["T1"] = 0
                    data["lubrication"]["L1"] = "0.00"
                    data["alignment"]["AMB_ANGULO_V"] = 0
                    data["alignment"]["AMB_ANGULO_H"] = 0.03
                    data["belt_tension"] = 0
                    before = copy.deepcopy(data)
                    path = official.fill_official_form(Path("formatos_pdf_nuevos") / name, Path(tmp) / name, data, ["all"])
                    with fitz.open(path) as doc:
                        cells = official.VIBRATION_CELLS[name][0]
                        expected = ["/", "0.1", "0.03"]
                        for cell, value in zip(cells, expected):
                            self.assertEqual(doc[0].get_text(clip=fitz.Rect(*cell)).strip(), value)
                        _, x0, x1, x2, y, _, h = official.TEMP_LAYOUT[name]
                        self.assertEqual(doc[0].get_text(clip=fitz.Rect(x0, y, x1, y+h)).strip(), "/")
                        self.assertEqual(doc[0].get_text(clip=fitz.Rect(x1, y, x2, y+h)).strip(), "/")
                    self.assertEqual(data, before)

    def test_compresor_horas_y_arranques_sin_truncar(self):
        row = dict(TAG="PRUEBA", N_HORAS=0.0, N_ARRANQUES=0.03, MTTO_LUB_UH=0,
                   MTTO_AIR_UH=0.1, MTTO_AIR_UF="08/09/2026", ACT1=0)
        before = copy.deepcopy(row)
        with tempfile.TemporaryDirectory() as tmp:
            path = compressor.build_compressor_checklist_pdf(row, Path(tmp))
            with fitz.open(path) as doc:
                text = doc[0].get_text(clip=fitz.Rect(395, 160, 590, 178))
                self.assertIn("/", text)
                self.assertIn("0.03", text)
                text = doc[0].get_text(clip=fitz.Rect(273, 535, 325, 620))
                self.assertIn("/", text)
                self.assertIn("0.1", text)
        self.assertEqual(row, before)

    def test_black_start_ceros_sin_unidad_y_decimales_con_unidad(self):
        row = dict(TRABAJO_HRS=0, REFRIGERANTE_LVL=0.0, COMBUSTIBLE_LVL=0.1, ACEITE_LVL=0.03)
        before = copy.deepcopy(row)
        with tempfile.TemporaryDirectory() as tmp:
            path = black.build_black_start_pdf(row, Path(tmp))
            with fitz.open(path) as doc:
                for y, expected in zip(black.FILAS_PARAMETROS, ["/", "/", "0.1 %", "0.03 %"]):
                    text = doc[0].get_text(clip=fitz.Rect(black.PARAM_X0, y-10, black.PARAM_X1, y+10)).strip()
                    self.assertEqual(text, expected)
        self.assertEqual(row, before)


if __name__ == "__main__":
    unittest.main()
