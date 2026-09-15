import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/component_catalog.dart';
import '../models/orden_reparacion.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/avisos.dart';

/// Cuantos dias afuera dejan de ser normales.
///
/// Pasado ese punto la orden se pinta distinto: al supervisor no le sirve una
/// lista donde una orden de tres dias y una de dos meses se ven igual.
const _diasParaAlerta = 15;

const _tiposComponente = <int, String>{
  1: 'Motor',
  2: 'Bomba',
  3: 'Caja',
  4: 'Ventilador',
};

const _iconoTipo = <int, IconData>{
  1: Icons.bolt_rounded,
  2: Icons.water_drop_rounded,
  3: Icons.settings_rounded,
  4: Icons.air_rounded,
};

/// Ordenes de reparacion de componentes rotativos.
///
/// Todo sale de la copia local: la orden se crea en el taller, donde muchas
/// veces no hay señal, y viaja al servidor en la siguiente sincronizacion.
class OrdenesReparacionScreen extends StatefulWidget {
  const OrdenesReparacionScreen({super.key});

  @override
  State<OrdenesReparacionScreen> createState() =>
      _OrdenesReparacionScreenState();
}

class _OrdenesReparacionScreenState extends State<OrdenesReparacionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<OrdenReparacion> _abiertas = const [];
  List<OrdenReparacion> _cerradas = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // El FAB solo tiene sentido en la pestaña de abiertas, por eso hay que
    // repintar al cambiar de pestaña.
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      // Una sola consulta y se parte aqui. Antes eran dos viajes a SQLite para
      // leer la misma tabla, y cada uno cuesta un cruce del canal de
      // plataforma.
      final todas = await DbHelper.instance.getOrdenesReparacion();
      if (!mounted) return;
      // Un solo setState: cada uno reconstruye la pantalla entera, barra
      // lateral incluida.
      setState(() {
        _abiertas = todas.where((o) => o.abierta).toList(growable: false);
        _cerradas = todas.where((o) => !o.abierta).toList(growable: false);
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _aviso(String texto, Color color) {
    if (!mounted) return;
    avisar(context, texto, color, duracion: const Duration(seconds: 4));
  }

  Future<void> _nuevaOrden() async {
    final datos = await showModalBottomSheet<_DatosNuevaOrden>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _NuevaOrdenSheet(),
    );
    if (datos == null || !mounted) return;

    // El usuario y el cargo son los mismos que firma el resto de la app: la
    // orden tiene que quedar atribuida a quien saco la pieza de planta.
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().toIso8601String();
    final orden = OrdenReparacion(
      uuid: const Uuid().v4(),
      tipo: datos.pieza.tipo,
      serial: datos.pieza.serial,
      marca: datos.pieza.marca,
      modelo: datos.pieza.modelo,
      ubicacionOrigen: datos.pieza.localizacion,
      destino: datos.destino,
      motivo: datos.motivo,
      fechaSalida: ahora.substring(0, 10),
      horaSalida: ahora.substring(11, 19),
      usuarioSalida:
          (prefs.getString('responsable') ?? prefs.getString('username'))
              ?.trim(),
      cargoSalida: (prefs.getString('cargo') ?? prefs.getString('rol'))?.trim(),
      estadoOrden: 'ABIERTA',
    );

    await DbHelper.instance.crearOrdenReparacion(orden);
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    _tabs.animateTo(0);
    _aviso(
      'Orden creada. ${orden.serial} queda EN REPARACION en ${orden.destino}.',
      AppColors.success,
    );
  }

  Future<void> _finalizar(OrdenReparacion orden) async {
    // La orden tiene que haber subido antes de poder cerrarse. Si no, apertura
    // y cierre viajarian en el mismo paquete y en el servidor quedaria una
    // orden que nacio cerrada, sin rastro de que la pieza estuvo afuera.
    if (!orden.puedeFinalizarse) {
      _aviso(
        'Primero sincroniza la orden de ${orden.serial}. Hasta que suba solo '
        'existe en esta tablet y no se puede finalizar.',
        AppColors.warning,
      );
      return;
    }

    final cierre = await showModalBottomSheet<_DatosCierre>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CerrarOrdenSheet(orden: orden),
    );
    if (cierre == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().toIso8601String();
    final cerrada = orden.cerrar(
      fecha: ahora.substring(0, 10),
      hora: ahora.substring(11, 19),
      resultado: cierre.resultado,
      trabajoRealizado: cierre.trabajoRealizado,
      ubicacionFinal: cierre.ubicacionFinal,
      observaciones: cierre.observaciones,
      usuario: (prefs.getString('responsable') ?? prefs.getString('username'))
          ?.trim(),
      cargo: (prefs.getString('cargo') ?? prefs.getString('rol'))?.trim(),
    );

    await DbHelper.instance.cerrarOrdenReparacion(cerrada);
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    _tabs.animateTo(1);
    _aviso(
      'Orden cerrada. ${cerrada.serial} queda ${cerrada.estadoPieza}.',
      AppColors.success,
    );
  }

  Future<void> _eliminar(OrdenReparacion orden) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Descartar la orden'),
        content: Text(
          'Se borrara la orden de ${orden.serial}. Solo se puede descartar '
          'porque todavia no se ha enviado al servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('DESCARTAR'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    await DbHelper.instance.deleteOrdenReparacion(orden.uuid);
    if (!mounted) return;
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialShell(
      activeRoute: '/equipos',
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: IndustrialAppBar(
          titulo: 'Órdenes de reparación',
          subtitulo: 'Seguimiento de trabajos y retornos',
          panel: true,
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: AppColors.teal,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFB8C7DE),
            tabs: [
              Tab(text: 'Abiertas (${_abiertas.length})'),
              const Tab(text: 'Finalizadas'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _nuevaOrden,
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'NUEVA ORDEN',
            style: AppText.cuerpoFuerte,
          ),
        ),
        body: _cargando && _abiertas.isEmpty && _cerradas.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabs,
                children: [
                  _ListaOrdenes(
                    ordenes: _abiertas,
                    onFinalizar: _finalizar,
                    onEliminar: _eliminar,
                    vacio: const _Vacio(
                      icono: Icons.build_circle_outlined,
                      titulo: 'No hay piezas en reparacion',
                      detalle:
                          'Cuando saques un componente a un taller, abre una '
                          'orden con NUEVA ORDEN para dejar constancia.',
                    ),
                  ),
                  _ListaOrdenes(
                    ordenes: _cerradas,
                    onFinalizar: null,
                    onEliminar: null,
                    vacio: const _Vacio(
                      icono: Icons.task_alt_rounded,
                      titulo: 'Todavia no has cerrado ninguna orden',
                      detalle:
                          'Al volver la pieza del taller, pulsa FINALIZAR en '
                          'su tarjeta y quedara registrada aqui.',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── LISTA ───────────────────────────────────────────────────────────────────

class _ListaOrdenes extends StatelessWidget {
  const _ListaOrdenes({
    required this.ordenes,
    required this.onFinalizar,
    required this.onEliminar,
    required this.vacio,
  });

  final List<OrdenReparacion> ordenes;
  final void Function(OrdenReparacion)? onFinalizar;
  final void Function(OrdenReparacion)? onEliminar;
  final Widget vacio;

  @override
  Widget build(BuildContext context) {
    if (ordenes.isEmpty) return vacio;
    return ListView.separated(
      // Espacio abajo para que el FAB no tape la ultima tarjeta.
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 92),
      itemCount: ordenes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, i) => _OrdenCard(
        orden: ordenes[i],
        onFinalizar:
            onFinalizar == null ? null : () => onFinalizar!(ordenes[i]),
        onEliminar: onEliminar == null ? null : () => onEliminar!(ordenes[i]),
      ),
    );
  }
}

// ── TARJETA ─────────────────────────────────────────────────────────────────

class _OrdenCard extends StatelessWidget {
  const _OrdenCard({
    required this.orden,
    required this.onFinalizar,
    required this.onEliminar,
  });

  final OrdenReparacion orden;
  final VoidCallback? onFinalizar;
  final VoidCallback? onEliminar;

  /// El color resume el desenlace: abierta ambar, y cerrada segun como volvio.
  Color get _color {
    if (orden.abierta) return AppColors.warning;
    switch ((orden.resultado ?? '').trim().toUpperCase()) {
      case 'REPARADO':
        return AppColors.success;
      case 'NO REPARABLE':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  String get _etiqueta =>
      orden.abierta ? 'ABIERTA' : (orden.resultado ?? 'CERRADA').toUpperCase();

  bool get _demorada =>
      orden.abierta && (orden.diasFuera ?? 0) > _diasParaAlerta;

  String get _textoDias {
    final dias = orden.diasFuera;
    if (dias == null) return 'Fecha de salida sin registrar';
    if (orden.abierta) {
      if (dias <= 0) return 'Salio hoy';
      return dias == 1 ? 'Lleva 1 dia fuera' : 'Lleva $dias dias fuera';
    }
    if (dias <= 0) return 'Volvio el mismo dia';
    return dias == 1 ? 'Estuvo 1 dia fuera' : 'Estuvo $dias dias fuera';
  }

  @override
  Widget build(BuildContext context) {
    // La demora se marca con el borde y no solo con un texto: la tarjeta tiene
    // que saltar a la vista al hacer scroll rapido por la lista.
    final borde = _demorada ? AppColors.error : AppColors.border;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _demorada ? borde.withValues(alpha: .7) : borde,
          width: _demorada ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _color.withValues(alpha: .35)),
                ),
                child: Icon(
                  _iconoTipo[orden.tipo] ?? Icons.settings_rounded,
                  color: _color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      orden.nombreTipo.toUpperCase(),
                      style: AppText.micro.copyWith(
                        color: AppColors.textHint,
                        letterSpacing: .6,
                      ),
                    ),
                    Text(
                      orden.titulo,
                      style: AppText.seccion.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _color.withValues(alpha: .45)),
                    ),
                    child: Text(
                      _etiqueta,
                      style: AppText.micro.copyWith(color: _color),
                    ),
                  ),
                  if (!orden.sincronizado)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 11,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'SIN ENVIAR',
                            style: AppText.micro.copyWith(
                              color: AppColors.textHint,
                              letterSpacing: .4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          _Linea(icono: Icons.tag_rounded, texto: 'Serial ${orden.serial}'),
          _Linea(
            icono: Icons.local_shipping_rounded,
            texto: orden.abierta
                ? 'En ${orden.destino}'
                : 'Fue a ${orden.destino}',
          ),
          if ((orden.motivo ?? '').isNotEmpty)
            _Linea(
              icono: Icons.report_problem_outlined,
              texto: 'Motivo: ${orden.motivo}',
            ),
          _Linea(
            icono: Icons.person_outline_rounded,
            texto: (orden.usuarioSalida ?? '').isEmpty
                ? 'Salio el ${orden.fechaSalida} · responsable sin registrar'
                : 'Salio el ${orden.fechaSalida} · ${orden.usuarioSalida}',
          ),
          if (!orden.abierta && (orden.trabajoRealizado ?? '').isNotEmpty)
            _Linea(
              icono: Icons.handyman_outlined,
              texto: 'Trabajo: ${orden.trabajoRealizado}',
            ),
          if (!orden.abierta && (orden.ubicacionFinal ?? '').isNotEmpty)
            _Linea(
              icono: Icons.warehouse_rounded,
              texto: 'Quedo en ${orden.ubicacionFinal}',
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: (_demorada ? AppColors.error : AppColors.bg2)
                  .withValues(alpha: _demorada ? .14 : 1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _demorada
                    ? AppColors.error.withValues(alpha: .4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _demorada
                      ? Icons.warning_amber_rounded
                      : Icons.schedule_rounded,
                  size: 16,
                  color: _demorada ? AppColors.error : AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _demorada
                        ? '$_textoDias · pasa de $_diasParaAlerta dias, reclama al taller'
                        : _textoDias,
                    style: AppText.cuerpoFuerte.copyWith(
                      color:
                          _demorada ? AppColors.error : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Mientras la orden no suba solo existe en esta tablet: no se puede
          // finalizar todavia. Se dice aqui y no solo al pulsar el boton
          // porque el tecnico necesita saber que le falta antes de ir al taller
          // a buscar la pieza.
          if (orden.abierta && !orden.sincronizado) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Falta sincronizar. Sube la orden desde SINCRONIZAR y '
                      'recien ahi podras finalizarla.',
                      style: AppText.cuerpoFuerte.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (onFinalizar != null || onEliminar != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                // Descartar solo aparece mientras la orden no ha salido de la
                // tablet: una vez enviada ya no es nuestra para borrarla.
                if (onEliminar != null && orden.puedeDescartarse)
                  TextButton.icon(
                    onPressed: onEliminar,
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textHint,
                    ),
                    label: const Text('DESCARTAR'),
                  ),
                const Spacer(),
                if (onFinalizar != null)
                  FilledButton.icon(
                    // Deshabilitado, no escondido: si desaparece el boton el
                    // tecnico cree que la orden esta rota.
                    onPressed: orden.puedeFinalizarse ? onFinalizar : null,
                    icon: Icon(
                      orden.puedeFinalizarse
                          ? Icons.check_circle_outline_rounded
                          : Icons.lock_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('FINALIZAR'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icono, size: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                texto,
                style: AppText.cuerpoFuerte.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Vacio extends StatelessWidget {
  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 52, color: AppColors.teal),
              const SizedBox(height: 12),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: AppText.seccion.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: AppText.apoyo.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── CREAR: HOJA CON PASOS ───────────────────────────────────────────────────

/// Lo que la hoja devuelve. La orden se arma fuera porque necesita las
/// preferencias del usuario, que no tienen por que vivir en el formulario.
class _DatosNuevaOrden {
  const _DatosNuevaOrden({
    required this.pieza,
    required this.destino,
    required this.motivo,
  });

  final ComponentCatalogItem pieza;
  final String destino;
  final String motivo;
}

class _NuevaOrdenSheet extends StatefulWidget {
  const _NuevaOrdenSheet();

  @override
  State<_NuevaOrdenSheet> createState() => _NuevaOrdenSheetState();
}

class _NuevaOrdenSheetState extends State<_NuevaOrdenSheet> {
  int _paso = 0;
  int _tipo = 1;
  final _buscador = TextEditingController();
  final _motivo = TextEditingController();
  final Map<int, List<ComponentCatalogItem>> _catalogo = {};
  final Set<int> _cargando = {};
  ComponentCatalogItem? _pieza;
  String? _destino;

  @override
  void initState() {
    super.initState();
    _buscador.addListener(() => setState(() {}));
    _motivo.addListener(() => setState(() {}));
    _cargarTipo(_tipo);
  }

  @override
  void dispose() {
    _buscador.dispose();
    _motivo.dispose();
    super.dispose();
  }

  /// Solo la copia local: crear una orden no puede depender de la red.
  Future<void> _cargarTipo(int tipo) async {
    if (_catalogo.containsKey(tipo) || _cargando.contains(tipo)) return;
    setState(() => _cargando.add(tipo));
    try {
      final filas = await DbHelper.instance.getComponentCatalog(tipo);
      final piezas =
          filas.map(ComponentCatalogItem.fromLocalMap).toList(growable: false);
      if (mounted) setState(() => _catalogo[tipo] = piezas);
    } catch (_) {
      if (mounted) setState(() => _catalogo[tipo] = const []);
    } finally {
      if (mounted) setState(() => _cargando.remove(tipo));
    }
  }

  List<ComponentCatalogItem> get _resultados {
    final todas = _catalogo[_tipo] ?? const <ComponentCatalogItem>[];
    final texto = _buscador.text.trim().toUpperCase();
    if (texto.isEmpty) return todas;
    return todas.where((p) => p.busqueda.contains(texto)).toList();
  }

  bool get _pasoCompleto {
    switch (_paso) {
      case 0:
        return _pieza != null;
      case 1:
        return _destino != null && _motivo.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  void _elegir(ComponentCatalogItem pieza) {
    if (pieza.instalado) {
      // Sacar a reparar una pieza montada dejaria el equipo sin registro de
      // que se le puso en su lugar. El reemplazo va primero, siempre.
      avisar(
          context,
          '${pieza.serial} esta instalada en ${pieza.equipo ?? 'un equipo'}. '
          'Registra primero el reemplazo para retirarla; recien ahi se puede '
          'mandar a reparar.',
          AppColors.warning,
          duracion: const Duration(seconds: 5));
      return;
    }
    setState(() => _pieza = pieza);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: media.size.height * .86,
          child: Column(
            children: [
              const _AsaHoja(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nueva orden de reparacion',
                    style: AppText.titulo.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stepper(
                  currentStep: _paso,
                  physics: const ClampingScrollPhysics(),
                  onStepTapped: (indice) {
                    // Solo se puede retroceder: saltar hacia adelante dejaria
                    // pasos sin llenar y el resumen mentiria.
                    if (indice < _paso) setState(() => _paso = indice);
                  },
                  onStepContinue: () {
                    if (!_pasoCompleto) return;
                    if (_paso < 2) {
                      setState(() => _paso += 1);
                    } else {
                      Navigator.pop(
                        context,
                        _DatosNuevaOrden(
                          pieza: _pieza!,
                          destino: _destino!,
                          motivo: _motivo.text.trim(),
                        ),
                      );
                    }
                  },
                  onStepCancel: () {
                    if (_paso == 0) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _paso -= 1);
                    }
                  },
                  controlsBuilder: (context, detalles) => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: detalles.onStepCancel,
                            child: Text(_paso == 0 ? 'CANCELAR' : 'ATRAS'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _pasoCompleto ? detalles.onStepContinue : null,
                            icon: Icon(
                              _paso == 2
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label:
                                Text(_paso == 2 ? 'CREAR ORDEN' : 'SIGUIENTE'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  steps: [
                    Step(
                      title: const Text('Que pieza'),
                      subtitle: _pieza == null
                          ? null
                          : Text('${_pieza!.titulo} · ${_pieza!.serial}'),
                      isActive: _paso >= 0,
                      state: _paso > 0 ? StepState.complete : StepState.indexed,
                      content: _pasoPieza(),
                    ),
                    Step(
                      title: const Text('A donde y por que'),
                      subtitle: _destino == null ? null : Text(_destino!),
                      isActive: _paso >= 1,
                      state: _paso > 1 ? StepState.complete : StepState.indexed,
                      content: _pasoDestino(),
                    ),
                    Step(
                      title: const Text('Confirmar'),
                      isActive: _paso >= 2,
                      state: StepState.indexed,
                      content: _pasoResumen(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pasoPieza() {
    final piezas = _resultados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _tipo,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Tipo de componente',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final entrada in _tiposComponente.entries)
              DropdownMenuItem(value: entrada.key, child: Text(entrada.value)),
          ],
          onChanged: (valor) {
            if (valor == null) return;
            setState(() {
              _tipo = valor;
              // La pieza elegida pertenecia al tipo anterior: mantenerla haria
              // que el resumen no cuadre con lo que se ve en la lista.
              _pieza = null;
            });
            _cargarTipo(valor);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _buscador,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Buscar por serial, marca o modelo',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _buscador.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _buscador.clear,
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Solo las piezas que no estan montadas pueden salir a reparar.',
          style: AppText.apoyo.copyWith(color: AppColors.textHint),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: _cargando.contains(_tipo)
              ? const Center(child: CircularProgressIndicator())
              : piezas.isEmpty
                  ? Center(
                      child: Text(
                        'No hay piezas de este tipo en la copia local.\n'
                        'Sincroniza la tablet para traer el inventario.',
                        textAlign: TextAlign.center,
                        style: AppText.apoyo.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: piezas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (_, i) => _OpcionPieza(
                        pieza: piezas[i],
                        seleccionada: _pieza?.serial == piezas[i].serial &&
                            _pieza?.tipo == piezas[i].tipo,
                        onTap: () => _elegir(piezas[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _pasoDestino() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _destino,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'A donde va',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final destino in destinosReparacion)
              DropdownMenuItem(value: destino, child: Text(destino)),
          ],
          onChanged: (valor) => setState(() => _destino = valor),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _motivo,
          minLines: 3,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Motivo de la salida',
            hintText: 'Que se le detecto: ruido, vibracion, no arranca...',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            errorText: _motivo.text.trim().isEmpty
                ? 'El taller necesita saber que buscar'
                : null,
          ),
        ),
      ],
    );
  }

  Widget _pasoResumen() {
    final pieza = _pieza;
    if (pieza == null || _destino == null) {
      return const Text(
        'Vuelve atras y completa la pieza y el destino.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pieza.titulo,
            style: AppText.seccion.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          _Linea(
            icono: _iconoTipo[pieza.tipo] ?? Icons.settings_rounded,
            texto: '${_tiposComponente[pieza.tipo] ?? 'Componente'} · '
                'serial ${pieza.serial}',
          ),
          _Linea(
            icono: Icons.local_shipping_rounded,
            texto: 'Destino: $_destino',
          ),
          _Linea(
            icono: Icons.report_problem_outlined,
            texto: 'Motivo: ${_motivo.text.trim()}',
          ),
          const _Linea(
            icono: Icons.inventory_2_outlined,
            texto: 'Queda como $estadoEnReparacion hasta que la cierres',
          ),
        ],
      ),
    );
  }
}

class _OpcionPieza extends StatelessWidget {
  const _OpcionPieza({
    required this.pieza,
    required this.seleccionada,
    required this.onTap,
  });

  final ComponentCatalogItem pieza;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bloqueada = pieza.instalado;
    final color = seleccionada
        ? AppColors.teal
        : bloqueada
            ? AppColors.textHint
            : AppColors.border;

    return InkWell(
      // Las instaladas siguen siendo pulsables a proposito: si el tecnico la
      // busca, es mejor explicarle por que no puede que esconderle la pieza.
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: bloqueada ? .55 : 1,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: seleccionada
                ? AppColors.teal.withValues(alpha: .12)
                : AppColors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: seleccionada ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(
                bloqueada
                    ? Icons.lock_outline_rounded
                    : seleccionada
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 19,
                color: seleccionada ? AppColors.teal : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pieza.titulo,
                      style: AppText.seccion.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${pieza.serial} · ${pieza.ubicacionTexto}',
                      style: AppText.apoyo.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pieza.estadoTexto,
                style: AppText.micro.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CERRAR: HOJA DE FINALIZACION ────────────────────────────────────────────

class _DatosCierre {
  const _DatosCierre({
    required this.resultado,
    required this.trabajoRealizado,
    required this.ubicacionFinal,
    required this.observaciones,
  });

  final String resultado;
  final String trabajoRealizado;
  final String? ubicacionFinal;
  final String? observaciones;
}

class _CerrarOrdenSheet extends StatefulWidget {
  const _CerrarOrdenSheet({required this.orden});
  final OrdenReparacion orden;

  @override
  State<_CerrarOrdenSheet> createState() => _CerrarOrdenSheetState();
}

class _CerrarOrdenSheetState extends State<_CerrarOrdenSheet> {
  String _resultado = resultadosReparacion.keys.first;
  String? _ubicacionFinal;
  final _trabajo = TextEditingController();
  final _observaciones = TextEditingController();

  @override
  void initState() {
    super.initState();
    // De vuelta suele quedarse donde la repararon: se propone ese destino y el
    // tecnico solo lo cambia si la movio.
    if (destinosReparacion.contains(widget.orden.destino)) {
      _ubicacionFinal = widget.orden.destino;
    }
    _trabajo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _trabajo.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orden = widget.orden;
    final estadoResultante = resultadosReparacion[_resultado] ?? 'DISPONIBLE';
    final completo = _trabajo.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AsaHoja(),
              Text(
                'Finalizar orden',
                style: AppText.titulo.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${orden.nombreTipo} ${orden.titulo} · serial ${orden.serial}',
                style: AppText.subtitulo.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _resultado,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Como volvio',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final valor in resultadosReparacion.keys)
                    DropdownMenuItem(value: valor, child: Text(valor)),
                ],
                onChanged: (valor) =>
                    setState(() => _resultado = valor ?? _resultado),
              ),
              const SizedBox(height: 6),
              // El estatus de la pieza no se escribe a mano: se muestra para
              // que quede claro que lo decide el resultado elegido arriba.
              Row(
                children: [
                  const Icon(Icons.arrow_forward_rounded,
                      size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'La pieza quedara como $estadoResultante',
                      style: AppText.apoyo.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _trabajo,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Trabajo realizado',
                  hintText: 'Que se le hizo en el taller',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  errorText: completo ? null : 'Obligatorio para cerrar',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _ubicacionFinal,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Donde queda la pieza',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final destino in destinosReparacion)
                    DropdownMenuItem(value: destino, child: Text(destino)),
                ],
                onChanged: (valor) => setState(() => _ubicacionFinal = valor),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observaciones,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !completo
                        ? null
                        : () => Navigator.pop(
                              context,
                              _DatosCierre(
                                resultado: _resultado,
                                trabajoRealizado: _trabajo.text.trim(),
                                ubicacionFinal: _ubicacionFinal,
                                observaciones:
                                    _observaciones.text.trim().isEmpty
                                        ? null
                                        : _observaciones.text.trim(),
                              ),
                            ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('CERRAR ORDEN'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _AsaHoja extends StatelessWidget {
  const _AsaHoja();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 42,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}
