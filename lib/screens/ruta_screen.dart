import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/equipo_service.dart';
import '../services/equipment_report_service.dart';
import '../services/mediciones_service.dart';
import '../theme.dart';
import '../widgets/industrial_equipment_card.dart';
import '../widgets/industrial_navigation.dart';
import 'operation_selection_screen.dart';
import 'limpieza_plato_screen.dart';
import 'equipment_history_screen.dart';
import '../models/checklist_compresor.dart';
import 'checklist_compresor_screen.dart';
import 'nuevo_equipo_screen.dart';
import '../widgets/avisos.dart';

class RutaScreen extends StatefulWidget {
  const RutaScreen({super.key});

  @override
  State<RutaScreen> createState() => _RutaScreenState();
}

class _RutaScreenState extends State<RutaScreen> {
  String _sistemaFiltro = 'Todos';
  String _busqueda = '';
  List<Equipo> _equipos = [];
  Map<int, UltimaLectura> _ultimas = {};
  Map<int, int> _pendingCounts = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _online = false;
  String? _error;

  /// Equipos registrados aqui que todavia no han subido.
  ///
  /// No se pueden medir: el servidor no conoce su LOCALIZACION y la medicion
  /// se rechazaria al sincronizar, con el trabajo ya hecho en campo.
  Set<int> _sinEnviar = const {};

  @override
  void initState() {
    super.initState();
    _load(actualizarServidor: true);
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    if (kIsWeb) return;
    try {
      final pendientes = await DbHelper.instance.localizacionesSinEnviar();
      if (mounted) setState(() => _sinEnviar = pendientes);
    } catch (_) {
      // Base aun sin crear: no hay equipos nuevos que bloquear.
    }
  }

  Future<void> _load({required bool actualizarServidor}) async {
    if (mounted) {
      setState(() {
        _refreshing = actualizarServidor && !_loading;
        _error = null;
      });
    }

    try {
      // Primero mostramos siempre el catálogo y las lecturas guardadas en la
      // tablet. Después, si hay red, actualizamos sin dejar la pantalla vacía.
      var equipos = await EquipoService.instance.cargar(forceRefresh: false);

      Map<int, UltimaLectura> ultimas = {};
      Map<int, int> pendingCounts = {};
      if (!kIsWeb) {
        try {
          ultimas = await DbHelper.instance.getUltimasLecturasMap();
          pendingCounts =
              await DbHelper.instance.getPendingWorkCountsByLocation();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _equipos = equipos;
          _ultimas = ultimas;
          _pendingCounts = pendingCounts;
          _loading = false;
        });
      }

      if (actualizarServidor) {
        try {
          _online = await ApiService.instance.checkConexion();
        } catch (_) {
          _online = false;
        }

        if (_online) {
          try {
            equipos = await EquipoService.instance.cargar(forceRefresh: true);
            if (mounted) setState(() => _equipos = equipos);
          } catch (_) {
            // El catálogo local sigue disponible aunque falle su actualización.
          }

          final remotas =
              await MedicionesService.instance.descargarUltimasPorEquipo();

          if (!kIsWeb) {
            await DbHelper.instance.upsertMedicionesRemotas(remotas);
            ultimas = await DbHelper.instance.getUltimasLecturasMap();
          } else {
            ultimas = {
              for (final medicion in remotas)
                medicion.localizacion: medicion.toUltimaLectura(),
            };
          }

          if (mounted) setState(() => _ultimas = ultimas);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<String> get _sistemas => ['Todos', ...EquipoService.instance.sistemas];

  List<Equipo> get _filtrados => EquipoService.instance.filtrar(
        sistema: _sistemaFiltro,
        busqueda: _busqueda.isEmpty ? null : _busqueda,
      );

  Future<void> _openHistory(Equipo equipo) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EquipmentHistoryScreen(equipo: equipo),
      ),
    );
  }

  Future<void> _openServices(Equipo equipo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OperationSelectionScreen(equipo: equipo),
      ),
    );
    if (!kIsWeb) {
      final map = await DbHelper.instance.getUltimasLecturasMap();
      final pending = await DbHelper.instance.getPendingWorkCountsByLocation();
      if (mounted) {
        setState(() {
          _ultimas = map;
          _pendingCounts = pending;
        });
      }
    }
  }

  Future<void> _showEquipmentActions(Equipo equipo) async {
    // Un equipo que aun no subio no existe para el servidor. Medirlo ahora
    // seria perder el trabajo al sincronizar, asi que se corta aqui y no
    // dentro de cada servicio.
    if (_sinEnviar.contains(equipo.localizacion)) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Falta sincronizar este equipo'),
          content: Text(
            '${equipo.equipo} se registro en esta tablet y todavia no ha '
            'subido. Hasta que se sincronice no se puede medir ni imprimir: '
            'la planta aun no conoce la LOC-${equipo.localizacion}.\n\n'
            'Ve a Sincronizar y sube los pendientes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ENTENDIDO'),
            ),
          ],
        ),
      );
      return;
    }

    // Un compresor tiene su propio menu: los siete servicios de medicion no
    // le aplican, y en su lugar va la planilla SF-OP-FOR-040.
    if (EquipoService.instance.esCompresorDeAire(equipo)) {
      await _accionesCompresor(equipo);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.precision_manufacturing_rounded,
                    color: AppColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(equipo.equipo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.titulo),
                    Text('${equipo.qrDisplay} · ${equipo.sistema}',
                        style: AppText.apoyo.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            _EquipmentActionTile(
              icon: Icons.analytics_outlined,
              title: 'Reportes e historial',
              subtitle: 'Consultar mediciones anteriores y generar PDF',
              onTap: () => Navigator.pop(sheetContext, 'history'),
            ),
            if (equipo.ptEq == 10) ...[
              const SizedBox(height: 9),
              _EquipmentActionTile(
                  icon: Icons.cleaning_services_rounded,
                  title: 'Historial de limpieza de plato',
                  subtitle: 'Fechas y lecturas del horómetro',
                  onTap: () => Navigator.pop(sheetContext, 'plate-history')),
            ],
            const SizedBox(height: 9),
            _EquipmentActionTile(
              icon: Icons.print_rounded,
              title: 'Imprimir plantilla oficial',
              subtitle: 'Seleccionar ODT y servicios para impresión',
              onTap: () => Navigator.pop(sheetContext, 'print'),
            ),
            const SizedBox(height: 9),
            _EquipmentActionTile(
              icon: Icons.build_circle_outlined,
              title: 'Servicios de medición',
              subtitle: 'Vibración, temperatura, lubricación y más',
              primary: true,
              onTap: () => Navigator.pop(sheetContext, 'services'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'history') await _openHistory(equipo);
    if (action == 'plate-history' && mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => HistorialLimpiezaPlatoScreen(equipo: equipo)));
    }
    if (action == 'print') await _printEquipment(equipo);
    if (action == 'services') await _openServices(equipo);
  }

  /// Menu de un compresor de aire.
  ///
  /// Tiene la misma forma que el de los rotativos —consultar, imprimir y
  /// trabajar— para que el tecnico no tenga que aprender otra pantalla. Lo que
  /// cambia es la accion de trabajo: en vez de elegir entre siete servicios de
  /// medicion, se llena la planilla.
  Future<void> _accionesCompresor(Equipo equipo) async {
    final checklists =
        await DbHelper.instance.getChecklistsCompresor(equipo.localizacion);
    if (!mounted) return;

    final accion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (hoja) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.hvac_rounded, color: AppColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(equipo.equipo, style: AppText.titulo),
                    Text(
                      '${equipo.qrDisplay} · ${equipo.subsistema}',
                      maxLines: 2,
                      style: AppText.apoyo
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'A este equipo no se le toma vibracion, temperatura ni '
                'lubricacion. Su mantenimiento es la planilla SF-OP-FOR-040.',
                style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 18),
            _EquipmentActionTile(
              icon: Icons.analytics_outlined,
              title: 'Planillas anteriores',
              subtitle: checklists.isEmpty
                  ? 'Todavia no se le ha llenado ninguna'
                  : '${checklists.length} realizada'
                      '${checklists.length == 1 ? '' : 's'}',
              onTap: () => Navigator.pop(hoja, 'historial'),
            ),
            const SizedBox(height: 9),
            _EquipmentActionTile(
              icon: Icons.print_rounded,
              title: 'Imprimir planilla',
              subtitle: 'Formato oficial lleno, listo para firmar',
              onTap: () => Navigator.pop(hoja, 'imprimir'),
            ),
            const SizedBox(height: 9),
            _EquipmentActionTile(
              icon: Icons.fact_check_rounded,
              title: 'Llenar planilla',
              subtitle: 'Check list de mantenimiento del compresor',
              primary: true,
              onTap: () => Navigator.pop(hoja, 'llenar'),
            ),
          ]),
        ),
      ),
    );

    if (accion == null || !mounted) return;
    if (accion == 'llenar') {
      final hecho = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ChecklistCompresorScreen(compresor: equipo),
        ),
      );
      if (hecho == true && mounted) await _load(actualizarServidor: false);
      return;
    }
    if (checklists.isEmpty) {
      if (!mounted) return;
      avisar(context, 'Este compresor todavia no tiene ninguna planilla.',
          AppColors.warning);
      return;
    }
    await _elegirChecklist(equipo, checklists, imprimir: accion == 'imprimir');
  }

  /// Elige de cual planilla se habla: la ultima casi siempre, pero el
  /// supervisor a veces necesita una anterior.
  Future<void> _elegirChecklist(
    Equipo equipo,
    List<ChecklistCompresor> checklists, {
    required bool imprimir,
  }) async {
    final elegida = await showModalBottomSheet<ChecklistCompresor>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (hoja) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                imprimir ? 'Cual planilla imprimir' : 'Planillas anteriores',
                style: AppText.titulo,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: checklists.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = checklists[i];
                  final color =
                      c.conforme ? AppColors.success : AppColors.warning;
                  return InkWell(
                    onTap: () => Navigator.pop(hoja, c),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: AppColors.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        Icon(
                          c.conforme
                              ? Icons.check_circle_rounded
                              : Icons.report_problem_rounded,
                          color: color,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.fecha}  ${c.hora}',
                                  style: AppText.cuerpoFuerte),
                              Text(
                                c.conforme
                                    ? 'Sin hallazgos'
                                    : c.hallazgos == 1
                                        ? '1 punto en NO'
                                        : '${c.hallazgos} puntos en NO',
                                style: AppText.apoyo.copyWith(color: color),
                              ),
                              if (!c.sincronizado)
                                Text('Sin enviar',
                                    style: AppText.micro
                                        .copyWith(color: AppColors.textHint)),
                            ],
                          ),
                        ),
                        if (imprimir)
                          const Icon(Icons.print_rounded,
                              color: AppColors.teal, size: 19),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    if (imprimir) {
      await _imprimirChecklist(elegida);
    } else {
      await _verChecklist(equipo, elegida);
    }
  }

  Future<void> _imprimirChecklist(ChecklistCompresor checklist) async {
    // La laptop lo lee de la planta, asi que una planilla sin subir no existe
    // para ella. Se corta aqui y no se deja al tecnico esperando dos minutos.
    if (!checklist.sincronizado) {
      avisar(
        context,
        'Primero sincroniza esta planilla. La laptop imprime lo que hay en '
        'la planta, y todavía no ha subido.',
        AppColors.warning,
        duracion: const Duration(seconds: 5),
      );
      return;
    }
    avisar(context, 'Enviando la planilla a la laptop...', AppColors.tealDark);
    try {
      final detalle = await EquipmentReportService.imprimirChecklistCompresor(
        uuid: checklist.uuid,
      );
      if (!mounted) return;
      avisar(context, detalle, AppColors.success,
          duracion: const Duration(seconds: 6));
    } catch (error) {
      if (!mounted) return;
      avisar(context, mensajeDeError(error), AppColors.error,
          duracion: const Duration(seconds: 6));
    }
  }

  /// Que dijo una planilla, sin tener que imprimirla.
  Future<void> _verChecklist(
    Equipo equipo,
    ChecklistCompresor checklist,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('${equipo.equipo} · ${checklist.fecha}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Horario ${checklist.horaInicio} a ${checklist.horaFin} · '
                '${checklist.numeroHoras} h · '
                '${checklist.numeroArranques} arranques',
                style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
              ),
              const Divider(height: 18),
              for (var i = 0; i < ChecklistCompresor.preguntas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        checklist.actividades[i]
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 15,
                        color: checklist.actividades[i]
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${i + 1}. '
                                '${ChecklistCompresor.preguntas[i]}',
                                style: AppText.apoyo),
                            if (checklist.observaciones[i].isNotEmpty)
                              Text(
                                checklist.observaciones[i],
                                style: AppText.apoyo
                                    .copyWith(color: AppColors.warning),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 18),
              const Text('Último mantenimiento registrado',
                  style: AppText.cuerpoFuerte),
              for (var i = 0; i < checklist.mantenimientos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '${ChecklistCompresor.tareasMantenimiento[i]}\n'
                    '${checklist.mantenimientos[i].tieneRegistro ? [
                        checklist.mantenimientos[i].ultimaFecha,
                        if (checklist.mantenimientos[i].horas.isNotEmpty)
                          '${checklist.mantenimientos[i].horas} horas',
                        checklist.mantenimientos[i].observacion,
                      ].where((v) => v.isNotEmpty).join(' · ') : 'Sin registro previo'}',
                    style: AppText.apoyo,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _registrarEquipo() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const NuevoEquipoScreen()),
    );
    if (creado != true || !mounted) return;
    // El catalogo en memoria no sabe del equipo nuevo: sin limpiarlo la lista
    // seguiria mostrando los de antes hasta reiniciar la app.
    EquipoService.instance.limpiarCache();
    await _load(actualizarServidor: false);
    await _cargarPendientes();
    if (!mounted) return;
    avisar(
        context,
        'Equipo registrado. Sincroniza la tablet para poder medirlo.',
        AppColors.success,
        duracion: const Duration(seconds: 5));
  }

  Future<void> _printEquipment(Equipo equipo) async {
    if (equipo.ptEq == 10) {
      avisar(
          context,
          'El formulario oficial del separador está pendiente. Sus registros sí se guardan y sincronizan.',
          AppColors.warning);
      return;
    }
    // Varias mediciones en un mismo dia son varias ODT: con un limite de 3 se
    // quedaban fuera las de una jornada movida.
    // Solo las que registraron algun servicio: una ODT en cero no tiene nada
    // que imprimir y solo sirve para que el tecnico la elija y se quede
    // trabado con la lista de servicios vacia.
    final orders = await DbHelper.instance.getRecentWorkOrdersForEquipment(
      equipo.localizacion,
      limit: 12,
      soloConServicios: true,
    );
    if (!mounted) return;
    if (orders.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sin mediciones para imprimir'),
          content: const Text(
            'Este equipo tiene órdenes de trabajo, pero ninguna registró un '
            'servicio todavía. Realice una medición, un reemplazo o una '
            'lubricación y luego imprima la planilla.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ENTENDIDO'),
            ),
          ],
        ),
      );
      return;
    }

    const serviceColumns = <EquipmentReportType, String>{
      EquipmentReportType.vibration: 'vibracion',
      EquipmentReportType.temperature: 'temperatura',
      EquipmentReportType.alignment: 'alineacion',
      EquipmentReportType.lubrication: 'lubricacion',
      EquipmentReportType.replacements: 'reemplazo',
      EquipmentReportType.couplingChanges: 'coupling_rpl',
      EquipmentReportType.beltAdjustment: 'correa_ajt',
    };
    Set<EquipmentReportType> available(Map<String, dynamic> order) =>
        serviceColumns.entries
            .where((entry) => (order[entry.value] as num?)?.toInt() == 1)
            .map((entry) => entry.key)
            .toSet();
    int odtOf(Map<String, dynamic> order) => (order['odt'] as num).toInt();

    // Varias mediciones del mismo dia se imprimen juntas: se eligen todas las
    // ODT que hagan falta en vez de una sola.
    final selectedOdts = <int>{odtOf(orders.first)};
    Set<EquipmentReportType> serviciosDisponibles() => {
          for (final order in orders)
            if (selectedOdts.contains(odtOf(order))) ...available(order),
        };
    var selectedServices = serviciosDisponibles();

    final selection =
        await showModalBottomSheet<(List<int>, Set<EquipmentReportType>)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Imprimir - ${equipo.equipo}',
                    style: AppText.titulo,
                  ),
                  const SizedBox(height: 4),
                  // Todo el contenido va dentro de una sola lista que
                  // desplaza. Antes las ODT se soltaban sueltas en el Column y
                  // solo los servicios tenian scroll: un equipo con varias
                  // mediciones pasaba del alto de la hoja y salia la barra de
                  // "BOTTOM OVERFLOWED", sin forma de bajar ni de llegar al
                  // boton.
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        const Text(
                          '1. Elija una o varias mediciones. Se imprime un reporte '
                          'por cada una.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        ...orders.map((order) {
                          final odt = odtOf(order);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedOdts.contains(odt),
                            activeColor: AppColors.teal,
                            title: Text(
                              'ODT $odt',
                              style: AppText.cuerpoFuerte,
                            ),
                            // Se nombra lo que trae cada ODT: una lista de numeros
                            // y fechas no dice cual es la que el tecnico busca.
                            subtitle: Text(
                              '${order['fecha']}  ${order['hora']}\n'
                              '${available(order).map((s) => s.label).join(' · ')}',
                            ),
                            isThreeLine: true,
                            onChanged: (checked) => update(() {
                              if (checked == true) {
                                selectedOdts.add(odt);
                              } else if (selectedOdts.length > 1) {
                                // Siempre queda al menos una: sin ODT no hay nada
                                // que imprimir.
                                selectedOdts.remove(odt);
                              }
                              // Al cambiar las ODT cambian los servicios posibles;
                              // se conserva lo que el usuario ya habia marcado.
                              final posibles = serviciosDisponibles();
                              selectedServices = selectedServices
                                  .where(posibles.contains)
                                  .toSet();
                              if (selectedServices.isEmpty) {
                                selectedServices = posibles;
                              }
                            }),
                          );
                        }),
                        const Divider(height: 18),
                        const Text(
                          '2. Seleccione qué servicios desea imprimir.',
                          style: AppText.cuerpoFuerte,
                        ),
                        const SizedBox(height: 6),
                        ...serviciosDisponibles().map((service) {
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedServices.contains(service),
                            activeColor: AppColors.teal,
                            title: Text(service.label),
                            onChanged: (checked) => update(() {
                              checked == true
                                  ? selectedServices.add(service)
                                  : selectedServices.remove(service);
                            }),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Fuera de la lista: el boton tiene que estar siempre a la
                  // vista, sin importar cuantas ODT haya.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedServices.isEmpty
                          ? null
                          : () => Navigator.pop(
                                sheetContext,
                                (
                                  selectedOdts.toList()..sort(),
                                  Set<EquipmentReportType>.of(selectedServices),
                                ),
                              ),
                      icon: const Icon(Icons.print_rounded),
                      label: Text(selectedOdts.length > 1
                          ? 'IMPRIMIR ${selectedOdts.length} REPORTES'
                          : 'IMPRIMIR SELECCIÓN'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selection == null || !mounted) return;
    try {
      final (odts, servicios) = selection;
      // Secuencial a proposito: request() espera la confirmacion de la laptop
      // antes de devolver, y la solicitud viaja por un unico archivo. En
      // paralelo se pisarian una a otra.
      var enviados = 0;
      String ultimo = '';
      for (final odt in odts) {
        final order = orders.firstWhere((item) => odtOf(item) == odt);
        // Cada ODT imprime solo los servicios que ella misma registro.
        final propios = servicios.intersection(available(order));
        if (propios.isEmpty) continue;
        ultimo = await EquipmentReportService.request(
          equipo: equipo,
          type: propios.first,
          types: propios,
          print: true,
          odt: odt,
          officialForm: true,
        );
        enviados++;
      }
      if (!mounted) return;
      avisar(
          context,
          enviados == 0
              ? 'Las mediciones elegidas no tienen esos servicios.'
              : enviados == 1
                  ? ultimo
                  : '$enviados reportes enviados a la laptop.',
          enviados == 0 ? AppColors.warning : AppColors.tealDark);
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No se pudo imprimir'),
          content: Text(mensajeDeError(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ENTENDIDO'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return IndustrialShell(
      activeRoute: '/ruta',
      child: Scaffold(
        backgroundColor: esterThemeController.isDark
            ? AppColors.bg
            : const Color(0xFFF7FAFE),
        body: Column(
          children: [
            IndustrialContentHeader(
              title: 'Equipos',
              subtitle:
                  '${_equipos.length} equipos · operaciones y reportes PDF',
              icon: Icons.precision_manufacturing_rounded,
              actions: [
                IconButton(
                  tooltip: 'Actualizar últimas lecturas',
                  onPressed: _refreshing
                      ? null
                      : () => _load(actualizarServidor: true),
                  icon: _refreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.teal))
                      : const Icon(Icons.refresh_rounded),
                )
              ],
            ),
            Container(
              color: esterThemeController.isDark
                  ? AppColors.surface
                  : Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
                  // Arriba del buscador: dar de alta un equipo es lo primero
                  // que se hace cuando la planta monta uno, antes de poder
                  // buscarlo o medirlo.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _registrarEquipo,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 19),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.teal,
                        side: BorderSide(
                          color: AppColors.teal.withValues(alpha: .5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      label: Text(
                        'REGISTRAR EQUIPO NUEVO',
                        style: AppText.cuerpoFuerte.copyWith(letterSpacing: .3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setState(() => _busqueda = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar equipo, localización o código QR…',
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _sistemas.length,
                      itemBuilder: (_, index) {
                        final sistema = _sistemas[index];
                        final active = sistema == _sistemaFiltro;
                        return GestureDetector(
                          onTap: () => setState(() => _sistemaFiltro = sistema),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: active ? AppColors.primary : AppColors.bg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              // En la base el sistema se llama AIRE
                              // COMPRIMIDO, pero en planta a estos equipos se
                              // les dice compresores. El filtro sigue usando
                              // el nombre real; solo cambia lo que se lee.
                              sistema == 'AIRE COMPRIMIDO'
                                  ? EquipoService.etiquetaAireComprimido
                                  : sistema,
                              style: AppText.apoyo.copyWith(
                                color: active
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: AppColors.warningBg,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  'Se muestran los datos guardados en la tablet. $_error',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.apoyo.copyWith(color: AppColors.warning),
                ),
              ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (lista.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No hay equipos que coincidan con el filtro.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(actualizarServidor: true),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: lista.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.02,
                    ),
                    itemBuilder: (_, index) {
                      final equipo = lista[index];
                      return IndustrialEquipmentCard(
                        equipo: equipo,
                        ultima: _ultimas[equipo.localizacion],
                        pendingCount: _pendingCounts[equipo.localizacion] ?? 0,
                        onTap: () => _showEquipmentActions(equipo),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentActionTile extends StatelessWidget {
  const _EquipmentActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    return Material(
      color: primary
          ? AppColors.teal.withValues(alpha: dark ? .18 : .10)
          : dark
              ? AppColors.surface2
              : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary
                  ? AppColors.teal.withValues(alpha: .55)
                  : dark
                      ? AppColors.border
                      : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.seccion),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: AppText.apoyo.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.teal),
          ]),
        ),
      ),
    );
  }
}
