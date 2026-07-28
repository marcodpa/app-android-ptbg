import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/equipo_service.dart';
import '../services/mediciones_service.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'operation_selection_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load(actualizarServidor: true);
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

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppHeader(
        title: 'Ruta de trabajo',
        subtitle: '${_equipos.length} equipos · operaciones y última lectura',
        actions: [
          IconButton(
            tooltip: 'Actualizar últimas lecturas',
            onPressed:
                _refreshing ? null : () => _load(actualizarServidor: true),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
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
                              color:
                                  active ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Text(
                            sistema,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                'Se muestran los datos guardados en la tablet. $_error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                ),
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
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: lista.length,
                  itemBuilder: (_, index) {
                    final equipo = lista[index];
                    return _EquipoTile(
                      equipo: equipo,
                      ultima: _ultimas[equipo.localizacion],
                      pendingCount: _pendingCounts[equipo.localizacion] ?? 0,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                OperationSelectionScreen(equipo: equipo),
                          ),
                        );
                        if (!kIsWeb) {
                          final map =
                              await DbHelper.instance.getUltimasLecturasMap();
                          final pending = await DbHelper.instance
                              .getPendingWorkCountsByLocation();
                          if (mounted) {
                            setState(() {
                              _ultimas = map;
                              _pendingCounts = pending;
                            });
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EquipoTile extends StatelessWidget {
  final Equipo equipo;
  final UltimaLectura? ultima;
  final int pendingCount;
  final VoidCallback onTap;

  const _EquipoTile({
    required this.equipo,
    required this.ultima,
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasReading = ultima != null;
    final rmsText =
        ultima?.rms == null ? null : '${ultima!.rms!.toStringAsFixed(2)} mm/s';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.shadowSm,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: AppColors.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    equipo.equipo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${equipo.sistema} · LOC-${equipo.localizacion} · ${equipo.qrDisplay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (pendingCount > 0) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$pendingCount ${pendingCount == 1 ? 'trabajo pendiente' : 'trabajos pendientes'}',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Icon(
                        hasReading
                            ? Icons.history_rounded
                            : Icons.info_outline_rounded,
                        size: 14,
                        color:
                            hasReading ? AppColors.success : AppColors.textHint,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hasReading
                              ? 'Última: ${ultima!.fecha}  ${ultima!.hora}'
                              : 'Sin mediciones registradas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasReading
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (rmsText != null)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tealLight,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            'RMS $rmsText',
                            style: const TextStyle(
                              color: AppColors.tealDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.gradAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
