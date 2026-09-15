import 'models.dart';
import 'operation_flow.dart';

/// Danos que se registran al reemplazar una pieza.
///
/// Es una lista cerrada a proposito: con texto libre el mismo dano termina
/// escrito de cuatro formas distintas y despues no se puede agrupar.
/// Estatus que un tecnico puede asignar a mano.
///
/// INSTALADO no esta: que una pieza este puesta en un equipo lo decide el
/// reemplazo, nunca una eleccion manual.
const estadosPieza = <String>[
  'DISPONIBLE',
  'AVERIADO',
  'DESECHADO',
];

/// Donde queda fisicamente una pieza que sale de un equipo.
const sitiosPieza = <String>[
  'TALLER ELECTRICO',
  'TALLER MECANICO',
  'TALLER EXTERNO',
  'ALMACEN PRINCIPAL',
  'ALMACEN DE MOTORES',
];

const danosReemplazo = <String>[
  'Rodamiento',
  'Bobinado',
  'Sello mecanico',
  'Eje',
  'Impulsor',
  'Acople',
  'Ventilador de enfriamiento',
  'Fin de vida util',
  'Otro',
];

class ReplacementData {
  const ReplacementData({
    required this.brand,
    required this.model,
    required this.serial,
    this.motivo,
    this.estadoSaliente,
    this.sitioSaliente,
    this.updateTechnicalSpecs = false,
    this.voltage = '',
    this.current = '',
    this.rpm = '',
    this.serviceFactor = '',
    this.horsepower = '',
    this.frame = '',
    this.driveBearing = '',
    this.oppositeBearing = '',
    this.cycle = '',
    this.start = '',
    this.phases = '',
    this.tension = '',
    this.lubrication = '',
  });

  final String brand;
  final String model;
  final String serial;

  /// Que se dano en la pieza que sale. Va a MOT_LOG_RPL.MOTIVO.
  final String? motivo;

  /// Con que estatus queda la pieza que SALE del equipo. Lo elige el tecnico:
  /// solo el sabe si el motor retirado quedo averiado, sirve o se desecha.
  final String? estadoSaliente;

  /// A donde va fisicamente la pieza que sale: taller o almacen.
  final String? sitioSaliente;
  final bool updateTechnicalSpecs;
  final String voltage;
  final String current;
  final String rpm;
  final String serviceFactor;
  final String horsepower;
  final String frame;
  final String driveBearing;
  final String oppositeBearing;
  final String cycle;
  final String start;
  final String phases;
  final String tension;
  final String lubrication;

  Map<String, dynamic> toLocalMap() => {
        'marca': brand.trim(),
        'modelo': model.trim(),
        'serial': serial.trim(),
        'motivo': motivo,
        'estado_saliente': estadoSaliente,
        'sitio_saliente': sitioSaliente,
        'actualizar_especificaciones': updateTechnicalSpecs ? 1 : 0,
        'voltaje': voltage.trim(),
        'corriente': current.trim(),
        'rpm': rpm.trim(),
        'sf': serviceFactor.trim(),
        'hp': horsepower.trim(),
        'frame': frame.trim(),
        'brgs_drive': driveBearing.trim(),
        'brgs_opp': oppositeBearing.trim(),
        'ciclo': cycle.trim(),
        'arranque': start.trim(),
        'ph': phases.trim(),
        'tension': tension.trim(),
        'lubricacion': lubrication.trim(),
      };

  Map<String, dynamic> toJson(ReplacementComponent component) => {
        'equipo': replacementComponentCode(component),
        ...toLocalMap(),
      };
}

class ReplacementRequest {
  const ReplacementRequest({
    required this.equipo,
    required this.components,
    this.odt,
  });

  final Equipo equipo;
  final Map<ReplacementComponent, ReplacementData> components;
  final int? odt;

  Map<String, dynamic> toJson() => {
        'localizacion': equipo.localizacion,
        'code_conjunto': equipo.codeSys,
        'odt': odt,
        'componentes': components.entries
            .map((entry) => entry.value.toJson(entry.key))
            .toList(),
      };
}

int replacementComponentCode(ReplacementComponent component) {
  switch (component) {
    case ReplacementComponent.motor:
      return 1;
    case ReplacementComponent.pump:
      return 2;
    case ReplacementComponent.gearbox:
      return 3;
    case ReplacementComponent.fan:
      return 4;
  }
}

class ReplacementSaveResult {
  const ReplacementSaveResult.success({
    this.created = 0,
    required this.updated,
    required this.unchanged,
  })  : ok = true,
        error = null;

  const ReplacementSaveResult.failure(this.error)
      : ok = false,
        created = 0,
        updated = 0,
        unchanged = 0;

  final bool ok;
  final int created;
  final int updated;
  final int unchanged;
  final String? error;
}

class ReplacementLocalItem {
  const ReplacementLocalItem({
    required this.uuid,
    required this.component,
    required this.brand,
    required this.model,
    required this.serial,
    this.updateTechnicalSpecs = false,
    this.voltage = '',
    this.current = '',
    this.rpm = '',
    this.serviceFactor = '',
    this.horsepower = '',
    this.frame = '',
    this.driveBearing = '',
    this.oppositeBearing = '',
    this.cycle = '',
    this.start = '',
    this.phases = '',
    this.tension = '',
    this.lubrication = '',
    this.errorSync,
    this.synchronized = false,
  });

  final String uuid;
  final ReplacementComponent component;
  final String brand;
  final String model;
  final String serial;
  final bool updateTechnicalSpecs;
  final String voltage;
  final String current;
  final String rpm;
  final String serviceFactor;
  final String horsepower;
  final String frame;
  final String driveBearing;
  final String oppositeBearing;
  final String cycle;
  final String start;
  final String phases;
  final String tension;
  final String lubrication;
  final String? errorSync;
  final bool synchronized;

  factory ReplacementLocalItem.fromMap(Map<String, dynamic> map) {
    return ReplacementLocalItem(
      uuid: (map['uuid'] ?? '').toString(),
      component: replacementComponentFromCode(_asInt(map['equipo'])),
      brand: (map['marca'] ?? '').toString(),
      model: (map['modelo'] ?? '').toString(),
      serial: (map['serial'] ?? '').toString(),
      updateTechnicalSpecs: _asInt(map['actualizar_especificaciones']) == 1,
      voltage: (map['voltaje'] ?? '').toString(),
      current: (map['corriente'] ?? '').toString(),
      rpm: (map['rpm'] ?? '').toString(),
      serviceFactor: (map['sf'] ?? '').toString(),
      horsepower: (map['hp'] ?? '').toString(),
      frame: (map['frame'] ?? '').toString(),
      driveBearing: (map['brgs_drive'] ?? '').toString(),
      oppositeBearing: (map['brgs_opp'] ?? '').toString(),
      cycle: (map['ciclo'] ?? '').toString(),
      start: (map['arranque'] ?? '').toString(),
      phases: (map['ph'] ?? '').toString(),
      tension: (map['tension'] ?? '').toString(),
      lubrication: (map['lubricacion'] ?? '').toString(),
      errorSync: map['error_sync']?.toString(),
      synchronized: _asInt(map['sincronizado']) == 1,
    );
  }

  ReplacementData toData() => ReplacementData(
        brand: brand,
        model: model,
        serial: serial,
        updateTechnicalSpecs: updateTechnicalSpecs,
        voltage: voltage,
        current: current,
        rpm: rpm,
        serviceFactor: serviceFactor,
        horsepower: horsepower,
        frame: frame,
        driveBearing: driveBearing,
        oppositeBearing: oppositeBearing,
        cycle: cycle,
        start: start,
        phases: phases,
        tension: tension,
        lubrication: lubrication,
      );
}

class ReplacementLocalOperation {
  const ReplacementLocalOperation({
    required this.operationUuid,
    required this.localizacion,
    required this.codeConjunto,
    required this.fecha,
    required this.hora,
    required this.components,
    this.odt,
  });

  final String operationUuid;
  final int localizacion;
  final int codeConjunto;
  final String fecha;
  final String hora;
  final List<ReplacementLocalItem> components;
  final int? odt;

  bool get synchronized =>
      components.isNotEmpty && components.every((item) => item.synchronized);

  bool get hasError => components.any(
        (item) => item.errorSync != null && item.errorSync!.trim().isNotEmpty,
      );

  List<String> get componentLabels => components
      .map((item) => replacementComponentLabel(item.component))
      .toList();

  static List<ReplacementLocalOperation> fromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final operationUuid =
          (row['operation_uuid'] ?? row['uuid'] ?? '').toString();
      grouped.putIfAbsent(operationUuid, () => []).add(row);
    }

    return grouped.entries.map((entry) {
      final first = entry.value.first;
      return ReplacementLocalOperation(
        operationUuid: entry.key,
        localizacion: _asInt(first['localizacion']),
        codeConjunto: _asInt(first['code_conjunto']),
        fecha: (first['fecha'] ?? '').toString(),
        hora: (first['hora'] ?? '').toString(),
        odt: first['odt'] == null ? null : _asInt(first['odt']),
        components: entry.value
            .map(ReplacementLocalItem.fromMap)
            .toList(growable: false),
      );
    }).toList(growable: false);
  }
}

ReplacementComponent replacementComponentFromCode(int code) {
  switch (code) {
    case 1:
      return ReplacementComponent.motor;
    case 2:
      return ReplacementComponent.pump;
    case 3:
      return ReplacementComponent.gearbox;
    case 4:
      return ReplacementComponent.fan;
    default:
      throw FormatException('Tipo de componente invalido: $code');
  }
}

String replacementComponentLabel(ReplacementComponent component) {
  switch (component) {
    case ReplacementComponent.motor:
      return 'Motor';
    case ReplacementComponent.pump:
      return 'Bomba';
    case ReplacementComponent.gearbox:
      return 'Caja';
    case ReplacementComponent.fan:
      return 'Ventilador';
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
