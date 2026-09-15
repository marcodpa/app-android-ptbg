import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/models.dart';
import '../models/equipo_visual_config.dart';
import '../models/replacement_request.dart';
import '../services/equipment_report_service.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/industrial_navigation.dart';

class EquipmentHistoryScreen extends StatefulWidget {
  const EquipmentHistoryScreen({super.key, required this.equipo});
  final Equipo equipo;

  @override
  State<EquipmentHistoryScreen> createState() => _EquipmentHistoryScreenState();
}

class _EquipmentHistoryScreenState extends State<EquipmentHistoryScreen> {
  static const _services = <EquipmentReportType>[
    EquipmentReportType.vibration,
    EquipmentReportType.temperature,
    EquipmentReportType.lubrication,
    EquipmentReportType.alignment,
    EquipmentReportType.replacements,
    EquipmentReportType.couplingChanges,
  ];
  EquipmentReportType _service = EquipmentReportType.vibration;
  List<Map<String, dynamic>> _rows = [];
  int _index = 0;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DbHelper.instance.getEquipmentServiceHistory(
      widget.equipo.localizacion,
      _service.code,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _index = 0;
      _loading = false;
    });
  }

  Future<void> _selectService(EquipmentReportType service) async {
    if (_service == service) return;
    setState(() => _service = service);
    await _load();
  }

  Future<void> _generateReport() async {
    var count = _rows.isEmpty ? 1 : _rows.length.clamp(1, 50);
    final selection = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 18),
              Text('Reporte de ${_service.label}', style: AppText.titulo),
              const SizedBox(height: 6),
              Text('Elige cuántas mediciones recientes incluir',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(
                    onPressed: count > 1 ? () => update(() => count--) : null,
                    icon: const Icon(Icons.remove_rounded)),
                Container(
                  width: 104,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.teal.withValues(alpha: .35))),
                  child: Column(children: [
                    Text('$count',
                        style: AppText.display.copyWith(color: AppColors.teal)),
                    const Text('mediciones', style: AppText.apoyo)
                  ]),
                ),
                IconButton.filledTonal(
                    onPressed:
                        count < (_rows.isEmpty ? 50 : _rows.length.clamp(1, 50))
                            ? () => update(() => count++)
                            : null,
                    icon: const Icon(Icons.add_rounded)),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, count),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('GENERAR REPORTE'))),
            ]),
          ),
        ),
      ),
    );
    if (selection == null || !mounted) return;
    setState(() => _generating = true);
    try {
      final detail = await EquipmentReportService.request(
        equipo: widget.equipo,
        type: _service,
        measurementCount: selection,
      );
      if (mounted) {
        avisar(context, detail, AppColors.tealDark);
      }
    } catch (error) {
      if (mounted) {
        avisar(context, mensajeDeError(error), AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    final surface = dark ? AppColors.surface : Colors.white;
    final current = _rows.isEmpty ? null : _rows[_index];
    return Scaffold(
      backgroundColor: dark ? AppColors.bg : Colors.white,
      appBar: IndustrialAppBar(
        titulo: 'Historial del equipo',
        subtitulo: widget.equipo.equipo,
        panel: true,
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 54,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            scrollDirection: Axis.horizontal,
            itemCount: _services.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final service = _services[i];
              return ChoiceChip(
                  label: Text(service.label),
                  selected: service == _service,
                  onSelected: (_) => _selectService(service),
                  selectedColor: AppColors.teal,
                  labelStyle: AppText.etiqueta.copyWith(
                      color: service == _service ? Colors.white : null));
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : current == null
                  ? _Empty(service: _service.label)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  '${_service.label} · Medición ${_index + 1} de ${_rows.length}',
                                  style: AppText.cuerpoFuerte)),
                          Text(
                              '${current['fecha'] ?? '-'}  ${current['hora'] ?? ''}',
                              style: AppText.etiqueta
                                  .copyWith(color: AppColors.teal)),
                        ]),
                        const SizedBox(height: 10),
                        Expanded(
                            child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: dark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              boxShadow: AppColors.shadowSm),
                          child: SingleChildScrollView(
                              child: _MeasurementDetails(
                                  row: current,
                                  dark: dark,
                                  equipo: widget.equipo,
                                  type: _service)),
                        )),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: _index + 1 < _rows.length
                                      ? () => setState(() => _index++)
                                      : null,
                                  icon: const Icon(Icons.chevron_left_rounded),
                                  label: const Text('ANTERIOR'))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: _index > 0
                                      ? () => setState(() => _index--)
                                      : null,
                                  icon: const Icon(Icons.chevron_right_rounded),
                                  label: const Text('SIGUIENTE'))),
                        ]),
                      ]),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: _generating ? null : _generateReport,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('GENERAR REPORTE PDF'))),
        ),
      ]),
    );
  }
}

/// Una columna de la tabla de puntos: el prefijo real en la base de datos
/// (`H1`, `T1`, `L1`, ...) y el encabezado que ve el operador.
class _PointColumn {
  const _PointColumn(this.prefix, this.label);
  final String prefix;
  final String label;
}

/// Servicios que se miden punto por punto y por tanto se muestran como tabla.
///
/// Alineación, reemplazos y cambios de coupling no están aquí: no guardan
/// columnas por punto (alineación usa AMB_/ACM_/ACB_), así que siguen
/// mostrándose como tarjetas.
const _pointColumns = <EquipmentReportType, List<_PointColumn>>{
  EquipmentReportType.vibration: [
    _PointColumn('H', 'H'),
    _PointColumn('V', 'V'),
    _PointColumn('A', 'A'),
  ],
  EquipmentReportType.temperature: [_PointColumn('T', 'Temperatura')],
  EquipmentReportType.lubrication: [_PointColumn('L', 'Gramos')],
};

/// Una fila de la tabla: el número que ve el operador, qué cosa es, y sus
/// valores en el orden de los encabezados.
class _TableLine {
  const _TableLine(this.number, this.name, this.values);
  final String number;
  final String name;
  final List<String> values;
}

/// La tabla ya resuelta para un servicio concreto. `consumed` son las columnas
/// de la base de datos que la tabla ya muestra, para no repetirlas debajo.
class _ServiceTable {
  const _ServiceTable({
    required this.nameHeader,
    required this.headers,
    required this.lines,
    required this.consumed,
    this.family,
  });
  final String nameHeader;
  final List<String> headers;
  final List<_TableLine> lines;
  final Set<String> consumed;

  /// Toda la familia de columnas de este servicio, la use la tabla o no.
  ///
  /// La base guarda los 9 puntos y los 3 acoples para todos los equipos, pero
  /// un equipo sólo usa los suyos. Sin esto, los puntos que no le tocan
  /// aparecían abajo como tarjetas sueltas.
  final RegExp? family;

  bool oculta(String key) =>
      consumed.contains(key) || (family?.hasMatch(key) ?? false);
}

/// Arma la tabla del servicio. Devuelve null cuando el servicio no tiene nada
/// que tabular, y entonces el registro se muestra sólo como tarjetas.
_ServiceTable? _tableFor(
  EquipmentReportType type,
  Map<String, dynamic> row,
  Equipo equipo,
) {
  final columns = _pointColumns[type];
  if (columns != null) {
    // Las filas salen del plan del equipo, no de la fila de la base de datos:
    // un equipo sólo tiene los puntos que le corresponden según PUNTOS.
    final points = PlanMedicionResolver.fromEquipo(equipo);
    if (points.isEmpty) return null;
    return _ServiceTable(
      nameHeader: 'Punto',
      headers: [for (final column in columns) column.label],
      lines: [
        for (final point in points)
          _TableLine('${point.puntoPantalla}', point.nombre, [
            for (final column in columns)
              _formatCell(row['${column.prefix}${point.puntoDb}'])
          ]),
      ],
      consumed: {
        for (final column in columns)
          for (final point in points) '${column.prefix}${point.puntoDb}',
      },
      // H1..H9, T1..T10, L1..L9 segun el servicio: los puntos que este equipo
      // no usa tampoco deben salir como tarjetas.
      family: RegExp(
        '^(${columns.map((column) => column.prefix).join('|')})\\d+\$',
        caseSensitive: false,
      ),
    );
  }

  if (type == EquipmentReportType.alignment) {
    // Alineación no se mide por punto sino por acople, y cuáles aplican los
    // decide el mismo resolver que usa la pantalla de captura.
    final sections = AlignmentPlanResolver.fromPuntos(equipo.puntos);
    if (sections.isEmpty) return null;
    return _ServiceTable(
      nameHeader: 'Acople',
      headers: const ['Áng. V', 'Áng. H', 'Comp. V', 'Comp. H'],
      lines: [
        for (var i = 0; i < sections.length; i++)
          _TableLine(
            '${i + 1}',
            sections[i].title.replaceFirst('ALINEACIÓN ', ''),
            [
              for (final field in sections[i].fields)
                _formatCell(
                    row[field.column] ?? row[field.column.toLowerCase()])
            ],
          ),
      ],
      // Los tres acoples viven en la tabla para todos los equipos. Los que no
      // le tocan a este se ocultan en vez de caer sueltos abajo.
      family: RegExp(r'^(AMB|ACM|ACB)_', caseSensitive: false),
      consumed: {
        for (final section in sections)
          for (final field in section.fields) ...[
            field.column,
            field.column.toLowerCase()
          ],
      },
    );
  }

  // Reemplazos y cambios de coupling no guardan valores por punto: cada
  // registro es la placa (marca/modelo/serial) de la pieza que se cambió.
  if (type == EquipmentReportType.replacements ||
      type == EquipmentReportType.couplingChanges) {
    const plate = ['marca', 'modelo', 'serial'];
    return _ServiceTable(
      nameHeader: 'Componente',
      headers: const ['Marca', 'Modelo', 'Serial'],
      lines: [
        _TableLine(
          '1',
          type == EquipmentReportType.couplingChanges
              ? 'Coupling'
              : _replacementName(row['equipo']),
          [for (final key in plate) _formatCell(row[key])],
        ),
      ],
      consumed: plate.toSet(),
    );
  }

  return null;
}

String _replacementName(Object? code) {
  final value = int.tryParse('${code ?? ''}');
  if (value == null) return 'Componente';
  try {
    return replacementComponentLabel(replacementComponentFromCode(value));
  } on FormatException {
    return 'Componente $value';
  }
}

/// Un dato que el registro debería tener pero quedó vacío se muestra como "—":
/// la fila no desaparece, para que se note que faltó.
String _formatCell(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '—';
  final number = num.tryParse(text);
  if (number == null) return text;
  final fixed = number.toStringAsFixed(2);
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}

class _MeasurementDetails extends StatelessWidget {
  const _MeasurementDetails({
    required this.row,
    required this.dark,
    required this.equipo,
    required this.type,
  });
  final Map<String, dynamic> row;
  final bool dark;
  final Equipo equipo;
  final EquipmentReportType type;

  static const _hidden = {
    'uuid',
    'operation_uuid',
    'remote_key',
    'id_remoto',
    'localizacion',
    'sincronizado',
    'error_sync',
    'created_at',
    'updated_at',
    'fecha_hora_iso',
    '_source',
    'RMS'
  };

  @override
  Widget build(BuildContext context) {
    final table = _tableFor(type, row, equipo);
    final entries = row.entries
        .where((e) =>
            !_hidden.contains(e.key) &&
            !(table?.oculta(e.key) ?? false) &&
            e.value != null &&
            e.value.toString().trim().isNotEmpty)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (table != null) ...[
        _ServiceTableView(table: table, dark: dark),
        const SizedBox(height: 14),
      ],
      _MetaCards(entries: entries, dark: dark, equipo: equipo),
    ]);
  }
}

class _ServiceTableView extends StatelessWidget {
  const _ServiceTableView({required this.table, required this.dark});
  final _ServiceTable table;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final border = dark ? AppColors.border : const Color(0xFFE2E8F0);
    final head = dark ? AppColors.textSecondary : const Color(0xFF64748B);
    final body = dark ? AppColors.textPrimary : const Color(0xFF111827);
    // Con pocas columnas cabe el encabezado completo ("Temperatura"); con
    // cuatro (alineación) hay que apretarlas para dejarle sitio al nombre.
    final width = switch (table.headers.length) {
      1 => 120.0,
      >= 4 => 72.0,
      _ => 96.0,
    };
    return Container(
      decoration: BoxDecoration(
          color: dark ? AppColors.surface2 : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border)),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          0: const FixedColumnWidth(32),
          1: const FlexColumnWidth(),
          for (var i = 0; i < table.headers.length; i++)
            i + 2: FixedColumnWidth(width),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border))),
            children: [
              const SizedBox.shrink(),
              _cell(table.nameHeader, color: head, bold: true),
              for (final header in table.headers)
                _cell(header, color: head, bold: true, align: TextAlign.center),
            ],
          ),
          for (var i = 0; i < table.lines.length; i++)
            TableRow(
              decoration: i + 1 < table.lines.length
                  ? BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: border.withValues(alpha: .55))))
                  : null,
              children: [
                _cell(table.lines[i].number,
                    color: AppColors.teal, bold: true, align: TextAlign.center),
                _cell(table.lines[i].name, color: body),
                for (final value in table.lines[i].values)
                  _cell(value,
                      color: body, bold: true, align: TextAlign.center),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text,
          {required Color color,
          bool bold = false,
          TextAlign align = TextAlign.start}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(text,
            textAlign: align,
            style:
                (bold ? AppText.dato : AppText.cuerpo).copyWith(color: color)),
      );
}

class _MetaCards extends StatelessWidget {
  const _MetaCards({
    required this.entries,
    required this.dark,
    required this.equipo,
  });
  final List<MapEntry<String, dynamic>> entries;
  final bool dark;
  final Equipo equipo;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries
          .map((entry) => SizedBox(
                width: MediaQuery.sizeOf(context).width > 600
                    ? 180
                    : (MediaQuery.sizeOf(context).width - 62) / 2,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                      color:
                          dark ? AppColors.surface2 : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: dark
                              ? AppColors.border
                              : const Color(0xFFE2E8F0))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_label(entry.key),
                            style: AppText.etiqueta.copyWith(
                                color: dark
                                    ? AppColors.textSecondary
                                    : const Color(0xFF64748B))),
                        const SizedBox(height: 3),
                        Text(entry.value.toString(),
                            style: AppText.cuerpoFuerte.copyWith(
                                color: dark
                                    ? AppColors.textPrimary
                                    : const Color(0xFF111827))),
                      ]),
                ),
              ))
          .toList(),
    );
  }

  String _label(String key) {
    final measurement =
        RegExp(r'^([HVA])(\d+)$', caseSensitive: false).firstMatch(key);
    if (measurement != null) {
      const axis = <String, String>{
        'H': 'Horizontal',
        'V': 'Vertical',
        'A': 'Axial',
      };
      final point = int.parse(measurement.group(2)!);
      return '${axis[measurement.group(1)!.toUpperCase()]} — ${_pointName(point)}';
    }
    final pointValue =
        RegExp(r'^([TL])(\d+)$', caseSensitive: false).firstMatch(key);
    if (pointValue != null) {
      final kind = pointValue.group(1)!.toUpperCase() == 'T'
          ? 'Temperatura'
          : 'Lubricación';
      return '$kind — ${_pointName(int.parse(pointValue.group(2)!))}';
    }
    const names = {
      'fecha': 'Fecha',
      'hora': 'Hora',
      'odt': 'Orden de trabajo (ODT)',
      'observaciones': 'Observaciones',
      'responsable': 'Responsable',
      'cargo': 'Cargo',
      'marca': 'Marca del equipo',
      'modelo': 'Modelo del equipo',
      'serial': 'Serial del equipo',
      'RMS': 'Nivel global de vibración (RMS)'
    };
    return names[key] ?? key.replaceAll('_', ' ').toUpperCase();
  }

  String _pointName(int dbPoint) {
    for (final point in PlanMedicionResolver.fromEquipo(equipo)) {
      if (point.puntoDb == dbPoint) return point.nombre;
    }
    return 'Punto de medición $dbPoint';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.service});
  final String service;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.history_toggle_off_rounded,
            size: 58, color: AppColors.teal),
        const SizedBox(height: 12),
        Text('Sin registros de $service', style: AppText.seccion),
        const SizedBox(height: 4),
        const Text('Sincroniza la tablet para descargar el historial.',
            textAlign: TextAlign.center),
      ]));
}
