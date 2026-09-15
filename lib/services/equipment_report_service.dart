import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

enum EquipmentReportType {
  integral('integral', 'Reporte integral',
      'Ficha técnica y todos los historiales disponibles'),
  vibration('vibration', 'Vibración', 'Lecturas H, V, A, RMS y observaciones'),
  temperature(
      'temperature', 'Temperatura', 'Temperaturas registradas por punto'),
  alignment(
      'alignment', 'Alineación', 'Ángulos, compensaciones y observaciones'),
  lubrication(
      'lubrication', 'Lubricación', 'Gramos aplicados por punto y responsable'),
  replacements('replacements', 'Reemplazos',
      'Componentes y especificaciones reemplazadas'),
  couplingChanges('coupling_changes', 'Cambios de coupling',
      'Cambios de coupling confirmados para el equipo'),
  beltAdjustment(
      'belt', 'Ajuste de correas', 'Ajuste realizado y tension registrada'),
  technical('technical', 'Ficha técnica',
      'Identificación y datos técnicos del equipo');

  const EquipmentReportType(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  /// Los que el reporte comparativo sabe generar.
  ///
  /// Falta [beltAdjustment] a proposito: el ajuste de correas no tiene tabla
  /// propia, solo es una casilla de la orden de trabajo, asi que no hay
  /// historial que comparar. Ofrecerlo en el selector terminaba siempre en un
  /// error de la laptop ("tipo de reporte no valido") sin PDF.
  ///
  /// Sigue en el enum porque la impresion del formato oficial si lo usa, que
  /// lee la casilla de la ODT y no un historial.
  static const comparables = <EquipmentReportType>[
    integral,
    vibration,
    temperature,
    alignment,
    lubrication,
    replacements,
    couplingChanges,
    technical,
  ];
}

class EquipmentReportService {
  static const _requestPath =
      '/data/data/com.example.scv_ptbg/files/usb_print_request.json';
  static const _statusPath =
      '/data/data/com.example.scv_ptbg/files/usb_status.json';
  static bool _working = false;

  static Future<String> request({
    required Equipo equipo,
    required EquipmentReportType type,
    Set<EquipmentReportType>? types,
    bool print = false,
    int? odt,
    bool officialForm = false,
    int? measurementCount,
  }) async {
    if (officialForm && equipo.ptEq == 10) {
      throw Exception(
          'El formulario oficial del separador está pendiente de incorporar.');
    }
    if (_working) throw Exception('Ya se está generando un reporte.');
    _working = true;
    final id = 'report-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final file = File(_requestPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'id': id,
        'action': officialForm ? 'official_form_print' : 'equipment_report',
        'created_at': DateTime.now().toIso8601String(),
        'localizacion': equipo.localizacion,
        'tag': equipo.qrDisplay,
        'report_type': type.code,
        'report_types': (types ?? {type}).map((item) => item.code).toList(),
        'print': print,
        if (odt != null) 'odt': odt,
        if (measurementCount != null) 'measurement_count': measurementCount,
      }));
      return await _waitForResult(id);
    } finally {
      _working = false;
    }
  }

  /// Manda a imprimir el check list de un compresor (SF-OP-FOR-040).
  ///
  /// La laptop lo lee de la planta por su UUID, no de la tablet: asi el papel
  /// dice exactamente lo que quedo registrado. Por eso solo se puede imprimir
  /// un check list ya sincronizado.
  static Future<String> imprimirChecklistCompresor({
    required String uuid,
    bool imprimir = true,
  }) async {
    if (_working) throw Exception('Ya se está generando un reporte.');
    _working = true;
    final id = 'checklist-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final file = File(_requestPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'id': id,
        'action': 'compressor_checklist_print',
        'created_at': DateTime.now().toIso8601String(),
        'uuid': uuid,
        'print': imprimir,
      }));
      return await _waitForResult(id);
    } finally {
      _working = false;
    }
  }

  /// Manda a imprimir el check list del black start (SF-OP-FOR-036).
  static Future<String> imprimirChecklistBlackStart({
    required String uuid,
    bool imprimir = true,
  }) async {
    if (_working) throw Exception('Ya se está generando un reporte.');
    _working = true;
    final id = 'blackstart-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final file = File(_requestPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'id': id,
        'action': 'black_start_print',
        'created_at': DateTime.now().toIso8601String(),
        'uuid': uuid,
        'print': imprimir,
      }));
      return await _waitForResult(id);
    } finally {
      _working = false;
    }
  }

  static Future<String> _waitForResult(String id) async {
    final statusFile = File(_statusPath);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        if (!await statusFile.exists()) continue;
        final decoded = jsonDecode(await statusFile.readAsString());
        if (decoded is! Map || decoded['request_id']?.toString() != id) {
          continue;
        }
        final status = decoded['status']?.toString().toUpperCase();
        final detail = decoded['detail']?.toString().trim() ?? '';
        if (status == 'DONE') {
          return detail.isEmpty ? 'Reporte abierto en la laptop.' : detail;
        }
        if (status == 'ERROR') {
          throw Exception(
              detail.isEmpty ? 'No se pudo generar el reporte.' : detail);
        }
      } catch (error) {
        if (error is FormatException || error is FileSystemException) continue;
        rethrow;
      }
    }
    throw Exception(
      'La laptop no respondió. Abra el subidor USB, conecte la tablet y vuelva a intentar.',
    );
  }
}
