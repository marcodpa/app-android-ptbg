import 'operation_flow.dart';

class WorkOrder {
  const WorkOrder({
    required this.odt,
    required this.fecha,
    required this.hora,
    required this.equipo,
    required this.ubicacion,
    required this.codeConjunto,
    required this.vibracion,
    required this.temperatura,
    required this.alineacion,
    required this.lubricacion,
    required this.couplingReplacement,
    required this.correaAjuste,
    required this.reemplazo,
    this.limpiezaPlato = false,
    this.tabletOrigen,
  });

  final int odt;
  final String fecha;
  final String hora;
  final String equipo;
  final int ubicacion;
  final int codeConjunto;
  final bool vibracion;
  final bool temperatura;
  final bool alineacion;
  final bool lubricacion;
  final bool couplingReplacement;
  final bool correaAjuste;
  final bool reemplazo;
  final bool limpiezaPlato;
  final String? tabletOrigen;

  factory WorkOrder.forSelection({
    required int odt,
    required DateTime createdAt,
    required String equipo,
    required int ubicacion,
    required int codeConjunto,
    required Set<OperationType> services,
    required String tabletOrigen,
  }) =>
      WorkOrder(
        odt: odt,
        fecha: _date(createdAt),
        hora: _time(createdAt),
        equipo: equipo,
        ubicacion: ubicacion,
        tabletOrigen: tabletOrigen,
        codeConjunto: codeConjunto,
        vibracion: services.contains(OperationType.vibration),
        temperatura: services.contains(OperationType.temperature),
        alineacion: services.contains(OperationType.alignment),
        lubricacion: services.contains(OperationType.lubrication),
        couplingReplacement: services.contains(OperationType.couplingChange),
        correaAjuste: services.contains(OperationType.beltAdjustment),
        reemplazo: services.contains(OperationType.replacement),
      );

  Map<String, dynamic> toDbMap() => {
        'odt': odt,
        'tablet_origen': tabletOrigen,
        'fecha': fecha,
        'hora': hora,
        'equipo': equipo,
        'ubicacion': ubicacion,
        'code_conjunto': codeConjunto,
        'vibracion': vibracion ? 1 : 0,
        'temperatura': temperatura ? 1 : 0,
        'alineacion': alineacion ? 1 : 0,
        'lubricacion': lubricacion ? 1 : 0,
        'coupling_rpl': couplingReplacement ? 1 : 0,
        'correa_ajt': correaAjuste ? 1 : 0,
        'reemplazo': reemplazo ? 1 : 0,
        // Se marca al guardar la limpieza, no simplemente al seleccionarla.
        'limpieza_plato': limpiezaPlato ? 1 : 0,
        'sincronizado': 0,
        'error_sync': null,
      };

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}
