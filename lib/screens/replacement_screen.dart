import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/operation_flow.dart';
import '../models/replacement_request.dart';
import '../models/compatibilidad_equipos.dart';
import '../models/component_catalog.dart';
import '../db/db_helper.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/replacement_focus_image.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/avisos.dart';

typedef ReplacementSaver = Future<ReplacementSaveResult> Function(
  ReplacementRequest request,
);

class ReplacementScreen extends StatefulWidget {
  const ReplacementScreen({
    super.key,
    required this.equipo,
    this.saveReplacement,
    this.odt,
  });

  final Equipo equipo;
  final ReplacementSaver? saveReplacement;
  final int? odt;

  @override
  State<ReplacementScreen> createState() => _ReplacementScreenState();
}

class _ReplacementScreenState extends State<ReplacementScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<ReplacementComponent, _ReplacementFields> _fields = {
    for (final component in ReplacementComponent.values)
      component: _ReplacementFields(),
  };
  final Set<ReplacementComponent> _selected = <ReplacementComponent>{};
  final Set<ReplacementComponent> _loadingCatalog = <ReplacementComponent>{};

  late final List<ReplacementComponent> _available;
  bool _updateMotorTechnicalSpecs = false;
  bool _reviewing = false;
  bool _finishing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _available = ReplacementComponentResolver.fromPuntos(widget.equipo.ptEq);
  }

  @override
  void dispose() {
    for (final fields in _fields.values) {
      fields.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges => _selected.isNotEmpty;

  /// Piezas ya registradas de ese tipo.
  ///
  /// El catalogo baja entero por USB en cada sincronizacion, asi que la copia
  /// local es la fuente de verdad en campo. Si ya hay datos se devuelven de
  /// inmediato y el refresco por red se hace aparte: hacer esperar un timeout
  /// de red al mecanico que esta sin señal no aporta nada.
  Future<List<ComponentCatalogItem>> _loadCatalog(
    ReplacementComponent component,
  ) async {
    final tipo = replacementComponentCode(component);
    final cached = await DbHelper.instance.getComponentCatalog(tipo);
    final local =
        cached.map(ComponentCatalogItem.fromLocalMap).toList(growable: false);

    if (local.isNotEmpty) {
      unawaited(_refrescarCatalogo(tipo));
      return local;
    }

    // Sin copia local si que vale la pena intentar la red: es la unica opcion.
    try {
      final fresh = await ApiService.instance.fetchComponentCatalog(tipo);
      await DbHelper.instance.saveComponentCatalog(
        tipo,
        fresh.map((item) => item.toLocalMap()).toList(),
      );
      return fresh;
    } catch (_) {
      return local;
    }
  }

  Future<void> _refrescarCatalogo(int tipo) async {
    try {
      final fresh = await ApiService.instance.fetchComponentCatalog(tipo);
      await DbHelper.instance.saveComponentCatalog(
        tipo,
        fresh.map((item) => item.toLocalMap()).toList(),
      );
    } catch (_) {
      // Sin señal en campo es lo normal: sigue valiendo lo que bajo por USB.
    }
  }

  Future<void> _pickRegistered(ReplacementComponent component) async {
    setState(() => _loadingCatalog.add(component));
    final List<ComponentCatalogItem> todas;
    try {
      todas = await _loadCatalog(component);
    } finally {
      if (mounted) setState(() => _loadingCatalog.remove(component));
    }
    if (!mounted) return;

    if (todas.isEmpty) {
      avisar(
        context,
        'El catálogo aún no se ha descargado. Sincroniza la tablet por USB. '
        'Mientras tanto puedes escribir los datos abajo.',
        AppColors.warning,
        duracion: const Duration(seconds: 5),
      );
      return;
    }

    // Solo las piezas de la misma familia que este equipo. Un motor de un
    // FIN FAN no sirve en una bomba de patin, y ofrecerselo al mecanico es
    // invitarlo a montar algo que no encaja.
    final destino = widget.equipo.localizacion;
    final items = todas
        .where((pieza) => CompatibilidadEquipos.compatible(
              origen: pieza.localizacion,
              destino: destino,
            ))
        .toList();

    if (items.isEmpty) {
      avisar(
        context,
        'No hay ${replacementComponentLabel(component).toLowerCase()} '
        'compatible con ${CompatibilidadEquipos.nombreFamilia(destino)}. '
        'De ${todas.length} registradas, ninguna sirve para este equipo.',
        AppColors.warning,
        duracion: const Duration(seconds: 6),
      );
      return;
    }

    final chosen = await showModalBottomSheet<ComponentCatalogItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CatalogPicker(
        titulo: replacementComponentLabel(component),
        items: items,
      ),
    );
    if (chosen == null || !mounted) return;

    // La pieza sigue montada en otro equipo. No se bloquea, se avisa: puede ser
    // un traslado real que aun no se ha registrado alla.
    if (chosen.instalado) {
      final donde = (chosen.equipo ?? '').trim().isEmpty
          ? 'el equipo ${chosen.localizacion ?? '?'}'
          : '${chosen.equipo} (loc. ${chosen.localizacion ?? '?'})';
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Esta pieza está instalada'),
          content: Text(
            'El serial ${chosen.serial} figura montado en $donde.\n\n'
            'Si la usas aquí, quedará registrada en los dos equipos hasta que '
            'alguien registre el reemplazo en el otro.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCELAR')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('USARLA IGUAL')),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
    }

    final fields = _fields[component]!;
    setState(() {
      fields.brand.text = chosen.marca;
      fields.model.text = chosen.modelo;
      fields.serial.text = chosen.serial;
    });
  }

  Future<bool> _confirmExit() async {
    if (!_hasChanges || _finishing) return true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salir del reemplazo'),
        content: const Text(
          'Los datos ingresados no se han terminado. Deseas salir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuar editando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return exit == true;
  }

  Future<void> _requestClose([Object? result]) async {
    if (!await _confirmExit() || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _toggleComponent(ReplacementComponent component) async {
    if (_selected.contains(component)) {
      setState(() => _selected.remove(component));
      return;
    }

    var updateTechnicalSpecs = false;
    if (component == ReplacementComponent.motor) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Especificaciones del motor'),
          content: const Text(
            'Quieres cambiar tambien las especificaciones tecnicas del motor? Si respondes no, se conservaran los datos tecnicos actuales.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No, conservarlas'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Si, cambiarlas'),
            ),
          ],
        ),
      );
      if (answer == null || !mounted) return;
      updateTechnicalSpecs = answer;
    }

    setState(() {
      _selected.add(component);
      if (component == ReplacementComponent.motor) {
        _updateMotorTechnicalSpecs = updateTechnicalSpecs;
      }
    });
  }

  void _review() {
    if (_selected.isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _reviewing = true);
  }

  Future<void> _complete() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final request = ReplacementRequest(
      equipo: widget.equipo,
      components: {
        for (final component in _selected)
          component: _fields[component]!.toData(
            updateTechnicalSpecs: component == ReplacementComponent.motor &&
                _updateMotorTechnicalSpecs,
          ),
      },
      odt: widget.odt,
    );

    final saver = widget.saveReplacement ?? _saveLocally;
    final result = await saver(request);
    if (!mounted) return;

    if (!result.ok) {
      setState(() => _finishing = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.error),
              SizedBox(width: 10),
              Expanded(child: Text('No se pudo guardar localmente')),
            ],
          ),
          content: Text(
            result.error ?? 'SQLite rechazo el reemplazo.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Revisar'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.teal),
            SizedBox(width: 10),
            Expanded(child: Text('Reemplazo guardado')),
          ],
        ),
        content: const Text(
          'El reemplazo fue guardado en la tablet. Queda pendiente de sincronizacion y se subira a MariaDB mediante la conexion USB con la laptop.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _requestClose(result);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: IndustrialAppBar(
          titulo: _reviewing ? 'Revisar reemplazo' : 'Reemplazo de equipo',
          leading: IconButton(
            tooltip: 'Atrás',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (_reviewing) {
                setState(() => _reviewing = false);
                return;
              }
              await _requestClose();
            },
          ),
        ),
        body: _available.isEmpty
            ? _unsupportedEquipment()
            : _reviewing
                ? _reviewBody()
                : _captureBody(),
      ),
    );
  }

  Widget _unsupportedEquipment() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 14),
            Text(
              'Composicion no configurada',
              style: AppText.titulo.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'El tipo PUNTOS ${widget.equipo.ptEq} no tiene componentes definidos para reemplazo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureBody() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _equipmentHeader(),
                const SizedBox(height: 14),
                ReplacementFocusImage(
                  equipo: widget.equipo,
                  selected: _selected,
                ),
                const SizedBox(height: 20),
                Text(
                  'Que componente se reemplazo?',
                  style: AppText.titulo.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Selecciona uno o varios componentes e ingresa sus datos nuevos.',
                  style: AppText.subtitulo
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                for (final component in _available) ...[
                  _componentSection(component),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('review-replacement-button'),
                onPressed: _selected.isEmpty ? null : _review,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar reemplazo'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _componentSection(ReplacementComponent component) {
    final selected = _selected.contains(component);
    final name = _componentLabel(component);
    final slug = component.name;
    final fields = _fields[component]!;

    final loading = _loadingCatalog.contains(component);

    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.surface2 : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: selected ? AppColors.shadowSm : null,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('component-$slug'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => _toggleComponent(component),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.teal.withValues(alpha: .16)
                            : AppColors.bg2,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: selected
                              ? AppColors.teal.withValues(alpha: .40)
                              : AppColors.borderDark,
                        ),
                      ),
                      child: Icon(
                        _componentIcon(component),
                        size: 22,
                        color: selected
                            ? AppColors.teal
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: AppText.seccion
                                  .copyWith(color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            _estadoComponente(component, fields),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitulo.copyWith(
                              color: !selected
                                  ? AppColors.textHint
                                  : (fields.completo
                                      ? AppColors.teal
                                      : AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.teal : AppColors.borderDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      key: Key('pick-registered-$slug'),
                      onPressed:
                          loading ? null : () => _pickRegistered(component),
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.inventory_2_outlined, size: 19),
                      label: Text(loading
                          ? 'Buscando piezas...'
                          : 'Elegir una ya registrada'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('o registra una nueva',
                          style: AppText.etiqueta
                              .copyWith(color: AppColors.textHint)),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ]),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: Key('brand-$slug'),
                    controller: fields.brand,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Marca'),
                    onChanged: (_) => setState(() {}),
                    validator: (value) => _required(value, 'Ingresa la marca'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: Key('model-$slug'),
                    controller: fields.model,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                    onChanged: (_) => setState(() {}),
                    validator: (value) => _required(value, 'Ingresa el modelo'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: Key('serial-$slug'),
                    controller: fields.serial,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Serial'),
                    onChanged: (_) => setState(() {}),
                    validator: (value) => _required(value, 'Ingresa el serial'),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('la pieza que sale',
                          style: AppText.etiqueta
                              .copyWith(color: AppColors.textHint)),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: Key('motivo-$slug'),
                    initialValue: fields.motivo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Que se dano? (opcional)',
                      prefixIcon: Icon(Icons.build_circle_outlined, size: 20),
                    ),
                    items: [
                      for (final dano in danosReemplazo)
                        DropdownMenuItem(value: dano, child: Text(dano)),
                    ],
                    onChanged: (value) =>
                        setState(() => fields.motivo = value),
                  ),
                  const SizedBox(height: 10),
                  // El estatus de la pieza retirada lo decide el tecnico: solo
                  // el sabe si sirve, quedo averiada o se desecha.
                  DropdownButtonFormField<String>(
                    key: Key('estado-saliente-$slug'),
                    initialValue: fields.estadoSaliente,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Como queda la pieza retirada',
                      prefixIcon: Icon(Icons.inventory_rounded, size: 20),
                    ),
                    items: [
                      for (final estado in estadosPieza)
                        DropdownMenuItem(value: estado, child: Text(estado)),
                    ],
                    onChanged: (value) =>
                        setState(() => fields.estadoSaliente = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: Key('sitio-saliente-$slug'),
                    initialValue: fields.sitioSaliente,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'A donde va',
                      prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
                    ),
                    items: [
                      for (final sitio in sitiosPieza)
                        DropdownMenuItem(value: sitio, child: Text(sitio)),
                    ],
                    onChanged: (value) =>
                        setState(() => fields.sitioSaliente = value),
                  ),
                  if (component == ReplacementComponent.motor) ...[
                    const SizedBox(height: 18),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        key: const Key('update-motor-technical-specs'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Cambiar especificaciones tecnicas',
                          style: AppText.seccion
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        value: _updateMotorTechnicalSpecs,
                        activeThumbColor: AppColors.teal,
                        onChanged: (value) => setState(
                          () => _updateMotorTechnicalSpecs = value,
                        ),
                      ),
                    ),
                    if (!_updateMotorTechnicalSpecs)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Se conservaran las especificaciones actuales',
                          style: AppText.apoyo
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    if (_updateMotorTechnicalSpecs) ...[
                      const SizedBox(height: 10),
                      ..._motorTechnicalFields(fields, slug),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Linea de estado bajo el nombre del componente en la tarjeta.
  String _estadoComponente(
    ReplacementComponent component,
    _ReplacementFields fields,
  ) {
    if (!_selected.contains(component)) return 'Sin reemplazo';
    if (!fields.completo) return 'Faltan datos';
    final resumen = [
      fields.brand.text.trim(),
      fields.model.text.trim(),
      fields.serial.text.trim(),
    ].join(' · ');
    return fields.motivo == null ? resumen : '$resumen · ${fields.motivo}';
  }

  Widget _reviewBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _equipmentHeader(),
              const SizedBox(height: 14),
              ReplacementFocusImage(
                equipo: widget.equipo,
                selected: _selected,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storage_outlined,
                        color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verifica cuidadosamente los datos. Al completar se archivara el equipo anterior y se actualizara el equipo en servicio.',
                        style:
                            AppText.apoyo.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final component in _selected) ...[
                _reviewComponent(component),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _reviewing = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('complete-replacement-button'),
                  onPressed: _finishing ? null : _complete,
                  icon: _finishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_finishing ? 'Guardando...' : 'Completar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewComponent(ReplacementComponent component) {
    final fields = _fields[component]!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_componentIcon(component), color: AppColors.tealDark),
              const SizedBox(width: 10),
              Text(
                _componentLabel(component),
                style: AppText.seccion.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const Divider(height: 24),
          _reviewRow('Marca', fields.brand.text.trim()),
          _reviewRow('Modelo', fields.model.text.trim()),
          _reviewRow('Serial', fields.serial.text.trim()),
          if (component == ReplacementComponent.motor &&
              _updateMotorTechnicalSpecs) ...[
            const Divider(height: 20),
            _reviewRow('Voltaje', fields.voltage.text.trim()),
            _reviewRow('Corriente', fields.current.text.trim()),
            _reviewRow('RPM', fields.rpm.text.trim()),
            _reviewRow('SF', fields.serviceFactor.text.trim()),
            _reviewRow('HP', fields.horsepower.text.trim()),
            _reviewRow('Frame', fields.frame.text.trim()),
            _reviewRow('Rod. acople', fields.driveBearing.text.trim()),
            _reviewRow('Rod. libre', fields.oppositeBearing.text.trim()),
            _reviewRow('Ciclo / Hz', fields.cycle.text.trim()),
            _reviewRow('Arranque', fields.start.text.trim()),
            _reviewRow('Fases', fields.phases.text.trim()),
            _reviewRow('Tension', fields.tension.text.trim()),
            _reviewRow('Lubricacion', fields.lubrication.text.trim()),
          ] else if (component == ReplacementComponent.motor) ...[
            const Divider(height: 20),
            Text(
              'Las especificaciones tecnicas actuales se conservaran.',
              style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _motorTechnicalFields(
    _ReplacementFields fields,
    String slug,
  ) {
    final specs = [
      _MotorFieldSpec('voltage', 'Voltaje nominal', fields.voltage),
      _MotorFieldSpec('current', 'Corriente / FLA', fields.current),
      _MotorFieldSpec('rpm', 'RPM', fields.rpm),
      _MotorFieldSpec(
          'service-factor', 'Factor de servicio (SF)', fields.serviceFactor),
      _MotorFieldSpec('horsepower', 'Potencia (HP)', fields.horsepower),
      _MotorFieldSpec('frame', 'Frame', fields.frame),
      _MotorFieldSpec(
          'drive-bearing', 'Rodamiento lado acople', fields.driveBearing),
      _MotorFieldSpec(
          'opposite-bearing', 'Rodamiento lado libre', fields.oppositeBearing),
      _MotorFieldSpec('cycle', 'Ciclo / Hz', fields.cycle),
      _MotorFieldSpec('start', 'Tipo de arranque', fields.start),
      _MotorFieldSpec('phases', 'Fases (PH)', fields.phases),
      _MotorFieldSpec('tension', 'Tension', fields.tension),
      _MotorFieldSpec('lubrication', 'Lubricacion', fields.lubrication),
    ];

    return [
      for (final spec in specs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            key: Key('${spec.key}-$slug'),
            controller: spec.controller,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(labelText: spec.label),
            validator: null,
          ),
        ),
    ];
  }

  Widget _equipmentHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.headerTop,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.equipo.equipo,
              style: AppText.titulo.copyWith(color: Colors.white)),
          const SizedBox(height: 5),
          Text(
            '${widget.equipo.sistema}  |  LOC ${widget.equipo.localizacion}',
            style:
                AppText.subtitulo.copyWith(color: const Color(0xFFB8C7DE)),
          ),
          if ((widget.equipo.qrCode ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'QR ${widget.equipo.qrCode}',
              style:
                  AppText.subtitulo.copyWith(color: const Color(0xFFB8C7DE)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppText.etiqueta
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppText.cuerpoFuerte
                    .copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  static String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  Future<ReplacementSaveResult> _saveLocally(
    ReplacementRequest request,
  ) async {
    try {
      await DbHelper.instance.insertReplacement(request);
      return ReplacementSaveResult.success(
        created: request.components.length,
        updated: 0,
        unchanged: 0,
      );
    } catch (error) {
      return ReplacementSaveResult.failure(error.toString());
    }
  }

  static String _componentLabel(ReplacementComponent component) {
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

  static IconData _componentIcon(ReplacementComponent component) {
    switch (component) {
      case ReplacementComponent.motor:
        return Icons.electric_bolt_rounded;
      case ReplacementComponent.pump:
        return Icons.water_rounded;
      case ReplacementComponent.gearbox:
        return Icons.settings_rounded;
      case ReplacementComponent.fan:
        return Icons.air_rounded;
    }
  }
}

/// Lista de piezas registradas, con buscador.
///
/// Las disponibles van primero; las que siguen montadas en otro equipo se
/// muestran igual pero marcadas, porque puede tratarse de un traslado que aun
/// no se registro alla.
class _CatalogPicker extends StatefulWidget {
  const _CatalogPicker({required this.titulo, required this.items});
  final String titulo;

  /// Ya vienen filtradas por familia: lo que se lista es lo compatible.
  final List<ComponentCatalogItem> items;

  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toUpperCase();
    final items = needle.isEmpty
        ? widget.items
        : widget.items
            .where((item) => item.busqueda.contains(needle))
            .toList(growable: false);
    final disponibles = widget.items.where((i) => !i.instalado).length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 14),
          Text('${widget.titulo}: piezas registradas',
              style: AppText.titulo.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            '$disponibles disponibles de ${widget.items.length}',
            style: AppText.subtitulo.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('catalog-search'),
            controller: _searchController,
            textCapitalization: TextCapitalization.characters,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Buscar por marca, modelo o serial',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text('Ninguna pieza coincide con la búsqueda',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final donde = (item.equipo ?? '').trim().isEmpty
                          ? 'loc. ${item.localizacion ?? '?'}'
                          : item.equipo!;
                      return ListTile(
                        key: Key('catalog-item-${item.serial}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.instalado
                              ? Icons.link_rounded
                              : Icons.check_circle_outline_rounded,
                          color: item.instalado
                              ? AppColors.textSecondary
                              : AppColors.teal,
                        ),
                        title: Text(item.titulo,
                            style: AppText.seccion
                                .copyWith(color: AppColors.textPrimary)),
                        subtitle: Text(
                          item.instalado
                              ? 'Serial ${item.serial} · instalada en $donde'
                              : 'Serial ${item.serial} · disponible',
                          style: AppText.apoyo.copyWith(
                              color: item.instalado
                                  ? AppColors.warning
                                  : AppColors.textSecondary),
                        ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class _ReplacementFields {
  final brand = TextEditingController();
  final model = TextEditingController();
  final serial = TextEditingController();
  final voltage = TextEditingController();
  final current = TextEditingController();
  final rpm = TextEditingController();
  final serviceFactor = TextEditingController();
  final horsepower = TextEditingController();
  final frame = TextEditingController();
  final driveBearing = TextEditingController();
  final oppositeBearing = TextEditingController();
  final cycle = TextEditingController();
  final start = TextEditingController();
  final phases = TextEditingController();
  final tension = TextEditingController();
  final lubrication = TextEditingController();

  /// Que se dano en la pieza que sale. Opcional: no bloquea el reemplazo.
  String? motivo;

  /// Con que estatus queda la pieza retirada y a donde va. Lo elige el
  /// tecnico en cada reemplazo.
  String? estadoSaliente;
  String? sitioSaliente;

  /// Hay algo escrito en los tres campos obligatorios.
  bool get completo =>
      brand.text.trim().isNotEmpty &&
      model.text.trim().isNotEmpty &&
      serial.text.trim().isNotEmpty;

  ReplacementData toData({required bool updateTechnicalSpecs}) =>
      ReplacementData(
        brand: brand.text,
        model: model.text,
        serial: serial.text,
        motivo: motivo,
        estadoSaliente: estadoSaliente,
        sitioSaliente: sitioSaliente,
        updateTechnicalSpecs: updateTechnicalSpecs,
        voltage: voltage.text,
        current: current.text,
        rpm: rpm.text,
        serviceFactor: serviceFactor.text,
        horsepower: horsepower.text,
        frame: frame.text,
        driveBearing: driveBearing.text,
        oppositeBearing: oppositeBearing.text,
        cycle: cycle.text,
        start: start.text,
        phases: phases.text,
        tension: tension.text,
        lubrication: lubrication.text,
      );

  void dispose() {
    for (final controller in [
      brand,
      model,
      serial,
      voltage,
      current,
      rpm,
      serviceFactor,
      horsepower,
      frame,
      driveBearing,
      oppositeBearing,
      cycle,
      start,
      phases,
      tension,
      lubrication,
    ]) {
      controller.dispose();
    }
  }
}

class _MotorFieldSpec {
  const _MotorFieldSpec(
    this.key,
    this.label,
    this.controller,
  );

  final String key;
  final String label;
  final TextEditingController controller;
}
