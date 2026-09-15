import 'dart:async';

import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/component_catalog.dart';
import '../models/operation_flow.dart';
import '../models/orden_reparacion.dart';
import '../models/replacement_request.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import 'ordenes_reparacion_screen.dart';

/// Inventario de piezas por tipo: motor, bomba, caja y ventilador.
///
/// Lee la copia local, que baja entera en cada sincronizacion por USB, y
/// refresca contra la API si hay señal. En campo no puede depender de la red.
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen>
    with SingleTickerProviderStateMixin {
  static const _tipos = <ReplacementComponent>[
    ReplacementComponent.motor,
    ReplacementComponent.pump,
    ReplacementComponent.gearbox,
    ReplacementComponent.fan,
  ];

  late final TabController _tabs;
  final _buscador = TextEditingController();
  final Map<int, List<ComponentCatalogItem>> _porTipo = {};
  final Set<int> _cargando = {};
  String _filtroEstado = 'TODOS';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tipos.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _buscador.addListener(() => setState(() {}));
    for (final componente in _tipos) {
      _cargar(replacementComponentCode(componente));
    }
    _contarOrdenes();
  }

  Future<void> _contarOrdenes() async {
    try {
      await DbHelper.instance.refrescarContadoresOrdenes();
    } catch (_) {
      // Sin la tabla todavia: el acceso se muestra sin contador.
    }
  }

  Future<void> _abrirOrdenes() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OrdenesReparacionScreen(),
      ),
    );
    if (!mounted) return;
    // Al volver puede haberse creado o cerrado una orden, y eso cambia el
    // estatus de alguna pieza del inventario.
    _contarOrdenes();
    for (final componente in _tipos) {
      _cargar(replacementComponentCode(componente));
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar(int tipo, {bool forzarRed = false}) async {
    setState(() => _cargando.add(tipo));
    try {
      final cache = await DbHelper.instance.getComponentCatalog(tipo);
      final local =
          cache.map(ComponentCatalogItem.fromLocalMap).toList(growable: false);
      if (mounted && local.isNotEmpty) {
        setState(() => _porTipo[tipo] = local);
      }

      if (local.isEmpty || forzarRed) {
        final fresco = await ApiService.instance.fetchComponentCatalog(tipo);
        await DbHelper.instance.saveComponentCatalog(
          tipo,
          fresco.map((item) => item.toLocalMap()).toList(),
        );
        if (mounted) setState(() => _porTipo[tipo] = fresco);
      } else {
        unawaited(_refrescar(tipo));
      }
    } catch (_) {
      // Sin señal el inventario local sigue sirviendo.
    } finally {
      if (mounted) setState(() => _cargando.remove(tipo));
    }
  }

  Future<void> _refrescar(int tipo) async {
    try {
      final fresco = await ApiService.instance.fetchComponentCatalog(tipo);
      await DbHelper.instance.saveComponentCatalog(
        tipo,
        fresco.map((item) => item.toLocalMap()).toList(),
      );
      if (mounted) setState(() => _porTipo[tipo] = fresco);
    } catch (_) {
      // En campo es lo normal.
    }
  }

  // Las listas de estatus y de sitios viven en replacement_request.dart: son
  // las mismas que usa el reemplazo y no deben poder divergir.

  List<ComponentCatalogItem> _visibles(int tipo) {
    final todas = _porTipo[tipo] ?? const <ComponentCatalogItem>[];
    final texto = _buscador.text.trim().toUpperCase();
    return todas.where((pieza) {
      if (_filtroEstado != 'TODOS' && pieza.estadoTexto != _filtroEstado) {
        return false;
      }
      return texto.isEmpty || pieza.busqueda.contains(texto);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tipoActual = replacementComponentCode(_tipos[_tabs.index]);
    final piezas = _visibles(tipoActual);
    final total = (_porTipo[tipoActual] ?? const []).length;

    return IndustrialShell(
      activeRoute: '/equipos',
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: IndustrialAppBar(
          titulo: 'Componentes de equipos',
          subtitulo: 'Inventario y disponibilidad',
          panel: true,
          actions: [
            IconButton(
              tooltip: 'Actualizar desde el servidor',
              onPressed: _cargando.contains(tipoActual)
                  ? null
                  : () => _cargar(tipoActual, forzarRed: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: AppColors.teal,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFB8C7DE),
            tabs: [
              for (final componente in _tipos)
                Tab(text: replacementComponentLabel(componente)),
            ],
          ),
        ),
        body: Column(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge(
                [ordenesAbiertasNotifier, ordenesSinEnviarNotifier],
              ),
              builder: (context, _) => _AccesoOrdenes(
                abiertas: ordenesAbiertasNotifier.value,
                sinEnviar: ordenesSinEnviarNotifier.value,
                onTap: _abrirOrdenes,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: TextField(
                controller: _buscador,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Buscar por serial, marca, modelo o equipo',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _buscador.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _buscador.clear(),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final estado in const [
                    'TODOS',
                    'DISPONIBLE',
                    'INSTALADO',
                    'AVERIADO',
                    estadoEnReparacion,
                    'DESECHADO',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(estado),
                        selected: _filtroEstado == estado,
                        selectedColor: AppColors.teal,
                        labelStyle: AppText.etiqueta.copyWith(
                          color: _filtroEstado == estado ? Colors.white : null,
                        ),
                        onSelected: (_) =>
                            setState(() => _filtroEstado = estado),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    '${piezas.length} de $total piezas',
                    style: AppText.dato.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_cargando.contains(tipoActual))
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(
              child: piezas.isEmpty
                  ? _Vacio(
                      cargando: _cargando.contains(tipoActual),
                      hayDatos: total > 0,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                      itemCount: piezas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (_, i) => _PiezaCard(pieza: piezas[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ilustracion representativa de cada tipo de pieza.
///
/// Es una por tipo, no una por unidad: la planta no tiene foto de cada motor,
/// y poner la misma imagen repetida como si fuera la pieza real seria
/// engañoso. Sirve para reconocer de que se habla de un vistazo.
const _fotoTipo = <int, String>{
  1: 'assets/images/pieza_motor.jpg',
  2: 'assets/images/pieza_bomba.jpg',
  3: 'assets/images/pieza_caja.jpg',
  4: 'assets/images/pieza_ventilador.jpg',
};

class _PiezaCard extends StatelessWidget {
  const _PiezaCard({required this.pieza});
  final ComponentCatalogItem pieza;

  /// Un color por estado: de un vistazo se ve que hay disponible y que no.
  Color get _color {
    switch (pieza.estadoTexto) {
      case 'DISPONIBLE':
        return AppColors.success;
      case 'AVERIADO':
      case 'AVERIA':
        return AppColors.warning;
      case 'DESECHADO':
        return AppColors.error;
      default:
        return AppColors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  // Las fotos nuevas ya vienen oscuras y en la paleta de la
                  // app: no hace falta el filtro de brillo que necesitaban los
                  // renders de fondo claro.
                  child: Image.asset(
                    _fotoTipo[pieza.tipo] ?? _fotoTipo[1]!,
                    fit: BoxFit.cover,
                    // Se dibuja a 54 px logicos; decodificarla mas grande solo
                    // gasta memoria en una lista que puede tener cientos de
                    // filas.
                    cacheWidth:
                        (54 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.bg2,
                      child: const Icon(Icons.settings_rounded,
                          color: AppColors.textSecondary, size: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  pieza.titulo,
                  style: AppText.seccion.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _color.withValues(alpha: .45)),
                ),
                child: Text(
                  pieza.estadoTexto,
                  style: AppText.micro.copyWith(color: _color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Linea(icono: Icons.tag_rounded, texto: 'Serial ${pieza.serial}'),
          _Linea(
            icono: pieza.instalado
                ? Icons.precision_manufacturing_rounded
                : Icons.warehouse_rounded,
            texto: pieza.ubicacionTexto,
          ),
          if ((pieza.ultimaFecha ?? '').isNotEmpty)
            _Linea(
              icono: Icons.event_rounded,
              texto: 'Ultimo movimiento: ${pieza.ultimaFecha}',
            ),
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
          children: [
            Icon(icono, size: 14, color: AppColors.textSecondary),
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
  const _Vacio({required this.cargando, required this.hayDatos});
  final bool cargando;
  final bool hayDatos;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 52, color: AppColors.teal),
            const SizedBox(height: 12),
            Text(
              hayDatos
                  ? 'Ninguna pieza coincide con el filtro'
                  : 'El inventario aun no se ha descargado',
              textAlign: TextAlign.center,
              style: AppText.seccion.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hayDatos
                  ? 'Prueba con otro estado o limpia la busqueda.'
                  : 'Sincroniza la tablet por USB para traerlo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acceso a las ordenes de reparacion, arriba del inventario.
///
/// Va aqui y no escondido en un menu porque el pendiente de una orden abierta
/// es lo primero que el supervisor necesita ver al entrar a componentes.
class _AccesoOrdenes extends StatelessWidget {
  const _AccesoOrdenes({
    required this.abiertas,
    required this.sinEnviar,
    required this.onTap,
  });

  final int abiertas;

  /// Ordenes que aun no han subido. Manda sobre [abiertas] al pintar el aviso:
  /// una orden sin sincronizar bloquea al tecnico, una abierta solo lo espera.
  final int sinEnviar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hayPendientes = abiertas > 0 || sinEnviar > 0;
    final color = sinEnviar > 0
        ? AppColors.error
        : abiertas > 0
            ? AppColors.warning
            : AppColors.teal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hayPendientes
                    ? color.withValues(alpha: .55)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: .40)),
                  ),
                  child: Icon(Icons.assignment_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ordenes de reparacion',
                        style: AppText.seccion.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sinEnviar > 0
                            ? sinEnviar == 1
                                ? '1 sin sincronizar · no se puede finalizar'
                                : '$sinEnviar sin sincronizar · no se pueden '
                                    'finalizar'
                            : abiertas > 0
                                ? '$abiertas sin finalizar'
                                : 'Llevar una pieza a reparar',
                        style: AppText.cuerpoFuerte.copyWith(
                          color:
                              hayPendientes ? color : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hayPendientes)
                  Container(
                    constraints: const BoxConstraints(minWidth: 26),
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${sinEnviar > 0 ? sinEnviar : abiertas}',
                      style: AppText.dato.copyWith(color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
