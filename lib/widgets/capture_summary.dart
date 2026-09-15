import 'package:flutter/material.dart';

import '../theme.dart';

/// Una fila del resumen: el punto como lo ve el operador y sus valores.
class CaptureSummaryRow {
  const CaptureSummaryRow({
    required this.numero,
    required this.nombre,
    required this.valores,
  });

  final String numero;
  final String nombre;
  final List<String> valores;

  bool get vacia => valores.every((valor) => valor.trim().isEmpty);
}

/// Resumen de lo capturado, con el mismo formato que el historial y el reporte.
///
/// Se muestra mientras el mecanico escribe las observaciones: al ver el valor
/// de cada punto se acuerda de que encontro en ese punto y puede describirlo.
class CaptureSummary extends StatelessWidget {
  const CaptureSummary({
    super.key,
    required this.headers,
    required this.rows,
    this.titulo = 'Lo que acabas de medir',
  });

  /// Encabezados de las columnas de valores: ['H', 'V', 'A'], ['Temperatura']...
  final List<String> headers;
  final List<CaptureSummaryRow> rows;
  final String titulo;

  /// Punto sin lectura: la fila no desaparece, para que se note que falto.
  static String formatear(Object? value) {
    final texto = value?.toString().trim() ?? '';
    if (texto.isEmpty) return '—';
    final numero = num.tryParse(texto.replaceAll(',', '.'));
    if (numero == null) return texto;
    final fijo = numero.toStringAsFixed(2);
    return fijo.endsWith('.00') ? fijo.substring(0, fijo.length - 3) : fijo;
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    const border = AppColors.border;
    const head = AppColors.textSecondary;
    const body = AppColors.textPrimary;
    // Con una sola columna cabe el encabezado completo; con tres hay que
    // dejarle ancho al nombre del punto.
    final anchoValor = headers.length > 1 ? 62.0 : 104.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded,
                    size: 16, color: AppColors.teal),
                const SizedBox(width: 7),
                Text(
                  titulo,
                  style: AppText.seccion.copyWith(color: AppColors.teal),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: border),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FixedColumnWidth(30),
              1: const FlexColumnWidth(),
              for (var i = 0; i < headers.length; i++)
                i + 2: FixedColumnWidth(anchoValor),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                children: [
                  const SizedBox.shrink(),
                  _celda('Punto', color: head, bold: true),
                  for (final header in headers)
                    _celda(header,
                        color: head, bold: true, align: TextAlign.center),
                ],
              ),
              for (var i = 0; i < rows.length; i++)
                TableRow(
                  decoration: i + 1 < rows.length
                      ? const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: AppColors.border)),
                        )
                      : null,
                  children: [
                    _celda(rows[i].numero,
                        color: AppColors.teal,
                        bold: true,
                        align: TextAlign.center),
                    _celda(rows[i].nombre, color: body),
                    for (var c = 0; c < headers.length; c++)
                      _celda(
                        c < rows[i].valores.length
                            ? rows[i].valores[c]
                            : '—',
                        color: rows[i].vacia ? AppColors.textHint : body,
                        bold: true,
                        align: TextAlign.center,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _celda(
    String texto, {
    required Color color,
    bool bold = false,
    TextAlign align = TextAlign.start,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Text(
          texto,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (bold ? AppText.dato : AppText.cuerpo).copyWith(color: color),
        ),
      );
}
