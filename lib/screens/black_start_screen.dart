import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/checklist_black_start.dart';
import '../services/equipment_report_service.dart';
import '../theme.dart';
import '../widgets/decode_imagen.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/formulario_industrial.dart';
import '../widgets/avisos.dart';

/// Generador de arranque en negro: su historial y su check list.
///
/// El black start es un equipo unico en la planta, asi que esta pantalla no
/// lista equipos: entra directo a lo que se le puede hacer. Las tres acciones
/// son las mismas que en el resto de la app —consultar, imprimir, trabajar—
/// para que no haya que aprender otra forma de moverse.
class BlackStartScreen extends StatefulWidget {
  const BlackStartScreen({super.key});

  @override
  State<BlackStartScreen> createState() => _BlackStartScreenState();
}

class _BlackStartScreenState extends State<BlackStartScreen> {
  List<ChecklistBlackStart> _historial = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final historial = await DbHelper.instance.getChecklistsBlackStart();
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _llenar() async {
    final hecho = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const _FormularioBlackStart()),
    );
    if (hecho == true) await _cargar();
  }

  Future<void> _imprimir(ChecklistBlackStart checklist) async {
    // La laptop lo lee de la planta: uno sin subir no existe todavia para
    // ella. Se corta aqui y no se deja al tecnico esperando la respuesta.
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
      final detalle = await EquipmentReportService.imprimirChecklistBlackStart(
        uuid: checklist.uuid,
      );
      if (!mounted) return;
      avisar(context, detalle, AppColors.success, duracion: const Duration(seconds: 6));
    } catch (error) {
      if (!mounted) return;
      avisar(context, mensajeDeError(error), AppColors.error, duracion: const Duration(seconds: 6));
    }
  }

  Future<void> _ver(ChecklistBlackStart c) async {
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Black start · ${c.fecha}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            Text('Parametros y variables operativas',
                style: AppText.etiqueta.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 6),
            for (var i = 0; i < ChecklistBlackStart.parametrosNombres.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(ChecklistBlackStart.parametrosNombres[i],
                        style: AppText.apoyo),
                  ),
                  Text(
                    c.parametros[i].isEmpty ? '—' : c.parametros[i],
                    style: AppText.dato.copyWith(color: AppColors.textPrimary),
                  ),
                ]),
              ),
            const Divider(height: 18),
            Text('Estados y verificaciones',
                style: AppText.etiqueta.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 6),
            for (var i = 0;
                i < ChecklistBlackStart.componentesNombres.length;
                i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(
                    c.componentes[i]
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 15,
                    color: c.componentes[i]
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(ChecklistBlackStart.componentesNombres[i],
                        style: AppText.apoyo),
                  ),
                ]),
              ),
            if (c.observaciones.isNotEmpty) ...[
              const Divider(height: 18),
              Text('Observaciones',
                  style: AppText.etiqueta.copyWith(color: AppColors.textHint)),
              const SizedBox(height: 4),
              Text(c.observaciones, style: AppText.apoyo),
            ],
          ]),
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

  @override
  Widget build(BuildContext context) {
    return IndustrialShell(
      activeRoute: '/equipos',
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: IndustrialAppBar(
          titulo: 'Black start',
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                children: [
                  _portada(),
                  const SizedBox(height: 14),
                  _AccionBlackStart(
                    icono: Icons.fact_check_rounded,
                    titulo: 'Llenar planilla',
                    detalle: 'Check list SF-OP-FOR-036',
                    principal: true,
                    onTap: _llenar,
                  ),
                  const SizedBox(height: 9),
                  _AccionBlackStart(
                    icono: Icons.print_rounded,
                    titulo: 'Imprimir planilla',
                    detalle: _historial.isEmpty
                        ? 'Todavia no hay ninguna que imprimir'
                        : 'Formato oficial lleno, listo para firmar',
                    onTap: _historial.isEmpty
                        ? null
                        : () => _elegir(imprimir: true),
                  ),
                  const SizedBox(height: 9),
                  _AccionBlackStart(
                    icono: Icons.analytics_outlined,
                    titulo: 'Planillas anteriores',
                    detalle: _historial.isEmpty
                        ? 'Todavia no se ha llenado ninguna'
                        : '${_historial.length} realizada'
                            '${_historial.length == 1 ? '' : 's'}',
                    onTap: _historial.isEmpty
                        ? null
                        : () => _elegir(imprimir: false),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _portada() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          AspectRatio(
            aspectRatio: 1200 / 675,
            child: Image.asset(
              'assets/images/visual_black_start.jpg',
              fit: BoxFit.cover,
              cacheWidth: anchoDecode(context),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: .92),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GENERADOR DE ARRANQUE EN NEGRO',
                    style: AppText.micro.copyWith(color: AppColors.teal)),
                const SizedBox(height: 2),
                Text('Black start',
                    style: AppText.titulo.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ]),
      );

  Future<void> _elegir({required bool imprimir}) async {
    final elegida = await showModalBottomSheet<ChecklistBlackStart>(
      context: context,
      backgroundColor: AppColors.surface,
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
                itemCount: _historial.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = _historial[i];
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
                                    ? 'Todo apto'
                                    : c.noAptos == 1
                                        ? '1 componente NO APTO'
                                        : '${c.noAptos} componentes NO APTO',
                                style: AppText.apoyo.copyWith(color: color),
                              ),
                              if (!c.sincronizado)
                                Text('Sin enviar',
                                    style: AppText.micro
                                        .copyWith(color: AppColors.textHint)),
                            ],
                          ),
                        ),
                        Icon(
                          imprimir
                              ? Icons.print_rounded
                              : Icons.chevron_right_rounded,
                          color: AppColors.teal,
                          size: 19,
                        ),
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
      await _imprimir(elegida);
    } else {
      await _ver(elegida);
    }
  }
}

class _AccionBlackStart extends StatelessWidget {
  const _AccionBlackStart({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.principal = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback? onTap;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final habilitada = onTap != null;
    final color = !habilitada
        ? AppColors.textHint
        : principal
            ? AppColors.teal
            : AppColors.textSecondary;
    return Material(
      color: principal && habilitada
          ? AppColors.teal.withValues(alpha: .10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: principal && habilitada
                  ? AppColors.teal.withValues(alpha: .45)
                  : AppColors.border,
            ),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: AppText.seccion.copyWith(
                        color: habilitada
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                      )),
                  Text(detalle,
                      style:
                          AppText.apoyo.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: habilitada ? AppColors.textSecondary : AppColors.textHint),
          ]),
        ),
      ),
    );
  }
}

// ── FORMULARIO ──────────────────────────────────────────────────────────────

/// El check list en si, en el mismo orden del formato impreso.
class _FormularioBlackStart extends StatefulWidget {
  const _FormularioBlackStart();

  @override
  State<_FormularioBlackStart> createState() => _FormularioBlackStartState();
}

class _FormularioBlackStartState extends State<_FormularioBlackStart> {
  late final List<TextEditingController> _parametros;
  final _observaciones = TextEditingController();

  /// Sin responder al empezar: obligar a tocar cada componente evita el
  /// "todo apto" automatico que dejaria el check list sin valor.
  final _componentes =
      List<bool?>.filled(ChecklistBlackStart.componentesNombres.length, null);

  final _faltantes = ValueNotifier<Map<int, int>>(const {});
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _parametros = List.generate(
      ChecklistBlackStart.parametrosNombres.length,
      (_) => TextEditingController()..addListener(_recontar),
    );
    _recontar();
  }

  @override
  void dispose() {
    for (final c in _parametros) {
      c.dispose();
    }
    _observaciones.dispose();
    _faltantes.dispose();
    super.dispose();
  }

  void _recontar() {
    final parametros =
        _parametros.where((c) => c.text.trim().isEmpty).length;
    final componentes = _componentes.where((c) => c == null).length;
    _faltantes.value = {0: parametros, 1: componentes};
  }

  int get _noAptos => _componentes.where((c) => c == false).length;

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ahora = DateTime.now().toIso8601String();
      final odt = await DbHelper.instance.crearOrdenSuelta('BLACK START');

      await DbHelper.instance.insertChecklistBlackStart(ChecklistBlackStart(
        uuid: const Uuid().v4(),
        fecha: ahora.substring(0, 10),
        hora: ahora.substring(11, 19),
        parametros: [for (final c in _parametros) c.text.trim()],
        componentes: [for (final c in _componentes) c ?? false],
        observaciones: _observaciones.text.trim(),
        usuario: (prefs.getString('responsable') ?? prefs.getString('username'))
            ?.trim(),
        cargo: (prefs.getString('cargo') ?? prefs.getString('rol'))?.trim(),
        odt: odt,
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
      avisar(
        context,
        _noAptos == 0
            ? 'Check list guardado. ODT $odt, todo apto.'
            : 'Check list guardado. ODT $odt, con $_noAptos componente'
                '${_noAptos == 1 ? '' : 's'} NO APTO.',
        _noAptos == 0 ? AppColors.success : AppColors.warning,
        duracion: const Duration(seconds: 5),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      avisar(context, 'No se pudo guardar: $error', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(
        titulo: 'Check list black start',
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
            children: [
              _banda('PARAMETROS Y VARIABLES OPERATIVAS', 0),
              const SizedBox(height: 10),
              for (var i = 0;
                  i < ChecklistBlackStart.parametrosNombres.length;
                  i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _parametros[i],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          '${i + 1}. ${ChecklistBlackStart.parametrosNombres[i]}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _banda('ESTADOS Y VERIFICACIONES DE COMPONENTES', 1),
              const SizedBox(height: 10),
              for (var i = 0;
                  i < ChecklistBlackStart.componentesNombres.length;
                  i++)
                _Componente(
                  numero: i + 1,
                  texto: ChecklistBlackStart.componentesNombres[i],
                  apto: _componentes[i],
                  onResponder: (valor) {
                    setState(() => _componentes[i] = valor);
                    _recontar();
                  },
                ),
              const SizedBox(height: 6),
              TextField(
                controller: _observaciones,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  hintText: 'Opcional, como en el formato',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        _pie(),
      ]),
    );
  }

  Widget _banda(String texto, int indice) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Expanded(
            child: Text(texto,
                style: AppText.etiqueta.copyWith(color: AppColors.textPrimary)),
          ),
          ValueListenableBuilder<Map<int, int>>(
            valueListenable: _faltantes,
            builder: (context, mapa, _) {
              final falta = mapa[indice] ?? 0;
              final color =
                  falta == 0 ? AppColors.success : AppColors.warning;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: .4)),
                ),
                child: Text(
                  falta == 0 ? 'LISTO' : 'FALTAN $falta',
                  style: AppText.micro.copyWith(color: color),
                ),
              );
            },
          ),
        ]),
      );

  Widget _pie() => PieFormulario(
        faltantes: _faltantes,
        textoBoton: 'GUARDAR CHECK LIST',
        guardando: _guardando,
        onGuardar: _guardar,
        // Igual que en el check list de compresores: si todo esta lleno pero
        // hay componentes NO APTO, el pie lo dice antes de guardar.
        extra: _noAptos == 0
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  const Icon(Icons.report_problem_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _noAptos == 1
                          ? '1 componente quedó NO APTO'
                          : '$_noAptos componentes quedaron NO APTO',
                      style: AppText.apoyo.copyWith(color: AppColors.warning),
                    ),
                  ),
                ]),
              ),
      );
}

/// Un componente con su APTO / NO APTO.
class _Componente extends StatelessWidget {
  const _Componente({
    required this.numero,
    required this.texto,
    required this.apto,
    required this.onResponder,
  });

  final int numero;
  final String texto;
  final bool? apto;
  final void Function(bool) onResponder;

  @override
  Widget build(BuildContext context) {
    final color = apto == null
        ? AppColors.border
        : apto!
            ? AppColors.success
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: apto == null ? AppColors.border : color,
          width: apto == null ? 1 : 1.3,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color.withValues(alpha: .45)),
            ),
            child: Text('$numero', style: AppText.micro.copyWith(color: color)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(texto,
                style: AppText.cuerpo.copyWith(color: AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OpcionBinaria(
              texto: 'APTO',
              elegido: apto == true,
              color: AppColors.success,
              onTap: () => onResponder(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OpcionBinaria(
              texto: 'NO APTO',
              elegido: apto == false,
              color: AppColors.warning,
              onTap: () => onResponder(false),
            ),
          ),
        ]),
      ]),
    );
  }
}

