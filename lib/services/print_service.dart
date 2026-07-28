import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/equipo_visual_config.dart';
import '../models/models.dart';

class MedicionPrintData {
  final int localizacion;
  final String fecha;
  final String hora;
  final Map<String, double?> valores;
  final double? rms;
  final String? observaciones;
  final String? equipoNombre;
  final String? tag;
  final String? sistema;
  final String? subsistema;
  final String? responsable;
  final String? cargo;

  const MedicionPrintData({
    required this.localizacion,
    required this.fecha,
    required this.hora,
    required this.valores,
    this.rms,
    this.observaciones,
    this.equipoNombre,
    this.tag,
    this.sistema,
    this.subsistema,
    this.responsable,
    this.cargo,
  });
}

class MedicionPrintService {
  static bool _printing = false;

  static Future<void> printMeasurement({
    required MedicionPrintData data,
    required Equipo equipo,
    EquipoInfo? info,
  }) async {
    if (_printing) {
      throw Exception('Ya hay una impresion en proceso.');
    }
    _printing = true;
    try {
      if (!kIsWeb) {
        final sentToLaptop = await _requestLaptopPrint(data, equipo, info);
        if (sentToLaptop) {
          await Future<void>.delayed(const Duration(seconds: 6));
          return;
        }
      }
      final bytes = await buildPdf(data: data, equipo: equipo, info: info);
      await Printing.layoutPdf(
        name: 'SCV-PTBG LOC-${data.localizacion} ${data.fecha}.pdf',
        onLayout: (_) async => bytes,
      );
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      _printing = false;
    }
  }

  static Future<bool> _requestLaptopPrint(
    MedicionPrintData data,
    Equipo equipo,
    EquipoInfo? info,
  ) async {
    try {
      final request = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'action': 'print_measurement',
        'created_at': DateTime.now().toIso8601String(),
        'localizacion': data.localizacion,
        'fecha': data.fecha,
        'hora': data.hora,
        'sistema': data.sistema ?? equipo.sistema,
        'subsistema': data.subsistema ?? equipo.subsistema,
        'equipo': equipo.equipo,
        'tag': data.tag ?? equipo.qrDisplay,
        'pt_eq': equipo.ptEq,
        'rms': data.rms,
        'observaciones': data.observaciones,
        'responsable': data.responsable,
        'cargo': data.cargo,
        'valores': data.valores.map((key, value) => MapEntry(key, value)),
        'info': {
          'marca': info?.marca ?? equipo.info?.marca,
          'serial': info?.serial ?? equipo.info?.serial,
          'modelo': info?.modelo ?? equipo.info?.modelo,
          'hp': info?.hp ?? equipo.info?.hp,
          'rpm': info?.rpm ?? equipo.info?.rpm,
        },
      };
      final file =
          File('/data/data/com.example.scv_ptbg/files/usb_print_request.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(request));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List> buildPdf({
    required MedicionPrintData data,
    required Equipo equipo,
    EquipoInfo? info,
  }) async {
    final doc = pw.Document();
    final title =
        _isVent(equipo) ? 'PROTOCOLO AJUSTE DE CORREAS, TEMPERATURA, LUBRICACION Y VELOCIDAD DE VIBRACION.'
            : 'PROTOCOLO DE NIVELACION, ALINEACION, TEMPERATURA, LUBRICACION Y VELOCIDAD DE VIBRACION.';
    final code = _isVent(equipo) ? 'SF-OP-FOR-021' : 'SF-OP-FOR-020';
    final revision = _isVent(equipo) ? '3' : '4';
    final points = _pointsFor(equipo);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(title, code, revision),
            pw.SizedBox(height: 8),
            _equipmentBlock(data, equipo, info),
            pw.SizedBox(height: 10),
            _tempLubBlock(points.length),
            pw.SizedBox(height: 10),
            _alignmentBlock(equipo),
            pw.SizedBox(height: 10),
            _vibrationBlock(points, data.valores),
            pw.SizedBox(height: 8),
            _observations(data),
            pw.Spacer(),
            _signatureBlock(),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(String title, String code, String revision) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(5.2),
        2: pw.FlexColumnWidth(1.7),
        3: pw.FlexColumnWidth(1.7),
      },
      children: [
        pw.TableRow(
          children: [
            _cell('SCV-PTBG', bold: true, center: true, rowSpanHint: true),
            _cell(title, bold: true, center: true, fontSize: 8.5),
            _cell('CODIGO:\n$code', bold: true, center: true, fontSize: 8),
            _cell('REVISION:\n$revision', bold: true, center: true, fontSize: 8),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('', height: 22),
            _cell('', height: 22),
            _cell('F. EMISION:\n22/11/24', center: true, fontSize: 7.5),
            _cell('F. APROBACION:\n23/01/26', center: true, fontSize: 7.5),
          ],
        ),
      ],
    );
  }

  static pw.Widget _equipmentBlock(
    MedicionPrintData data,
    Equipo equipo,
    EquipoInfo? info,
  ) {
    final tag = _firstNonBlank(data.tag, equipo.qrDisplay, equipo.scada);
    final sistema = _firstNonBlank(data.sistema, equipo.sistema);
    final subsistema = _firstNonBlank(
      data.subsistema,
      equipo.subsistema,
      equipo.equipo,
      data.equipoNombre,
    );
    final responsable = _firstNonBlank(data.responsable, '');
    final cargo = _firstNonBlank(data.cargo, '');
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.3),
        3: pw.FlexColumnWidth(2.3),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(2.1),
      },
      children: [
        pw.TableRow(children: [
          _labelCell('Fecha:'),
          _valueCell('${data.fecha} ${data.hora}'),
          _labelCell('Sistema:'),
          _valueCell(sistema),
          _labelCell('Subsistema:'),
          _valueCell(subsistema),
        ]),
        pw.TableRow(children: [
          _labelCell('TAG:'),
          _valueCell(tag),
          _labelCell('Fabricante:'),
          _valueCell(_clean(info?.marca)),
          _labelCell('N:'),
          _valueCell(_clean(info?.serial)),
        ]),
        pw.TableRow(children: [
          _labelCell('Modelo:'),
          _valueCell(_clean(info?.modelo)),
          _labelCell('HP:'),
          _valueCell(_clean(info?.hp)),
          _labelCell('RPM:'),
          _valueCell(_clean(info?.rpm)),
        ]),
        if (responsable.isNotEmpty || cargo.isNotEmpty)
          pw.TableRow(children: [
            _labelCell('Responsable:'),
            _valueCell(responsable),
            _labelCell('Cargo:'),
            _valueCell(cargo),
            _labelCell(''),
            _valueCell(''),
          ]),
      ],
    );
  }

  static pw.Widget _tempLubBlock(int count) {
    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        _sectionCell('VALORES DE TEMPERATURA Y LUBRICACION', colspanHint: true),
        _cell('PUNTO', bold: true, center: true),
        _cell('TEMPERATURA', bold: true, center: true),
        _cell('LUBRICACION', bold: true, center: true),
      ]),
    ];
    for (var i = 1; i <= count; i++) {
      rows.add(pw.TableRow(children: [
        _cell('', height: 16),
        _cell('$i', center: true, height: 16),
        _cell('', height: 16),
        _cell('', height: 16),
      ]));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
      columnWidths: const {
        0: pw.FlexColumnWidth(4.4),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.8),
        3: pw.FlexColumnWidth(1.8),
      },
      children: rows,
    );
  }

  static pw.Widget _alignmentBlock(Equipo equipo) {
    if (_isVent(equipo) || equipo.visualType == 5) {
      return _boxedLine('AJUSTE DE CORREAS: SI________   NO______ ; TENSION: ______');
    }
    if (equipo.visualType == 6) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _boxedLine('ALINEACION: SI_________   NO________'),
          _smallAlignmentTable('VALORES DE ALINEACION CAJA-MOTOR'),
          _smallAlignmentTable('VALORES DE ALINEACION CAJA-BOMBA'),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _boxedLine('ALINEACION: SI_________   NO________'),
        _smallAlignmentTable('VALORES DE ALINEACION MOTOR - BOMBA'),
      ],
    );
  }

  static pw.Widget _smallAlignmentTable(String title) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(children: [
          _sectionCell(title),
          _cell('VERTICAL', bold: true, center: true),
          _cell('', center: true),
          _cell('HORIZONTAL', bold: true, center: true),
          _cell('', center: true),
        ]),
        pw.TableRow(children: [
          _labelCell('ANGULO (mm/100mm)'),
          _cell('', height: 15),
          _cell('', height: 15),
          _cell('', height: 15),
          _cell('', height: 15),
        ]),
        pw.TableRow(children: [
          _labelCell('COMPENSACION (mm)'),
          _cell('', height: 15),
          _cell('', height: 15),
          _cell('', height: 15),
          _cell('', height: 15),
        ]),
      ],
    );
  }

  static pw.Widget _vibrationBlock(
    List<PuntoCapturaConfig> points,
    Map<String, double?> values,
  ) {
    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        _sectionCell('VELOCIDAD DE VIBRACION (mm/s)'),
        _cell('H', bold: true, center: true),
        _cell('V', bold: true, center: true),
        _cell('A', bold: true, center: true),
      ]),
    ];

    for (final point in points) {
      rows.add(pw.TableRow(children: [
        _labelCell('${point.puntoPantalla}. ${_cleanPointName(point.nombre)}'),
        _valueCell(_fmt(values['H${point.puntoDb}']), center: true),
        _valueCell(_fmt(values['V${point.puntoDb}']), center: true),
        _valueCell(_fmt(values['A${point.puntoDb}']), center: true),
      ]));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _boxedLine('VELOCIDAD DE VIBRACION: SI________   NO______'),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
          columnWidths: const {
            0: pw.FlexColumnWidth(4.0),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.2),
          },
          children: rows,
        ),
      ],
    );
  }

  static pw.Widget _observations(MedicionPrintData data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(7.0),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(children: [
          _labelCell('Observacion:'),
          _valueCell((data.observaciones ?? '').trim(), height: 34),
          _labelCell('RMS:'),
          _valueCell(_fmt(data.rms), center: true),
        ]),
      ],
    );
  }

  static pw.Widget _signatureBlock() {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          _cell('REALIZADO POR:\n\n\nNombre / Firma', center: true, height: 48),
          _cell('REVISADO POR:\n\n\nNombre / Firma', center: true, height: 48),
        ]),
      ],
    );
  }

  static pw.Widget _boxedLine(String text) {
    return pw.Container(
      height: 22,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.55),
      ),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _sectionCell(String text, {bool colspanHint = false}) =>
      _cell(text, bold: true, center: true, fill: PdfColors.grey300);

  static pw.Widget _labelCell(String text) =>
      _cell(text, bold: true, fontSize: 8, fill: PdfColors.grey200);

  static pw.Widget _valueCell(String text, {bool center = false, double? height}) =>
      _cell(text, center: center, height: height);

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool center = false,
    double fontSize = 8,
    double? height,
    PdfColor? fill,
    bool rowSpanHint = false,
  }) {
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: fill,
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static List<PuntoCapturaConfig> _pointsFor(Equipo equipo) {
    final points = PlanMedicionResolver.fromEquipo(equipo);
    if (points.isNotEmpty) return points;
    return const [
      PuntoCapturaConfig(puntoPantalla: 1, puntoVisual: 1, puntoDb: 1, nombre: 'Punto 1'),
    ];
  }

  static bool _isVent(Equipo equipo) {
    final config = EquipoVisualResolver.previewFromEquipo(equipo);
    return config.id == 'ventiladores';
  }

  static String _clean(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL' || text.toUpperCase() == 'SIN DATOS') {
      return '';
    }
    return text;
  }

  static String _firstNonBlank(String? a, String? b, [String? c, String? d]) {
    for (final value in [a, b, c, d]) {
      final clean = _clean(value);
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  static String _fmt(double? value) => value == null ? '' : value.toStringAsFixed(2);

  static String _cleanPointName(String value) {
    return value
        .replaceAll('Motor - ', '')
        .replaceAll('Bomba - ', 'Bomba ')
        .replaceAll('Caja multiplicadora - ', 'Caja ')
        .trim();
  }
}
