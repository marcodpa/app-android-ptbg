import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import fitz
from compressor_checklist_report import (
    build_compressor_checklist_pdf, checklist_con_mantenimientos_anteriores,
)


def ejemplos():
    anterior = dict(UUID="a", LOCALIZACION=53, FECHA="01/06/2026", HORA="08:00",
                    MTTO_LUB_UF="01/06/2026", MTTO_LUB_UH="3000", MTTO_LUB_OBS="Grasa aplicada",
                    MTTO_AIR_UF="01/06/2026", MTTO_AIR_UH="3000")
    filtro = dict(UUID="b", LOCALIZACION=53, FECHA="2026-08-20", HORA="08:00",
                  MTTO_AIR_UF="20/08/2026", MTTO_AIR_UH="4000", MTTO_AIR_OBS="Filtro cambiado")
    actual = dict(UUID="c", LOCALIZACION=53, FECHA="2026-09-07", HORA="08:00",
                  EQUIPO="COMPRESOR DE PRUEBA", TAG="PRUEBA-53", SUBSISTEMA="AIRE INSTRUMENTOS",
                  H_INICIO="08:00", H_FIN="09:00", N_HORAS=4500, N_ARRANQUES=150)
    actual.update({f"ACT{i}": 1 for i in range(1, 12)})
    return anterior, filtro, actual


class CompressorHistoryTest(unittest.TestCase):
    def test_hereda_por_tarea_sin_modificar_registros(self):
        anterior, filtro, actual = ejemplos()
        copia = copy.deepcopy(actual)
        res = checklist_con_mantenimientos_anteriores(actual, [filtro, anterior])
        self.assertEqual(res["MTTO_LUB_UF"], "01/06/2026")
        self.assertEqual(res["MTTO_LUB_UH"], "3000")
        self.assertEqual(res["MTTO_LUB_OBS"], "Grasa aplicada")
        self.assertEqual(res["MTTO_AIR_UF"], "20/08/2026")
        self.assertEqual(res["MTTO_AIR_OBS"], "Filtro cambiado")
        self.assertEqual(actual, copia)
        self.assertEqual(res["FECHA"], actual["FECHA"])

    def test_no_toma_futuro_ni_otro_equipo(self):
        anterior, _, actual = ejemplos()
        futuro = dict(anterior, UUID="futuro", FECHA="2026-10-01")
        otro = dict(anterior, LOCALIZACION=54)
        res = checklist_con_mantenimientos_anteriores(actual, [futuro, otro])
        self.assertNotIn("MTTO_LUB_UF", res)

    def test_datos_nuevos_no_se_mezclan_con_la_tarea_anterior(self):
        anterior, _, actual = ejemplos()
        actual["MTTO_LUB_UF"] = "07/09/2026"
        res = checklist_con_mantenimientos_anteriores(actual, [anterior])
        self.assertNotIn("MTTO_LUB_UH", res)
        self.assertNotIn("MTTO_LUB_OBS", res)

    def test_blancos_y_cero(self):
        anterior, _, actual = ejemplos()
        anterior.update(MTTO_LUB_UH=0)
        actual.update(MTTO_LUB_UF="  ", MTTO_LUB_UH=" ")
        res = checklist_con_mantenimientos_anteriores(actual, [anterior])
        self.assertEqual(res["MTTO_LUB_UH"], 0)

    def test_pdf_imprime_lo_anterior_y_no_la_fecha_de_hoy_como_mantenimiento(self):
        anterior, filtro, actual = ejemplos()
        with tempfile.TemporaryDirectory() as tmp:
            ruta = build_compressor_checklist_pdf(actual, Path(tmp), historial=[anterior, filtro])
            with fitz.open(ruta) as doc:
                self.assertEqual(len(doc), 1)
                mantenimiento = doc[0].get_text(clip=fitz.Rect(180, 530, 560, 650))
                self.assertIn("01/06/2026", mantenimiento)
                self.assertIn("3000", mantenimiento)
                self.assertIn("20/08/2026", mantenimiento)
                self.assertIn("GRASA APLICADA", mantenimiento)
                self.assertIn("FILTRO CAMBIADO", mantenimiento)
                self.assertIn("SIN REGISTRO PREVIO", mantenimiento)
                self.assertNotIn("07/09/2026", mantenimiento)

    def test_uploader_entrega_historial_al_generador_sin_escribir_mariadb(self):
        import tablet_uploader as u
        anterior, filtro, actual = ejemplos()
        maria = MagicMock()
        cur = maria.cursor.return_value.__enter__.return_value
        cur.fetchone.side_effect = [actual, {"NAME_SYS_2": "ACTUAL"}]
        cur.fetchall.return_value = [anterior, filtro, actual]
        request = dict(id="prueba-mtto", action="compressor_checklist_print", uuid="c", print=False)
        with patch.object(u, "read_tablet_usb_print_request", return_value=request), \
             patch.object(u, "_claim_print_request", return_value=(True, "prueba", None)), \
             patch.object(u, "_release_print_request_lock"), \
             patch.object(u, "clear_tablet_usb_print_request"), \
             patch.object(u, "set_tablet_usb_status") as estado, \
             patch.object(u, "connect_mariadb", return_value=maria), \
             patch.object(u, "build_compressor_checklist_pdf", return_value=Path("prueba.pdf")) as pdf, \
             patch.object(u, "open_pdf", return_value="Vista previa"):
            u.process_tablet_print_request(MagicMock(serial="prueba"), Path("."), set(), log=lambda _: None)
        pdf.assert_called_once()
        self.assertEqual(pdf.call_args.kwargs["historial"], [anterior, filtro, actual])
        self.assertEqual(pdf.call_args.args[0]["SUBSISTEMA"], "ACTUAL")
        self.assertEqual(estado.call_args.kwargs["status"], "DONE")
        self.assertTrue(all(call.args[0].lstrip().startswith("SELECT") for call in cur.execute.call_args_list))
        maria.commit.assert_not_called()
        maria.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
