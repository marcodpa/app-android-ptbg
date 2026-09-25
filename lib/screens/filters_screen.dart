import 'package:flutter/material.dart';
import '../db/filter_store.dart';
import '../models/filter_catalog.dart';
import '../models/sesion.dart';
import '../widgets/filter_visuals.dart';
import '../widgets/filter_flux.dart';

/// Una columna en vertical; ninguna tabla exige desplazamiento horizontal.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key, this.store});
  final FilterStore? store;
  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  late final store = widget.store ?? FilterStore();
  FilterCatalog? catalog;
  FilterRow? system, subsystem;
  String search = '';
  String? error;
  bool admin = false;
  final searchController = TextEditingController();
  final catalogScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    catalogScroll.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final data = await store.catalog();
      final allowed = await Sesion.esAdmin();
      if (!mounted) return;
      setState(() {
        catalog = data;
        admin = allowed;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => error = 'No se pudo leer el catálogo. Intente nuevamente.');
      }
    }
  }

  void back() {
    if (subsystem != null || system != null) {
      setState(() {
        if (subsystem != null) {
          subsystem = null;
        } else {
          system = null;
        }
        search = '';
        searchController.clear();
      });
      if (catalogScroll.hasClients) catalogScroll.jumpTo(0);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => page));
    await refresh();
  }

  Widget navigationCard(FilterRow row, FilterCatalog data) =>
      FilterFluxNavigationCard(
        title: system == null
            ? filterSystemTitle(row)
            : filterDisplayName(filterText(row['NAME_SUB_SYS'])),
        asset: system == null
            ? FilterFluxAssets.system(row)
            : FilterFluxAssets.subsystem(row),
        wide: system == null && filterSystemArt(row) != FilterArt.turbine,
        detail: system == null
            ? _countLabel(data.forSystem(filterInt(row['CODE_SYS'])).length,
                'subsistema habilitado', 'subsistemas habilitados')
            : _countLabel(
                data
                    .forSubsystem(filterInt(row['CODE_SYS']),
                        filterInt(row['CODE_SUB_SYS']))
                    .length,
                'filtro disponible',
                'filtros disponibles'),
        label: system == null ? 'Ver subsistemas' : 'Ver filtros',
        onTap: () => setState(() {
          if (system == null) {
            system = row;
          } else {
            subsystem = row;
          }
          search = '';
          searchController.clear();
          if (catalogScroll.hasClients) catalogScroll.jumpTo(0);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final data = catalog;
    final rows = data == null
        ? <FilterRow>[]
        : subsystem != null
            ? data.forSubsystem(filterInt(system!['CODE_SYS']),
                filterInt(subsystem!['CODE_SUB_SYS']))
            : system != null
                ? data.forSystem(filterInt(system!['CODE_SYS']))
                : data.enabledSystems;
    final field = subsystem != null
        ? 'ELEMENTO'
        : system != null
            ? 'NAME_SUB_SYS'
            : 'SISTEMA';
    final visible = rows
        .where((r) =>
            '${r[field]} ${field == 'SISTEMA' ? filterSystemTitle(r) : ''} ${r['TAGNAME'] ?? ''} ${r['LOCALIZACION'] ?? ''}'
                .toLowerCase()
                .contains(search.toLowerCase()))
        .toList();
    return PopScope(
        canPop: system == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) back();
        },
        child: FilterPage(
          title: subsystem != null
              ? 'Filtros del subsistema'
              : system != null
                  ? filterSystemTitle(system!)
                  : 'Cambio de filtros',
          subtitle: subsystem != null
              ? filterDisplayName(filterText(subsystem!['NAME_SUB_SYS']))
              : system != null
                  ? 'Selecciona un subsistema'
                  : 'Selecciona un sistema',
          leading: IconButton(
              tooltip: 'Volver',
              onPressed: back,
              icon: const Icon(Icons.arrow_back)),
          body: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                  controller: catalogScroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (system != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                TextButton(
                                    onPressed: () => setState(() {
                                          system = null;
                                          subsystem = null;
                                          search = '';
                                          searchController.clear();
                                          if (catalogScroll.hasClients) {
                                            catalogScroll.jumpTo(0);
                                          }
                                        }),
                                    child: const Text('Filtros')),
                                const Icon(Icons.chevron_right, size: 18),
                                Text(filterSystemTitle(system!)),
                                if (subsystem != null) ...[
                                  const Icon(Icons.chevron_right, size: 18),
                                  Text(filterDisplayName(
                                      filterText(subsystem!['NAME_SUB_SYS'])))
                                ],
                              ])),
                    TextField(
                        controller: searchController,
                        onChanged: (v) => setState(() => search = v),
                        decoration: InputDecoration(
                            labelText: subsystem != null
                                ? 'Buscar filtro'
                                : system != null
                                    ? 'Buscar subsistema'
                                    : 'Buscar sistema',
                            prefixIcon: const Icon(Icons.search))),
                    const SizedBox(height: 16),
                    if (error != null)
                      _Notice(error!, action: refresh, label: 'Reintentar')
                    else if (data == null)
                      const Center(child: CircularProgressIndicator())
                    else if (data.systems.isEmpty)
                      _Notice(
                          'Descargue el catálogo de filtros con el uploader seguro por USB. '
                          'No se cargarán sistemas ni códigos inventados.',
                          action: () => Navigator.pushNamed(context, '/sync'),
                          label: 'Ir a sincronización')
                    else if (visible.isEmpty)
                      const _Notice(
                          'No hay elementos habilitados que coincidan con la búsqueda.'),
                    if (subsystem != null)
                      for (final row in visible)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FilterElementCard(
                                row: row,
                                onHistory: () => open(FilterHistoryScreen(
                                    store: store, element: row)),
                                onChange: () => open(FilterChangeScreen(
                                    store: store, element: row)))),
                    if (subsystem == null && data != null) ...[
                      FilterFluxGrid(children: [
                        for (final row in visible.where((r) =>
                            system != null ||
                            filterSystemArt(r) == FilterArt.turbine))
                          navigationCard(row, data),
                      ]),
                      if (system == null)
                        for (final row in visible.where(
                            (r) => filterSystemArt(r) != FilterArt.turbine))
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: navigationCard(row, data)),
                    ],
                    if (subsystem != null) ...[
                      const Text(
                          'Imágenes ilustrativas de referencia. Verifica el modelo instalado.',
                          style: TextStyle(fontSize: 12, height: 1.5)),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 8),
                    FilterFluxAction(
                        onTap: () => open(FilterHistoryScreen(store: store)),
                        icon: Icons.description_outlined,
                        title: 'Historial de filtros'),
                    if (admin) ...[
                      const SizedBox(height: 12),
                      FilterFluxAction(
                          onTap: () => open(FilterAdminScreen(store: store)),
                          icon: Icons.settings_outlined,
                          title: 'Administrar filtros'),
                    ],
                    const SizedBox(height: 16),
                  ])),
        ));
  }
}

String _countLabel(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

class FilterElementCard extends StatelessWidget {
  const FilterElementCard(
      {super.key,
      required this.row,
      required this.onHistory,
      required this.onChange});
  final FilterRow row;
  final VoidCallback onHistory, onChange;
  @override
  Widget build(BuildContext context) => FilterFluxProduct(
      asset: FilterFluxAssets.element(row),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(filterDisplayName(filterText(row['ELEMENTO'])),
            style: const TextStyle(
                fontSize: 19, height: 1.3, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
            'Localización ${row['LOCALIZACION']} · TAG: ${row['TAGNAME']}\nCantidad completa: ${row['CANTIDAD']}',
            style: const TextStyle(height: 1.6)),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: onChange,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Registrar cambio')),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.history),
            label: const Text('Historial')),
      ]));
}

class FilterChangeScreen extends StatefulWidget {
  const FilterChangeScreen(
      {super.key, required this.store, required this.element});
  final FilterStore store;
  final FilterRow element;
  @override
  State<FilterChangeScreen> createState() => _FilterChangeScreenState();
}

class _FilterChangeScreenState extends State<FilterChangeScreen> {
  final form = GlobalKey<FormState>();
  late final fields = <String, TextEditingController>{
    for (final key in ['modelo', 'marca', 'especificaciones'])
      key: TextEditingController(
          text: filterText(widget.element[key.toUpperCase()])),
    'observaciones': TextEditingController()
  };
  bool saving = false;
  bool confirming = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || confirming || !form.currentState!.validate()) return;
    setState(() => confirming = true);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Confirmar cambio completo'),
                content: Text(
                    'Se registrará el reemplazo de ${widget.element['CANTIDAD']} elementos de ${widget.element['ELEMENTO']}. '
                    'La fecha, hora y tablet de origen se guardan al confirmar.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Guardar cambio'))
                ]));
    if (!mounted) return;
    setState(() => confirming = false);
    if (confirmed != true) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final odt = await widget.store.saveChange(
          widget.element, fields.map((k, v) => MapEntry(k, v.text.trim())));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Cambio guardado. ODT $odt · Pendiente de envío por USB.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FilterPage(
      title: 'Registrar cambio',
      subtitle: 'Reemplazo completo del elemento filtrante',
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FilterVisualCard(
                title:
                    filterDisplayName(filterText(widget.element['ELEMENTO'])),
                kind: FilterArt.cartridge,
                imageAsset: FilterFluxAssets.element(widget.element),
                detail:
                    'Localización ${widget.element['LOCALIZACION']} · TAG: ${widget.element['TAGNAME']}'),
            const SizedBox(height: 12),
            FilterMessage(
                '${widget.element['CANTIDAD']} elementos · Cambio completo',
                icon: Icons.lock_outline),
            const SizedBox(height: 16),
            const FilterMessage(
                'ODT de numeración general. Fecha y hora automáticas al confirmar.\nResponsable y cargo: usuario de la sesión actual.',
                icon: Icons.assignment_outlined),
            const SizedBox(height: 16),
            const FilterSectionTitle('Datos del recambio'),
            for (final item in {
              'modelo': 'Modelo / N.º de parte instalado',
              'marca': 'Marca instalada',
              'especificaciones': 'Especificaciones (micrones)',
              'observaciones': 'Observaciones (opcional)'
            }.entries)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                      controller: fields[item.key],
                      enabled: !saving,
                      maxLength: item.key == 'observaciones'
                          ? 4000
                          : item.key == 'especificaciones'
                              ? 50
                              : 150,
                      minLines: item.key == 'observaciones' ? 3 : 1,
                      maxLines: item.key == 'observaciones' ? 6 : 1,
                      decoration: InputDecoration(
                          labelText: item.value, alignLabelWithHint: true),
                      validator: (v) => item.key != 'observaciones' &&
                              (v ?? '').trim().isEmpty
                          ? 'Complete este campo.'
                          : null)),
            if (error != null) _Notice(error!),
            FilledButton.icon(
                onPressed: saving || confirming ? null : save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Guardando…' : 'Revisar y guardar')),
          ])));
}

class FilterHistoryScreen extends StatefulWidget {
  const FilterHistoryScreen({super.key, required this.store, this.element});
  final FilterStore store;
  final FilterRow? element;
  @override
  State<FilterHistoryScreen> createState() => _FilterHistoryScreenState();
}

class _FilterHistoryScreenState extends State<FilterHistoryScreen> {
  late Future<List<FilterRow>> rows = load();
  String search = '';
  Future<List<FilterRow>> load() => widget.store.history(
      location: widget.element == null
          ? null
          : filterInt(widget.element!['LOCALIZACION']));
  @override
  Widget build(BuildContext context) => FilterPage(
      title: 'Historial de filtros',
      subtitle: 'Trazabilidad de los cambios registrados',
      body: FutureBuilder<List<FilterRow>>(
          future: rows,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Notice('No se pudo cargar el historial.',
                  action: () => setState(() => rows = load()),
                  label: 'Reintentar');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final matches = snapshot.data!
                .where((r) => r.values.join(' ').toLowerCase().contains(search))
                .toList();
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.element != null) ...[
                FilterVisualCard(
                    title: filterDisplayName(
                        filterText(widget.element!['ELEMENTO'])),
                    kind: FilterArt.cartridge,
                    imageAsset: FilterFluxAssets.element(widget.element!),
                    detail:
                        'Localización ${widget.element!['LOCALIZACION']} · TAG: ${widget.element!['TAGNAME']}'),
                const SizedBox(height: 16),
              ],
              TextField(
                  onChanged: (v) => setState(() => search = v.toLowerCase()),
                  decoration: const InputDecoration(
                      labelText: 'Buscar fecha, ODT, filtro o tablet',
                      prefixIcon: Icon(Icons.search))),
              const SizedBox(height: 16),
              const FilterSectionTitle('Cambios registrados'),
              if (matches.isEmpty)
                const FilterFluxEmpty(
                    title: 'Sin cambios registrados para esta consulta.',
                    detail:
                        'Los cambios guardados aparecerán aquí con su ODT y tablet de origen.'),
              for (final r in matches)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilterFluxProduct(
                        asset: FilterFluxAssets.element(r),
                        compact: true,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(filterDisplayName(filterText(r['elemento'])),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(
                                  '${r['fecha']} ${r['hora']}\nODT ${r['odt']} · ${filterInt(r['sincronizado']) == 1 ? 'Sincronizado' : 'Pendiente de envío'}'),
                              Text(
                                  '${r['sistema']} · Localización ${r['localizacion']}\n${r['responsable']} · ${r['cargo']}\nTablet: ${r['tablet_origen']}'),
                              Text(
                                  'Modelo: ${r['modelo']}\nMarca: ${r['marca']}\nEspecificaciones: ${r['especificaciones']}'),
                              if (r['cantidad'] != null)
                                Text(
                                    'Cantidad capturada en esta tablet: ${r['cantidad']}'),
                              if (filterText(r['observaciones']).isNotEmpty)
                                Text(filterText(r['observaciones'])),
                              if (filterText(r['error_sync']).isNotEmpty)
                                Text('Error de envío: ${r['error_sync']}'),
                            ]))),
              const SizedBox(height: 16),
              const Text('Cada cambio conserva sus datos de origen.'),
            ]);
          }));
}

class FilterAdminScreen extends StatefulWidget {
  const FilterAdminScreen({super.key, required this.store});
  final FilterStore store;
  @override
  State<FilterAdminScreen> createState() => _FilterAdminScreenState();
}

class _FilterAdminScreenState extends State<FilterAdminScreen> {
  late Future<bool> access = Sesion.esAdmin();
  late Future<FilterCatalog> catalog = widget.store.catalog();
  late Future<List<FilterRow>> requests = widget.store.catalogRequests();
  int? selectedSystem, selectedSubsystem;
  Future<void> open(bool add) async {
    try {
      final data = await catalog;
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => add
                  ? FilterAddScreen(store: widget.store, catalog: data)
                  : FilterAvailabilityScreen(
                      store: widget.store, catalog: data)));
      if (mounted) setState(() => requests = widget.store.catalogRequests());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No se pudo abrir el catálogo. Regrese y vuelva a intentarlo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FilterPage(
      title: 'Administrar filtros',
      subtitle: 'Catálogo de elementos filtrantes',
      body: FutureBuilder<bool>(
          future: access,
          builder: (context, auth) {
            if (auth.data != true) {
              return const Center(
                  child: Text('Acceso exclusivo del administrador.'));
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                      avatar: Icon(Icons.person_outline, size: 18),
                      label: Text('Administrador'))),
              const SizedBox(height: 16),
              FilterFluxGrid(children: [
                FilterFluxAction(
                    title: 'Agregar filtro',
                    icon: Icons.add,
                    onTap: () => open(true)),
                FilterFluxAction(
                    title: 'Sistemas y subsistemas',
                    icon: Icons.account_tree_outlined,
                    onTap: () => open(false)),
              ]),
              const SizedBox(height: 16),
              const _Notice(
                  'Las altas y habilitaciones se validan por USB. El catálogo y los mantenimientos se gestionan por separado.'),
              const SizedBox(height: 24),
              FutureBuilder<List<FilterRow>>(
                  future: requests,
                  builder: (context, s) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Solicitudes pendientes',
                                style: Theme.of(context).textTheme.titleMedium),
                            if (s.hasError)
                              const Text(
                                  'No se pudieron leer las solicitudes.'),
                            if (s.hasData && s.data!.isEmpty) ...[
                              const SizedBox(height: 12),
                              const FilterFluxEmpty(
                                  title: 'Sin solicitudes pendientes',
                                  detail:
                                      'Las solicitudes de catálogo se envían por USB.'),
                            ],
                            for (final r in s.data ?? <FilterRow>[])
                              Card(
                                  child: ListTile(
                                      title: Text(
                                          '${r['accion']} · ${r['created_at']}'),
                                      subtitle: Text(
                                          '${r['responsable']}\n${r['error_sync'] ?? 'Pendiente de envío USB'}'))),
                          ])),
              const SizedBox(height: 24),
              FutureBuilder<FilterCatalog>(
                  future: catalog,
                  builder: (context, s) {
                    if (s.hasError) {
                      return const Text('No se pudo leer el catálogo.');
                    }
                    return Column(children: [
                      DropdownButtonFormField<int>(
                          initialValue: selectedSystem,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Sistema'),
                          items: [
                            const DropdownMenuItem<int>(
                                child: Text('Todos los sistemas')),
                            for (final system
                                in s.data?.systems ?? <FilterRow>[])
                              DropdownMenuItem(
                                  value: filterInt(system['CODE_SYS']),
                                  child: Text(filterSystemTitle(system),
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (value) => setState(() {
                                selectedSystem = value;
                                selectedSubsystem = null;
                              })),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                          key: ValueKey(selectedSystem),
                          initialValue: selectedSubsystem,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Subsistema'),
                          items: [
                            const DropdownMenuItem<int>(
                                child: Text('Todos los subsistemas')),
                            for (final sub in s.data?.forSystem(
                                    selectedSystem ?? -1,
                                    enabledOnly: false) ??
                                <FilterRow>[])
                              DropdownMenuItem(
                                  value: filterInt(sub['CODE_SUB_SYS']),
                                  child: Text(
                                      filterDisplayName(
                                          filterText(sub['NAME_SUB_SYS'])),
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: selectedSystem == null
                              ? null
                              : (value) =>
                                  setState(() => selectedSubsystem = value)),
                      const SizedBox(height: 24),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: FilterSectionTitle('Elementos del catálogo')),
                      for (final e in (s.data?.elements ?? <FilterRow>[]).where(
                          (e) =>
                              (selectedSystem == null ||
                                  filterInt(e['CODE_SYS']) == selectedSystem) &&
                              (selectedSubsystem == null ||
                                  filterInt(e['CODE_SUB_SYS']) ==
                                      selectedSubsystem)))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: FilterVisualCard(
                                title: filterDisplayName(
                                    filterText(e['ELEMENTO'])),
                                kind: FilterArt.cartridge,
                                imageAsset: FilterFluxAssets.element(e),
                                detail:
                                    'Sistema ${e['CODE_SYS']} · Subsistema ${e['CODE_SUB_SYS']}\nLocalización ${e['LOCALIZACION']} · Cantidad ${e['CANTIDAD']}\n${e['MARCA']} · ${e['MODELO']}'))
                    ]);
                  }),
            ]);
          }));
}

class FilterAddScreen extends StatefulWidget {
  const FilterAddScreen(
      {super.key, required this.store, required this.catalog});
  final FilterStore store;
  final FilterCatalog catalog;
  @override
  State<FilterAddScreen> createState() => _FilterAddScreenState();
}

class _FilterAddScreenState extends State<FilterAddScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final k in [
      'ELEMENTO',
      'TAGNAME',
      'LOCALIZACION',
      'CANTIDAD',
      'MODELO',
      'MARCA',
      'ESPECIFICACIONES'
    ])
      k: TextEditingController()
  };
  int? system, subsystem;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving ||
        !form.currentState!.validate() ||
        system == null ||
        subsystem == null) {
      return;
    }
    final data = <String, dynamic>{
      'CODE_SYS': system,
      'CODE_SUB_SYS': subsystem,
      for (final e in fields.entries) e.key: e.value.text.trim()
    };
    for (final k in ['CANTIDAD', 'LOCALIZACION']) {
      data[k] = int.tryParse('${data[k]}');
    }
    final validation = FilterCatalog.validateElement(data);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    if (widget.catalog.elements
        .any((e) => e['LOCALIZACION'] == data['LOCALIZACION'])) {
      setState(() => error = 'La localización ya está asignada.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.requestCatalogChange('add', data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FilterPage(
      title: 'Agregar filtro',
      subtitle: 'Catálogo de elementos filtrantes',
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            FilterVisualCard(
                title: 'Nuevo elemento filtrante',
                kind: FilterArt.cartridge,
                imageAsset: FilterFluxAssets.element(
                    {'ELEMENTO': fields['ELEMENTO']!.text}),
                detail:
                    'Imagen ilustrativa por familia. Completa la ficha técnica.'),
            const SizedBox(height: 16),
            const FilterSectionTitle('Sistema y subsistema'),
            DropdownButtonFormField<int>(
                initialValue: system,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Sistema habilitado'),
                items: [
                  for (final s in widget.catalog.enabledSystems)
                    DropdownMenuItem(
                        value: filterInt(s['CODE_SYS']),
                        child: Text(filterSystemTitle(s),
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: saving
                    ? null
                    : (v) => setState(() {
                          system = v;
                          subsystem = null;
                        }),
                validator: (v) => v == null ? 'Seleccione un sistema.' : null),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
                key: ValueKey(system),
                initialValue: subsystem,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Subsistema habilitado'),
                items: [
                  for (final s in widget.catalog.forSystem(system ?? -1))
                    DropdownMenuItem(
                        value: filterInt(s['CODE_SUB_SYS']),
                        child: Text(
                            filterDisplayName(filterText(s['NAME_SUB_SYS'])),
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: saving ? null : (v) => setState(() => subsystem = v),
                validator: (v) =>
                    v == null ? 'Seleccione un subsistema.' : null),
            const SizedBox(height: 16),
            const FilterSectionTitle('Ficha del filtro'),
            for (final e in {
              'ELEMENTO': 'Elemento filtrante',
              'TAGNAME': 'TAG',
              'LOCALIZACION': 'Localización',
              'CANTIDAD': 'Cantidad total',
              'MODELO': 'Modelo / N.º de parte',
              'MARCA': 'Marca',
              'ESPECIFICACIONES': 'Especificaciones (micrones)'
            }.entries)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                      controller: fields[e.key],
                      onChanged:
                          e.key == 'ELEMENTO' ? (_) => setState(() {}) : null,
                      enabled: !saving,
                      decoration: InputDecoration(labelText: e.value),
                      keyboardType: ['LOCALIZACION', 'CANTIDAD'].contains(e.key)
                          ? TextInputType.number
                          : TextInputType.text,
                      maxLength: e.key == 'ESPECIFICACIONES' ? 50 : 150,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Complete este campo.'
                          : null)),
            const _Notice(
                'En cada cambio se reemplazará la cantidad completa. El alta será validada al sincronizar.'),
            if (error != null) _Notice(error!),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Guardando…' : 'Solicitar alta')),
          ])));
}

class FilterAvailabilityScreen extends StatefulWidget {
  const FilterAvailabilityScreen(
      {super.key, required this.store, required this.catalog});
  final FilterStore store;
  final FilterCatalog catalog;
  @override
  State<FilterAvailabilityScreen> createState() =>
      _FilterAvailabilityScreenState();
}

class _FilterAvailabilityScreenState extends State<FilterAvailabilityScreen> {
  String? error;
  final requested = <String>{};
  bool busy = false;
  Future<void> request(FilterRow row, bool system, bool value) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(
                    value ? 'Habilitar para filtros' : 'Ocultar del módulo'),
                content: Text(
                    '${row[system ? 'SISTEMA' : 'NAME_SUB_SYS']}\nNo se borrará el historial. La solicitud se validará por USB.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Solicitar cambio'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.requestCatalogChange(system ? 'system' : 'subsystem', {
        'CODE_SYS': row['CODE_SYS'],
        if (!system) 'CODE_SUB_SYS': row['CODE_SUB_SYS'],
        'previous': filterInt(row['PTBG_FLT']),
        'PTBG_FLT': value ? 1 : 0
      });
      if (mounted) {
        setState(() => requested.add('${system ? 's' : 'sub'}:${row['ID']}'));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget toggle(FilterRow r, bool system) {
    final pending = requested.contains('${system ? 's' : 'sub'}:${r['ID']}');
    return SwitchListTile(
        title: Text(system
            ? filterSystemTitle(r)
            : filterDisplayName(filterText(r['NAME_SUB_SYS']))),
        subtitle: Text(pending
            ? 'Solicitud pendiente de envío'
            : filterInt(r['PTBG_FLT']) == 1
                ? 'Habilitado'
                : 'No habilitado'),
        value: filterInt(r['PTBG_FLT']) == 1,
        onChanged: busy || pending ? null : (v) => request(r, system, v));
  }

  @override
  Widget build(BuildContext context) => FilterPage(
      title: 'Sistemas y subsistemas',
      subtitle: 'Disponibilidad para filtros',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _Notice(
            'Solo se muestran al operador los sistemas y subsistemas habilitados. Los pendientes y el historial se conservan.'),
        if (error != null) _Notice(error!),
        const SizedBox(height: 24),
        for (final s in widget.catalog.systems)
          Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                      key: PageStorageKey(
                          'filter-availability-${s['CODE_SYS']}'),
                      initiallyExpanded: s == widget.catalog.systems.first,
                      title: Text(filterSystemTitle(s),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(filterInt(s['PTBG_FLT']) == 1
                          ? 'Habilitado'
                          : 'No habilitado'),
                      children: [
                        SizedBox(
                            height: 120,
                            width: double.infinity,
                            child: FilterFluxImage(FilterFluxAssets.system(s))),
                        toggle(s, true),
                        const Divider(height: 1),
                        for (final sub in widget.catalog.forSystem(
                            filterInt(s['CODE_SYS']),
                            enabledOnly: false))
                          toggle(sub, false),
                      ]))),
      ]));
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.action, this.label});
  final String message;
  final VoidCallback? action;
  final String? label;
  @override
  Widget build(BuildContext context) => FilterMessage(message,
      action: action == null
          ? null
          : TextButton(onPressed: action, child: Text(label ?? 'Reintentar')));
}
