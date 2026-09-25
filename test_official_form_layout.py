import tempfile
import unittest
from pathlib import Path

import fitz

from official_form_report import fill_official_form, sample_data


class OfficialFormLayoutTests(unittest.TestCase):
    def test_fin_fan_labels_are_unique_and_grid_is_preserved(self):
        template = Path('formatos_pdf_nuevos/Motor-Ventilador(Fin-Fan).pdf')
        with tempfile.TemporaryDirectory() as tmp:
            output = fill_official_form(template, Path(tmp)/'report.pdf', sample_data(4), ['lubrication'])
            with fitz.open(output) as doc, fitz.open(template) as source:
                page = doc[0]
                text = page.get_text()
                self.assertEqual(text.count('RADIAL HORIZONTAL'), 2)
                self.assertEqual(text.count('RADIAL VERTICAL'), 2)
                self.assertEqual(text.count('SUBSISTEMA:'), 1)
                # Only the ventilator table has standalone axis headings.
                self.assertEqual(sum(s.strip() == 'HORIZONTAL' for s in text.splitlines()), 1)
                # Every original table stroke remains: text cleanup must not erase borders.
                original = [d['items'] for d in source[0].get_drawings()]
                result = [d['items'] for d in page.get_drawings()]
                for stroke in original:
                    self.assertIn(stroke, result)

    def test_uninstalled_values_are_centered_in_actual_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = fill_official_form(
                Path('formatos_pdf_nuevos/Motor-Ventilador(Fin-Fan).pdf'),
                Path(tmp)/'report.pdf', sample_data(4), ['lubrication'])
            with fitz.open(output) as doc:
                slashes = [w for w in doc[0].get_text('words')
                           if w[4] == '/' and 70 < w[0] < 598 and 218 < w[1] < 247]
                self.assertEqual(len(slashes), 6)
                for word in slashes:
                    self.assertTrue(word[3] < 232.75 or word[1] > 232.75)


if __name__ == '__main__':
    unittest.main()
