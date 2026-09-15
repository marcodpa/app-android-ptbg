import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/qr_label_service.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';

/// Etiqueta QR de un equipo: se ve, se guarda y se imprime.
///
/// El visor de PDF trae sus propios botones de guardar y compartir, asi que no
/// hace falta pedir permisos de almacenamiento ni escribir en carpetas del
/// sistema: el guardado lo resuelve Android con su propio selector.
class QrEtiquetaScreen extends StatelessWidget {
  const QrEtiquetaScreen({
    super.key,
    required this.codeQr,
    required this.equipo,
    required this.localizacion,
    this.sistema = '',
    this.subsistema = '',
    this.tag = '',
  });

  final String codeQr;
  final String equipo;
  final int localizacion;
  final String sistema;
  final String subsistema;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(
        titulo: 'Etiqueta QR',
        subtitulo: 'Identificación del equipo',
        panel: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipo,
                  style: AppText.seccion.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '$codeQr · LOC-$localizacion',
                  style: AppText.subtitulo
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.download_rounded,
                      size: 15, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Con el boton de guardar de arriba la descargas o la '
                      'mandas a imprimir a tamano real.',
                      style: AppText.apoyo.copyWith(color: AppColors.teal),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) => QrLabelService.build(
                codeQr: codeQr,
                equipo: equipo,
                localizacion: localizacion,
                sistema: sistema,
                subsistema: subsistema,
                tag: tag,
              ),
              pdfFileName: QrLabelService.nombreArchivo(codeQr, localizacion),
              canDebug: false,
              // El visor ya ofrece compartir e imprimir; no hace falta el
              // selector de tamano de pagina, la etiqueta tiene el suyo.
              canChangePageFormat: false,
              canChangeOrientation: false,
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
