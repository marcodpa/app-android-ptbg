import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/medicion_remota.dart';
import '../models/models.dart';
import '../models/temperature_measurement.dart';
import '../models/temperature_plan.dart';
import '../services/api_service.dart';
import '../services/mediciones_service.dart';
import '../services/print_service.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

String _alignmentHistorySignature(AlignmentMeasurement measurement) {
  String text(String? value) =>
      (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final values = alignmentValueColumns
      .map(
        (column) => measurement.valores[column]?.toStringAsFixed(2) ?? 'NULL',
      )
      .join('|');
  return [
    measurement.localizacion,
    measurement.fecha,
    measurement.hora,
    text(measurement.sistema),
    values,
    text(measurement.observaciones),
    text(measurement.responsable),
    text(measurement.cargo),
    text(measurement.marca),
    text(measurement.modelo),
    text(measurement.serial),
    measurement.odt ?? 'NULL',
  ].join('|');
}

DateTime _alignmentHistoryDateTime(AlignmentMeasurement measurement) {
  final iso = DateTime.tryParse('${measurement.fecha}T${measurement.hora}');
  if (iso != null) return iso;
  final match = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
  ).firstMatch(measurement.fecha.trim());
  if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
  var year = int.tryParse(match.group(3) ?? '') ?? 1970;
  if (year < 100) year += 2000;
  final time = measurement.hora.split(':');
  return DateTime(
    year,
    int.tryParse(match.group(2) ?? '') ?? 1,
    int.tryParse(match.group(1) ?? '') ?? 1,
    time.isNotEmpty ? int.tryParse(time[0]) ?? 0 : 0,
    time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0,
    time.length > 2 ? int.tryParse(time[2].split('.').first) ?? 0 : 0,
  );
}

List<AlignmentMeasurement> mergeAlignmentHistory({
  required List<AlignmentMeasurement> local,
  required List<AlignmentMeasurement> remote,
}) {
  final merged = <String, AlignmentMeasurement>{};
  for (final measurement in remote) {
    merged[_alignmentHistorySignature(measurement)] = measurement;
  }
  for (final measurement in local) {
    merged[_alignmentHistorySignature(measurement)] = measurement;
  }
  return merged.values.toList()
    ..sort(
      (a, b) =>
          _alignmentHistoryDateTime(b).compareTo(_alignmentHistoryDateTime(a)),
    );
}

class MedicionesScreen extends StatefulWidget {
  const MedicionesScreen({super.key});

  @override
  State<MedicionesScreen> createState() => _MedicionesScreenState();
}

class _MedicionesScreenState extends State<MedicionesScreen> {
  List<MedicionLocal> _locales = [];
  List<MedicionRemota> _remotas = [];
  List<TemperatureMeasurement> _temperaturasLocales = [];
  List<TemperatureReading> _temperaturasRemotas = [];
  List<AlignmentMeasurement> _alineaciones = [];
  Map<int, Set<String>> _temperatureColumnsByLocation = {};
  bool _loadingLocal = true;
  bool _loadingRemotas = true;
  bool _refreshing = false;
  bool _online = false;
  String _tab = 'bd';
  String _measurementType = 'vibration';
  String _busqueda = '';
  String? _errorRemoto;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _online = await ApiService.instance.checkConexion();
    } catch (_) {
      _online = false;
    }

    await Future.wait([
      _cargarLocales(),
      _cargarRemotasCache(),
      _loadTemperatures(),
      _loadAlignments(),
    ]);

    if (_online) {
      await _actualizarDesdeServidor(mostrarMensaje: false);
    }
  }

  Future<bool> _loadTemperatures() async {
    if (!kIsWeb) {
      try {
        final local = await DbHelper.instance.getLocalTemperatures();
        final cached = await DbHelper.instance.getRemoteTemperatureHistory();
        final equipos = await DbHelper.instance.getAllEquipos();
        final columnsByLocation = <int, Set<String>>{
          for (final equipo in equipos)
            equipo.localizacion: TemperaturePlanResolver.fromPuntos(
              equipo.ptEq,
            ).map((step) => step.dbColumn).toSet(),
        };
        if (mounted) {
          setState(() {
            _temperaturasLocales = local;
            _temperaturasRemotas = cached;
            _temperatureColumnsByLocation = columnsByLocation;
          });
        }
      } catch (_) {}
    }
    if (_online) {
      try {
        final remote = await ApiService.instance.fetchTemperatureHistory(
          limit: 500,
        );
        if (!kIsWeb) {
          await DbHelper.instance.replaceRemoteTemperatureHistory(remote);
        }
        if (mounted) setState(() => _temperaturasRemotas = remote);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<void> _refreshTemperatures() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      _online = await ApiService.instance.checkConexion();
      final downloaded = await _loadTemperatures();
      if (mounted) {
        _snack(
          downloaded
              ? 'Temperaturas actualizadas desde MariaDB'
              : 'Mostrando temperaturas guardadas en la tablet',
          downloaded ? AppColors.success : AppColors.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadAlignments() async {
    if (kIsWeb) return;
    try {
      final local = await DbHelper.instance.getLocalAlignments();
      final remote = await DbHelper.instance.getRemoteAlignmentHistory();
      final ordered = mergeAlignmentHistory(local: local, remote: remote);
      if (mounted) setState(() => _alineaciones = ordered);
    } catch (_) {}
  }

  Future<void> _refreshAlignments() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _loadAlignments();
      if (mounted) {
        _snack(
          'Alineaciones actualizadas desde la caché USB de la tablet',
          AppColors.success,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _cargarLocales() async {
    if (kIsWeb) {
      if (mounted) setState(() => _loadingLocal = false);
      return;
    }

    try {
      final db = await DbHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT * FROM MEDICIONES_LOCAL '
        'ORDER BY fecha DESC, hora DESC, created_at DESC',
      );
      if (mounted) {
        setState(() {
          _locales = rows
              .map((row) => MedicionLocal.fromMap(
                    Map<String, dynamic>.from(row),
                  ))
              .toList();
          _loadingLocal = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLocal = false);
    }
  }

  Future<void> _cargarRemotasCache() async {
    if (kIsWeb) {
      if (mounted) setState(() => _loadingRemotas = false);
      return;
    }

    try {
      final data = await DbHelper.instance.getMedicionesRemotas();
      if (mounted) {
        setState(() {
          _remotas = data;
          _loadingRemotas = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRemotas = false;
          _errorRemoto = e.toString();
        });
      }
    }
  }

  Future<int> _recargarRemotasCache({
    String? motivo,
    bool mostrarMensaje = true,
  }) async {
    if (kIsWeb) return 0;

    final cache = await DbHelper.instance.getMedicionesRemotas();
    if (!mounted) return cache.length;

    setState(() {
      _remotas = cache;
      _loadingRemotas = false;
      _errorRemoto = motivo;
    });

    if (mostrarMensaje) {
      _snack(
        cache.isEmpty
            ? 'No hay mediciones guardadas en la tablet.'
            : 'Mostrando ${cache.length} mediciones guardadas por USB.',
        cache.isEmpty ? AppColors.warning : AppColors.success,
      );
    }

    return cache.length;
  }

  Future<void> _actualizarDesdeServidor({bool mostrarMensaje = true}) async {
    if (_refreshing) return;

    setState(() {
      _refreshing = true;
      _errorRemoto = null;
    });

    try {
      _online = await ApiService.instance.checkConexion();
      if (!_online) {
        await _recargarRemotasCache(
          motivo: 'Servidor API sin conexion. Datos cargados desde la tablet.',
          mostrarMensaje: mostrarMensaje,
        );
        return;
      }

      final data = await MedicionesService.instance.descargarTodas();

      if (!kIsWeb) {
        await DbHelper.instance.upsertMedicionesRemotas(
          data,
          reemplazarTodo: true,
        );
        final cache = await DbHelper.instance.getMedicionesRemotas();
        if (mounted) setState(() => _remotas = cache);
      } else {
        if (mounted) setState(() => _remotas = data);
      }

      if (mostrarMensaje && mounted) {
        _snack(
          '✓ ${data.length} mediciones descargadas desde MariaDB',
          AppColors.success,
        );
      }
    } catch (e) {
      if (mounted) {
        await _recargarRemotasCache(
          motivo: 'Servidor API no disponible. Datos cargados desde la tablet.',
          mostrarMensaje: mostrarMensaje,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _loadingRemotas = false;
        });
      }
    }
  }

  void _snack(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<MedicionRemota> get _remotasFiltradas {
    final query = _busqueda.trim().toLowerCase();
    if (query.isEmpty) return _remotas;

    return _remotas.where((m) {
      return m.localizacion.toString().contains(query) ||
          m.equipo.toLowerCase().contains(query) ||
          m.tagname.toLowerCase().contains(query) ||
          m.fecha.toLowerCase().contains(query) ||
          m.hora.toLowerCase().contains(query);
    }).toList();
  }

  Set<String> get _clavesUltimas {
    final result = <String>{};
    final localizaciones = <int>{};

    for (final medicion in _remotas) {
      if (localizaciones.add(medicion.localizacion)) {
        result.add(medicion.remoteKey);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppHeader(
        title: 'Mediciones',
        subtitle: 'Histórico completo y capturas de la tablet',
        actions: [
          IconButton(
            tooltip: 'Descargar todas las mediciones',
            onPressed: _refreshing
                ? null
                : () {
                    if (_measurementType == 'temperature') {
                      _refreshTemperatures();
                    } else if (_measurementType == 'alignment') {
                      _refreshAlignments();
                    } else {
                      _actualizarDesdeServidor();
                    }
                  },
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TabBtn(
                        label: 'Vibración',
                        active: _measurementType == 'vibration',
                        onTap: () => setState(
                          () => _measurementType = 'vibration',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TabBtn(
                        label: 'Alineación',
                        active: _measurementType == 'alignment',
                        onTap: () => setState(
                          () => _measurementType = 'alignment',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TabBtn(
                        label: 'Temperatura',
                        active: _measurementType == 'temperature',
                        onTap: () => setState(
                          () => _measurementType = 'temperature',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _TabBtn(
                        label: 'MariaDB (${_remoteMeasurementCount()})',
                        active: _tab == 'bd',
                        onTap: () => setState(() => _tab = 'bd'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TabBtn(
                        label: 'Tablet (${_localMeasurementCount()})',
                        active: _tab == 'local',
                        onTap: () => setState(() => _tab = 'local'),
                      ),
                    ),
                  ],
                ),
                if (_tab == 'bd' && _measurementType == 'vibration') ...[
                  const SizedBox(height: 9),
                  TextField(
                    onChanged: (value) => setState(() => _busqueda = value),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Buscar equipo, tag, localización o fecha…',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_tab == 'bd' && _errorRemoto != null)
            Container(
              width: double.infinity,
              color: AppColors.warningBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                'Modo caché: $_errorRemoto',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                ),
              ),
            ),
          Expanded(
            child: _measurementType == 'temperature'
                ? _buildTemperatures()
                : _measurementType == 'alignment'
                    ? _buildAlignments()
                    : (_tab == 'local' ? _buildLocal() : _buildRemotas()),
          ),
        ],
      ),
    );
  }

  Widget _buildRemotas() {
    if (_loadingRemotas && _remotas.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Cargando histórico de mediciones…',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final lista = _remotasFiltradas;
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storage_rounded,
              size: 52,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            Text(
              _remotas.isEmpty
                  ? 'No hay mediciones descargadas'
                  : 'No hay resultados para la búsqueda',
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            if (_remotas.isEmpty) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed:
                    _refreshing ? null : () => _actualizarDesdeServidor(),
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Descargar desde MariaDB'),
              ),
            ],
          ],
        ),
      );
    }

    final clavesUltimas = _clavesUltimas;
    return RefreshIndicator(
      onRefresh: () => _actualizarDesdeServidor(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: lista.length,
        itemBuilder: (_, index) {
          final medicion = lista[index];
          return _RemotaCard(
            medicion: medicion,
            esUltima: clavesUltimas.contains(medicion.remoteKey),
          );
        },
      ),
    );
  }

  Widget _buildLocal() {
    if (_loadingLocal) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_locales.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 56,
              color: AppColors.textHint,
            ),
            SizedBox(height: 12),
            Text(
              'Sin mediciones capturadas en la tablet',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _locales.length,
      itemBuilder: (_, index) => _LocalCard(m: _locales[index]),
    );
  }

  Widget _buildTemperatures() {
    final measurements = _tab == 'local'
        ? _temperaturasLocales
        : _temperaturasRemotas
            .map(
              (reading) => TemperatureMeasurement(
                uuid:
                    'remote-${reading.localizacion}-${reading.fecha}-${reading.hora}',
                localizacion: reading.localizacion,
                sistema: reading.sistema ?? '',
                fecha: reading.fecha,
                hora: reading.hora,
                valores: reading.valores,
                observaciones: reading.observaciones,
                responsable: reading.responsable,
                cargo: reading.cargo,
                marca: reading.marca,
                modelo: reading.modelo,
                serial: reading.serial,
                odt: reading.odt,
                sincronizado: true,
              ),
            )
            .toList();
    if (measurements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.thermostat_outlined,
                size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Sin mediciones de temperatura',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshTemperatures,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: measurements.length,
        itemBuilder: (_, index) => TemperatureHistoryCard(
          measurement: measurements[index],
          applicableColumns:
              _temperatureColumnsByLocation[measurements[index].localizacion],
        ),
      ),
    );
  }

  int _remoteMeasurementCount() {
    if (_measurementType == 'temperature') return _temperaturasRemotas.length;
    if (_measurementType == 'alignment') {
      return _alineaciones.where((item) => item.sincronizado).length;
    }
    return _remotas.length;
  }

  int _localMeasurementCount() {
    if (_measurementType == 'temperature') return _temperaturasLocales.length;
    if (_measurementType == 'alignment') {
      return _alineaciones.where((item) => !item.sincronizado).length;
    }
    return _locales.length;
  }

  Widget _buildAlignments() {
    final measurements = _alineaciones
        .where(
          (measurement) => _tab == 'local'
              ? !measurement.sincronizado
              : measurement.sincronizado,
        )
        .toList();
    if (measurements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.straighten_rounded,
              size: 56,
              color: AppColors.textHint,
            ),
            SizedBox(height: 12),
            Text(
              'Sin mediciones de alineación',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAlignments,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: measurements.length,
        itemBuilder: (_, index) => AlignmentHistoryCard(
          measurement: measurements[index],
        ),
      ),
    );
  }
}

class AlignmentHistoryCard extends StatelessWidget {
  const AlignmentHistoryCard({
    super.key,
    required this.measurement,
  });

  final AlignmentMeasurement measurement;

  String _formatted(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final sections = AlignmentPlanResolver.fromPuntos(measurement.puntos);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten_rounded, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'LOC-${measurement.localizacion} · ${measurement.sistema}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _AlignmentSyncBadge(synchronized: measurement.sincronizado),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${measurement.fecha}  ${measurement.hora}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            for (final section in sections) ...[
              const SizedBox(height: 14),
              Text(
                section.title,
                style: const TextStyle(
                  color: AppColors.headerTop,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              for (final field in section.fields)
                if (measurement.valores[field.column] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(field.label)),
                        Text(
                          '${_formatted(measurement.valores[field.column]!)} ${field.unit}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
            if ((measurement.observaciones ?? '').trim().isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                measurement.observaciones!.trim(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if ((measurement.errorSync ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                measurement.errorSync!.trim(),
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlignmentSyncBadge extends StatelessWidget {
  const _AlignmentSyncBadge({required this.synchronized});

  final bool synchronized;

  @override
  Widget build(BuildContext context) {
    final color = synchronized ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        synchronized ? 'Sincronizada' : 'Pendiente',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class TemperatureHistoryCard extends StatelessWidget {
  final TemperatureMeasurement measurement;
  final Set<String>? applicableColumns;

  const TemperatureHistoryCard({
    super.key,
    required this.measurement,
    this.applicableColumns,
  });

  @override
  Widget build(BuildContext context) {
    final values = measurement.valores.entries
        .where(
          (entry) =>
              entry.value != null &&
              (applicableColumns == null ||
                  applicableColumns!.contains(entry.key)),
        )
        .toList()
      ..sort((a, b) {
        final aIndex = int.tryParse(a.key.substring(1)) ?? 0;
        final bIndex = int.tryParse(b.key.substring(1)) ?? 0;
        return aIndex.compareTo(bIndex);
      });
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.thermostat_rounded, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'LOC-${measurement.localizacion} · ${measurement.sistema}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (measurement.sincronizado
                            ? AppColors.success
                            : AppColors.warning)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    measurement.sincronizado ? 'Sincronizada' : 'Pendiente',
                    style: TextStyle(
                      color: measurement.sincronizado
                          ? AppColors.success
                          : AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${measurement.fecha}  ${measurement.hora}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values
                  .map(
                    (entry) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tealLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${entry.key}  ${entry.value!.toStringAsFixed(2)} °C',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if ((measurement.observaciones ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(measurement.observaciones!.trim()),
            ],
            if ((measurement.errorSync ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                measurement.errorSync!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemotaCard extends StatelessWidget {
  final MedicionRemota medicion;
  final bool esUltima;

  const _RemotaCard({
    required this.medicion,
    required this.esUltima,
  });

  Color get _rmsColor {
    final value = medicion.rms ?? 0;
    if (value > 7.1) return AppColors.error;
    if (value > 4.5) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _print(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imprimiendo... solicitud enviada a la laptop'),
          duration: Duration(seconds: 6),
        ),
      );
      final equipo = await DbHelper.instance
          .getEquipoByLocalizacion(medicion.localizacion);
      final info = await DbHelper.instance.getEquipoInfo(medicion.localizacion);
      final printEquipo = equipo ??
          Equipo(
            id: medicion.localizacion,
            codeSys: 0,
            equipo: medicion.equipo,
            localizacion: medicion.localizacion,
            qrCode: medicion.tagname,
            puntos: 0,
            ptEq: 1,
            sistema: medicion.equipo,
            scada: medicion.tagname,
          );

      await MedicionPrintService.printMeasurement(
        data: MedicionPrintData(
          localizacion: medicion.localizacion,
          fecha: medicion.fecha,
          hora: medicion.hora,
          valores: medicion.valores,
          rms: medicion.rms,
          observaciones: medicion.observaciones,
          equipoNombre: medicion.equipo,
          tag: medicion.tagname,
          sistema: printEquipo.sistema,
          subsistema: printEquipo.subsistema,
          responsable: medicion.responsable,
          cargo: medicion.cargo,
        ),
        equipo: printEquipo,
        info: info ?? printEquipo.info,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresion enviada. Espere a que salga en la laptop.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo imprimir: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final valores = medicion.valores.entries
        .where((entry) => entry.value != null)
        .map(
          (entry) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Text(
              '${entry.key}: ${entry.value!.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
              ),
            ),
          ),
        )
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esUltima ? AppColors.success : AppColors.border,
          width: esUltima ? 1.2 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    color: AppColors.accent,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOC-${medicion.localizacion} · ${medicion.equipo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${medicion.tagname == 'Sin tag' ? '' : 'TAG: ${medicion.tagname} · '}'
                        '${medicion.fecha}  ${medicion.hora}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (medicion.rms != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _rmsColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RMS ${medicion.rms!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _rmsColor,
                      ),
                    ),
                  ),
                _PrintIconButton(onPressed: () => _print(context)),
              ],
            ),
          ),
          if (valores.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: valores,
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  esUltima
                      ? Icons.history_toggle_off_rounded
                      : Icons.cloud_done_outlined,
                  color: esUltima ? AppColors.success : AppColors.accent,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  esUltima
                      ? 'Última registrada para este equipo'
                      : 'Histórico MariaDB · ID ${medicion.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: esUltima ? AppColors.success : AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (medicion.observaciones.isNotEmpty) ...[
                  const Spacer(),
                  const Icon(
                    Icons.note_outlined,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      medicion.observaciones,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalCard extends StatelessWidget {
  final MedicionLocal m;

  const _LocalCard({required this.m});

  Color get _rmsColor {
    final value = m.rms ?? 0;
    if (value > 7.1) return AppColors.error;
    if (value > 4.5) return AppColors.warning;
    return AppColors.success;
  }

  int get _lecturasCapturadas =>
      m.valores.values.where((value) => value != null).length;

  Future<void> _print(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imprimiendo... solicitud enviada a la laptop'),
          duration: Duration(seconds: 6),
        ),
      );
      final equipo =
          await DbHelper.instance.getEquipoByLocalizacion(m.localizacion);
      final info = await DbHelper.instance.getEquipoInfo(m.localizacion);
      final printEquipo = equipo ??
          Equipo(
            id: m.localizacion,
            codeSys: 0,
            equipo: m.sistema,
            localizacion: m.localizacion,
            qrCode: m.localizacion.toString(),
            puntos: 0,
            ptEq: 1,
            sistema: m.sistema,
          );

      await MedicionPrintService.printMeasurement(
        data: MedicionPrintData(
          localizacion: m.localizacion,
          fecha: m.fecha,
          hora: m.hora,
          valores: m.valores,
          rms: m.rms,
          observaciones: m.observaciones,
          equipoNombre: printEquipo.equipo,
          tag: printEquipo.qrDisplay,
          sistema: m.sistema,
          subsistema: printEquipo.subsistema,
          responsable: m.responsable,
          cargo: m.cargo,
        ),
        equipo: printEquipo,
        info: info ?? printEquipo.info,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresion enviada. Espere a que salga en la laptop.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo imprimir: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tablet_android_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FutureBuilder<Equipo?>(
                    future: DbHelper.instance
                        .getEquipoByLocalizacion(m.localizacion),
                    builder: (context, snapshot) {
                      final equipo = snapshot.data;
                      final nombre = equipo?.equipo.trim().isNotEmpty == true
                          ? equipo!.equipo.trim()
                          : m.sistema;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LOC-${m.localizacion} · $nombre',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${m.fecha}  ${m.hora}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (m.rms != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _rmsColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RMS ${m.rms!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _rmsColor,
                      ),
                    ),
                  ),
                _PrintIconButton(onPressed: () => _print(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.checklist_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Lecturas capturadas: $_lecturasCapturadas',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((m.observaciones ?? '').trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.notes_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      m.observaciones!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  m.sincronizado
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  size: 14,
                  color: m.sincronizado ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 5),
                Text(
                  m.sincronizado
                      ? 'Sincronizada con MariaDB'
                      : 'Pendiente de sincronización',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        m.sincronizado ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrintIconButton extends StatefulWidget {
  final Future<void> Function() onPressed;

  const _PrintIconButton({required this.onPressed});

  @override
  State<_PrintIconButton> createState() => _PrintIconButtonState();
}

class _PrintIconButtonState extends State<_PrintIconButton> {
  bool _printing = false;

  Future<void> _handlePressed() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _printing ? 'Imprimiendo...' : 'Imprimir formato',
      onPressed: _printing ? null : _handlePressed,
      icon: _printing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.print_rounded, size: 18),
      color: AppColors.primary,
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
