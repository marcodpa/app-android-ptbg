import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Etiqueta QR de un equipo, lista para pegar en planta.
///
/// El QR codifica EXACTAMENTE el CODE_QR del equipo, sin URLs ni prefijos: el
/// backend busca por ese valor literal, asi que cualquier adorno rompe el
/// escaneo. Es la misma regla que sigue el generador de la laptop.
class QrLabelService {
  const QrLabelService._();

  /// Arma la etiqueta en PDF.
  ///
  /// Va en PDF y no en PNG porque asi se imprime a tamano real: una etiqueta
  /// tiene que medir lo que mide, y una imagen se escala a lo que quiera el
  /// visor. Ademas el visor de PDF de la tablet ya trae guardar y compartir.
  static Future<Uint8List> build({
    required String codeQr,
    required String equipo,
    required int localizacion,
    String sistema = '',
    String subsistema = '',
    String tag = '',
  }) async {
    final contenido = codeQr.trim();
    if (contenido.isEmpty) {
      throw ArgumentError('El equipo no tiene codigo QR.');
    }

    final doc = pw.Document(title: 'QR $equipo');
    doc.addPage(
      pw.Page(
        // A6 apaisado: entra en una etiquetadora y tambien en media hoja A4
        // cortada, que es como se hacen hoy en planta.
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(10),
        build: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 110,
              height: 110,
              child: pw.BarcodeWidget(
                // Correccion alta: la etiqueta vive a la intemperie, con grasa
                // y golpes. Con este nivel sigue leyendose aunque se pierda
                // parte del dibujo.
                barcode: Barcode.qrCode(
                  errorCorrectLevel: BarcodeQRCorrectionLevel.high,
                ),
                data: contenido,
                drawText: false,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    equipo,
                    style: const pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 2,
                  ),
                  pw.SizedBox(height: 3),
                  // El codigo tambien en texto: si el QR se borra, el equipo
                  // se sigue pudiendo identificar y buscar a mano.
                  pw.Text(
                    contenido,
                    style: const pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('LOC-$localizacion',
                      style: const pw.TextStyle(fontSize: 10)),
                  if (sistema.trim().isNotEmpty)
                    pw.Text(sistema, style: const pw.TextStyle(fontSize: 9)),
                  if (subsistema.trim().isNotEmpty)
                    pw.Text(subsistema,
                        style: const pw.TextStyle(fontSize: 8),
                        maxLines: 2),
                  if (tag.trim().isNotEmpty)
                    pw.Text('TAG $tag',
                        style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Nombre del archivo al guardarlo o compartirlo.
  static String nombreArchivo(String codeQr, int localizacion) {
    final limpio = codeQr.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    final base = limpio.isEmpty ? 'LOC-$localizacion' : limpio;
    return 'QR_$base.pdf';
  }
}
