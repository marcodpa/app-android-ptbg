import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/checklist_compresor.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import '../widgets/formulario_industrial.dart';
import '../widgets/avisos.dart';
import '../widgets/selector_hora_rueda.dart';

/// Check list de mantenimiento a un compresor de aire (SF-OP-FOR-040).
///
/// Reproduce el formato de papel en el mismo orden en que esta impreso, para
/// que el tecnico que ya lo conoce no tenga que buscar donde quedo cada cosa:
/// cabecera, once inspecciones de SI/NO, control de mantenimiento y firma.
class ChecklistCompresorScreen extends StatefulWidget {
  const ChecklistCompresorScreen({
    super.key,
    required this.compresor,
    this.cargarHistorial,
  });

  final Equipo compresor;
  final Future<List<ChecklistCompresor>> Function(int)? cargarHistorial;

  @override
  State<ChecklistCompresorScreen> createState() =>
      _ChecklistCompresorScreenState();
}

class _ChecklistCompresorScreenState extends State<ChecklistCompresorScreen> {
  /// Que seccion esta abierta. Solo una: en 800 px dos abiertas obligan a
  /// hacer scroll a ciegas.
  int _abierta = 0;
  bool _guardando = false;

  final _horaInicio = TextEditingController();
  final _horaFin = TextEditingController();
  final _horas = TextEditingController();
  final _arranques = TextEditingController();

  /// Respuesta de cada inspeccion. Empieza sin responder: obligar a tocar cada
  /// una evita el "todo si" automatico que vacia de sentido al check list.
  final _respuestas =
      List<bool?>.filled(ChecklistCompresor.preguntas.length, null);
  late final List<TextEditingController> _observaciones;
  late final List<List<TextEditingController>> _mantenimiento;

  /// Que tareas de mantenimiento se hicieron HOY. Solo esas piden fecha y
  /// horas nuevas; el resto muestra el ultimo registro conocido sin guardarlo.
  final _mantenimientoHecho =
      List<bool>.filled(ChecklistCompresor.tareasMantenimiento.length, false);

  /// La ultima vez que se hizo cada tarea, sacada del check list mas reciente
  /// de este compresor (incluidos los descargados de la planta por USB).
  /// null = todavia cargando o sin registro previo.
  List<MantenimientoCompresor?> _ultimos =
      List.filled(ChecklistCompresor.tareasMantenimiento.length, null);
  bool _historialCargado = false;
  bool _errorHistorial = false;

  /// Lo que falta en cada seccion. Va en un notificador para que escribir una
  /// letra no repinte las once tarjetas de inspeccion.
  final _faltantes = ValueNotifier<Map<int, int>>(const {});

  @override
  void initState() {
    super.initState();
    _observaciones = List.generate(
      ChecklistCompresor.preguntas.length,
      (_) => TextEditingController()..addListener(_recontar),
    );
    _mantenimiento = List.generate(
      ChecklistCompresor.tareasMantenimiento.length,
      (_) => List.generate(
        3,
        (_) => TextEditingController()..addListener(_recontar),
      ),
    );
    for (final c in [_horaInicio, _horaFin, _horas, _arranques]) {
      c.addListener(_recontar);
    }
    _recontar();
    _cargarUltimosMantenimientos();
  }

  /// Busca, tarea por tarea, el registro mas reciente que tenga fecha u
  /// horas. Se recorre el historial completo y no solo el ultimo check list
  /// porque los viejos podian dejar la fila vacia si el tecnico no la sabia.
  Future<void> _cargarUltimosMantenimientos() async {
    try {
      final cargar =
          widget.cargarHistorial ?? DbHelper.instance.getChecklistsCompresor;
      final historial = historialCompresorConReferencias(
        await cargar(widget.compresor.localizacion),
      );
      final ultimos = List<MantenimientoCompresor?>.filled(
        ChecklistCompresor.tareasMantenimiento.length,
        null,
      );
      for (final checklist in historial) {
        for (var i = 0; i < ultimos.length; i++) {
          final tarea = checklist.mantenimientos[i];
          if (checklist.localizacion == widget.compresor.localizacion &&
              ultimos[i] == null &&
              tarea.tieneRegistro) {
            ultimos[i] = tarea;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _ultimos = ultimos;
        _historialCargado = true;
        _errorHistorial = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _historialCargado = true;
          _errorHistorial = true;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_horaInicio, _horaFin, _horas, _arranques]) {
      c.dispose();
    }
    for (final c in _observaciones) {
      c.dispose();
    }
    for (final fila in _mantenimiento) {
      for (final c in fila) {
        c.dispose();
      }
    }
    _faltantes.dispose();
    super.dispose();
  }

  bool _vacio(TextEditingController c) => c.text.trim().isEmpty;

  void _recontar() {
    var cabecera = 0;
    for (final c in [_horaInicio, _horaFin, _horas, _arranques]) {
      if (_vacio(c)) cabecera++;
    }

    var inspeccion = 0;
    for (var i = 0; i < _respuestas.length; i++) {
      if (_respuestas[i] == null) {
        inspeccion++;
      } else if (_respuestas[i] == false && _vacio(_observaciones[i])) {
        // Un NO sin explicacion no sirve de nada: el que lee el formato
        // necesita saber que se encontro.
        inspeccion++;
      }
    }

    // Solo se exige lo de las tareas marcadas con SI: decir que se hizo el
    // mantenimiento y no anotar cuando ni con que horometro dejaria al
    // proximo check list sin su "ultima vez". Las que van en NO no piden nada.
    var mantenimiento = 0;
    for (var i = 0; i < _mantenimiento.length; i++) {
      if (!_mantenimientoHecho[i]) continue;
      if (_vacio(_mantenimiento[i][0]) || _vacio(_mantenimiento[i][1])) {
        mantenimiento++;
      }
    }

    _faltantes.value = {0: cabecera, 1: inspeccion, 2: mantenimiento};
  }

  int get _hallazgos => _respuestas.where((r) => r == false).length;

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_historialCargado || _errorHistorial) {
      avisar(
          context,
          'Espera a que cargue el historial de mantenimiento. '
          'Si falló, vuelve a abrir la planilla.',
          AppColors.warning);
      return;
    }
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ahora = DateTime.now().toIso8601String();

      // El check list es un trabajo mas del equipo, asi que abre su orden y
      // queda con numero propio en el historial.
      //
      // La orden va sin servicios marcados porque ninguno de los siete que
      // conoce ORDENES_TRABAJO_LOCAL aplica a un compresor: el trabajo hecho
      // es el check list, y ese vive en su propia tabla apuntando a esta ODT.
      final odt = await DbHelper.instance.createWorkOrder(
        equipo: widget.compresor,
        services: const {},
      );

      final checklist = ChecklistCompresor(
        uuid: const Uuid().v4(),
        localizacion: widget.compresor.localizacion,
        equipo: widget.compresor.equipo,
        subsistema: widget.compresor.subsistema,
        tag: widget.compresor.qrDisplay,
        fecha: ahora.substring(0, 10),
        hora: ahora.substring(11, 19),
        horaInicio: _horaInicio.text.trim(),
        horaFin: _horaFin.text.trim(),
        numeroHoras: int.tryParse(_horas.text.trim()) ?? 0,
        numeroArranques: int.tryParse(_arranques.text.trim()) ?? 0,
        actividades: [for (final r in _respuestas) r ?? false],
        observaciones: [for (final c in _observaciones) c.text.trim()],
        mantenimientos: mantenimientosRealizados(_mantenimientoHecho, [
          for (final fila in _mantenimiento)
            MantenimientoCompresor(
              ultimaFecha: fila[0].text.trim(),
              horas: fila[1].text.trim(),
              observacion: fila[2].text.trim(),
            ),
        ]),
        usuario: (prefs.getString('responsable') ?? prefs.getString('username'))
            ?.trim(),
        cargo: (prefs.getString('cargo') ?? prefs.getString('rol'))?.trim(),
        odt: odt,
      );

      await DbHelper.instance.insertChecklistCompresor(checklist);
      if (!mounted) return;
      Navigator.pop(context, true);
      avisar(
        context,
        _hallazgos == 0
            ? 'Check list guardado. ODT $odt, sin hallazgos.'
            : 'Check list guardado. ODT $odt, con $_hallazgos hallazgo'
                '${_hallazgos == 1 ? '' : 's'}.',
        _hallazgos == 0 ? AppColors.success : AppColors.warning,
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
        titulo: 'Check list de compresor',
      ),
      body: Column(
        children: [
          _cabeceraEquipo(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              children: [
                SeccionPlegable(
                  indice: 0,
                  abierta: _abierta == 0,
                  icono: Icons.schedule_rounded,
                  titulo: 'Datos de la jornada',
                  resumen: 'Horario, horometro y arranques',
                  explicacion:
                      'Es la cabecera del formato: a que hora se empezo y se '
                      'termino, y que marcaba la unidad al revisarla.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _jornada,
                ),
                SeccionPlegable(
                  indice: 1,
                  abierta: _abierta == 1,
                  icono: Icons.checklist_rounded,
                  titulo: 'Inspeccion y control mecanico',
                  resumen: '${ChecklistCompresor.preguntas.length} preguntas',
                  explicacion:
                      'Las once del formato, en el mismo orden. Cada NO pide '
                      'una observacion obligatoria; con SI tambien se puede '
                      'anotar, por si hay algo que valga la pena dejar dicho.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _inspeccion,
                ),
                SeccionPlegable(
                  indice: 2,
                  abierta: _abierta == 2,
                  icono: Icons.build_rounded,
                  titulo: 'Control de mantenimiento',
                  resumen: 'Última vez y tareas hechas hoy',
                  explicacion:
                      'La app muestra cuando se hizo cada tarea por ultima '
                      'vez y con que horometro. Si hoy se hizo alguna, '
                      'marcala y anota la fecha y las horas nuevas.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _controlMantenimiento,
                ),
              ],
            ),
          ),
          _pie(),
        ],
      ),
    );
  }

  void _alternar(int i) => setState(() => _abierta = _abierta == i ? -1 : i);

  Widget _cabeceraEquipo() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.teal.withValues(alpha: .20),
              AppColors.teal.withValues(alpha: .06),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.teal.withValues(alpha: .40)),
        ),
        child: Row(children: [
          const Icon(Icons.hvac_rounded, size: 22, color: AppColors.teal),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.compresor.equipo,
                    style: AppText.seccion.copyWith(color: AppColors.teal)),
                Text(
                  '${widget.compresor.qrDisplay} · '
                  '${widget.compresor.subsistema}',
                  maxLines: 2,
                  style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ]),
      );

  Widget _campo(
    TextEditingController control,
    String etiqueta, {
    String? ayuda,
    bool numerico = false,
    int lineas = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: control,
          minLines: lineas,
          maxLines: lineas,
          textCapitalization: TextCapitalization.characters,
          keyboardType: numerico ? TextInputType.number : null,
          inputFormatters:
              numerico ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: etiqueta,
            helperText: ayuda,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  /// Hora que se elige deslizando ruedas, no escribiendo.
  ///
  /// A mano salia de todo ('8', '8:5', '08.30') y con guantes puestos el
  /// teclado es un estorbo. La caja no se puede teclear: al tocarla abre el
  /// selector y la hora siempre queda como HH:mm.
  Widget _campoHora(TextEditingController control, String etiqueta) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: control,
          readOnly: true,
          key: Key('campo-$etiqueta'),
          decoration: InputDecoration(
            labelText: etiqueta,
            suffixIcon: const Icon(Icons.schedule_rounded, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onTap: () async {
            final elegida = await elegirHoraConRuedas(
              context,
              inicial: control.text,
              titulo: etiqueta,
            );
            if (elegida != null) control.text = elegida;
          },
        ),
      );

  Widget get _jornada => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: _campoHora(_horaInicio, 'Hora de inicio')),
            const SizedBox(width: 10),
            Expanded(child: _campoHora(_horaFin, 'Hora de fin')),
          ]),
          _campo(_horas, 'Numero de horas',
              ayuda: 'Horometro de la unidad', numerico: true),
          _campo(_arranques, 'Numero de arranques', numerico: true),
        ],
      );

  Widget get _inspeccion => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ChecklistCompresor.preguntas.length; i++)
            _Pregunta(
              numero: i + 1,
              texto: ChecklistCompresor.preguntas[i],
              respuesta: _respuestas[i],
              observacion: _observaciones[i],
              onResponder: (valor) {
                setState(() => _respuestas[i] = valor);
                _recontar();
              },
            ),
        ],
      );

  /// Marca una tarea como hecha hoy y pre-llena lo obvio: la fecha de hoy y
  /// el horometro que el tecnico ya escribio en la cabecera. Editables, por
  /// si el trabajo fue mas temprano o el contador marcaba otra cosa.
  /// Marca si la tarea se hizo. Con SI se abren los campos ya propuestos con
  /// la fecha de hoy y el horometro de la cabecera: en la mayoria de los
  /// casos es justo eso, y si no, se corrigen. Con NO no se borra nada, solo
  /// se ocultan: si se marco por error, lo escrito sigue ahi.
  void _marcarHecho(int i, bool hecho) {
    setState(() => _mantenimientoHecho[i] = hecho);
    if (hecho) {
      if (_vacio(_mantenimiento[i][0])) {
        final hoy = DateTime.now();
        _mantenimiento[i][0].text = '${hoy.day.toString().padLeft(2, '0')}/'
            '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
      }
      if (_vacio(_mantenimiento[i][1]) && !_vacio(_horas)) {
        _mantenimiento[i][1].text = _horas.text.trim();
      }
    }
    _recontar();
  }

  /// La linea "ultima vez" de una tarea: lo que dijo el check list anterior.
  Widget _ultimaVez(int i) {
    final ultimo = _ultimos[i];
    final sinRegistro = ultimo == null;
    final texto = !_historialCargado
        ? 'Buscando el último registro…'
        : _errorHistorial
            ? 'No se pudo cargar el historial. Vuelve a abrir la planilla.'
            : sinRegistro
                ? 'Sin registro previo'
                : [
                    if (ultimo.ultimaFecha.isNotEmpty)
                      'Última vez: ${ultimo.ultimaFecha}',
                    if (ultimo.horas.isNotEmpty) '${ultimo.horas} horas',
                    if (ultimo.observacion.isNotEmpty) ultimo.observacion,
                  ].join(' · ');
    return Row(children: [
      Icon(
        sinRegistro ? Icons.help_outline_rounded : Icons.history_rounded,
        size: 15,
        color: sinRegistro ? AppColors.textHint : AppColors.teal,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          texto,
          style: AppText.apoyo.copyWith(
            color: sinRegistro ? AppColors.textHint : AppColors.teal,
          ),
        ),
      ),
    ]);
  }

  /// La fecha se elige en un calendario, no se teclea.
  ///
  /// Escrita a mano entraba de todo —incluso una hora, '11PM', que despues
  /// nadie podia interpretar como fecha. Con el calendario siempre queda
  /// dd/mm/aaaa y no se puede meter algo que no sea un dia.
  Widget _campoFecha(int i) {
    final control = _mantenimiento[i][0];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: control,
        readOnly: true,
        key: Key('mtto-fecha-$i'),
        decoration: const InputDecoration(
          labelText: 'Fecha',
          helperText: 'Cuándo se hizo',
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onTap: () async {
          final hoy = DateTime.now();
          final elegida = await showDatePicker(
            context: context,
            initialDate: _fechaDe(control.text) ?? hoy,
            // Un mantenimiento puede ser de hace anios; futuro no existe.
            firstDate: DateTime(hoy.year - 10),
            lastDate: hoy,
            helpText: 'Fecha del mantenimiento',
          );
          if (elegida == null) return;
          control.text = '${elegida.day.toString().padLeft(2, '0')}/'
              '${elegida.month.toString().padLeft(2, '0')}/${elegida.year}';
        },
      ),
    );
  }

  /// Lee 'dd/mm/aaaa' para que el calendario abra donde ya estaba.
  DateTime? _fechaDe(String texto) {
    final partes = texto.trim().split('/');
    if (partes.length != 3) return null;
    final d = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    final a = int.tryParse(partes[2]);
    if (d == null || m == null || a == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(a, m, d);
  }

  Widget get _controlMantenimiento => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '¿Se realizó cada tarea hoy? Si marcas NO, se mostrará y se '
              'imprimirá el último mantenimiento registrado, sin repetirlo '
              'como un trabajo nuevo.',
              style: AppText.apoyo,
            ),
          ),
          for (var i = 0;
              i < ChecklistCompresor.tareasMantenimiento.length;
              i++) ...[
            Text(
              ChecklistCompresor.tareasMantenimiento[i],
              style: AppText.etiqueta.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            _ultimaVez(i),
            const SizedBox(height: 8),
            // ¿Se le hizo esta tarea? Con SI se abren la fecha y las horas
            // para anotarlas; con NO no hay nada que llenar. La pantalla y
            // la impresion consultan el ultimo registro sin volver a guardarlo.
            Row(children: [
              Expanded(
                child: OpcionBinaria(
                  texto: 'SÍ',
                  elegido: _mantenimientoHecho[i],
                  color: AppColors.success,
                  onTap: () => _marcarHecho(i, true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OpcionBinaria(
                  texto: 'NO',
                  elegido: !_mantenimientoHecho[i],
                  color: AppColors.textSecondary,
                  onTap: () => _marcarHecho(i, false),
                ),
              ),
            ]),
            if (_mantenimientoHecho[i]) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _campoFecha(i)),
                const SizedBox(width: 10),
                Expanded(
                  child: _campo(_mantenimiento[i][1], 'Horas del equipo',
                      ayuda: 'Horómetro al hacerla', numerico: true),
                ),
              ]),
              _campo(_mantenimiento[i][2], 'Observación (opcional)'),
            ],
            if (i < ChecklistCompresor.tareasMantenimiento.length - 1)
              const Divider(height: 20),
          ],
        ],
      );

  Widget _pie() => PieFormulario(
        faltantes: _faltantes,
        textoBoton: 'GUARDAR CHECK LIST',
        guardando: _guardando,
        onGuardar: _guardar,
        // Cuando ya no falta nada pero hay puntos en NO, el pie lo avisa
        // antes de guardar: un check list con hallazgos no es un error, pero
        // conviene que quien firma lo sepa.
        extra: _hallazgos == 0
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  const Icon(Icons.report_problem_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _hallazgos == 1
                          ? '1 punto quedó en NO'
                          : '$_hallazgos puntos quedaron en NO',
                      style: AppText.apoyo.copyWith(color: AppColors.warning),
                    ),
                  ),
                ]),
              ),
      );
}

/// Una inspeccion del formato: la pregunta, SI/NO y su observacion.
class _Pregunta extends StatelessWidget {
  const _Pregunta({
    required this.numero,
    required this.texto,
    required this.respuesta,
    required this.observacion,
    required this.onResponder,
  });

  final int numero;
  final String texto;
  final bool? respuesta;
  final TextEditingController observacion;
  final void Function(bool) onResponder;

  @override
  Widget build(BuildContext context) {
    // El NO se pinta distinto: es lo que despues hay que ir a resolver, y
    // tiene que saltar a la vista al repasar el formulario.
    final color = respuesta == null
        ? AppColors.border
        : respuesta!
            ? AppColors.success
            : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: respuesta == null ? AppColors.border : color,
          width: respuesta == null ? 1 : 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: color.withValues(alpha: .45)),
              ),
              child:
                  Text('$numero', style: AppText.micro.copyWith(color: color)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                texto,
                style: AppText.cuerpo.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OpcionBinaria(
                texto: 'SI',
                elegido: respuesta == true,
                color: AppColors.success,
                onTap: () => onResponder(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OpcionBinaria(
                texto: 'NO',
                elegido: respuesta == false,
                color: AppColors.warning,
                onTap: () => onResponder(false),
              ),
            ),
          ]),
          // La caja aparece al responder, con reglas distintas: el NO exige
          // explicar que se encontro; el SI tambien puede llevar nota (una
          // fuga reparada en el momento, un detalle a vigilar), pero nadie
          // esta obligado a escribirla.
          if (respuesta != null) ...[
            const SizedBox(height: 10),
            // Escucha su propio controlador para que el aviso de obligatoria
            // se apague en cuanto el tecnico escribe. Sin esto el regano rojo
            // quedaba pintado hasta que algo mas repintara la tarjeta. Va
            // aparte y no con un setState del formulario: repintar las once
            // preguntas en cada tecla es justo lo que se evita aqui.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: observacion,
              builder: (context, valor, _) => TextField(
                controller: observacion,
                minLines: respuesta! ? 1 : 2,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText:
                      respuesta! ? 'Observación (opcional)' : 'Observación',
                  hintText: respuesta!
                      ? 'Algún detalle que valga la pena anotar'
                      : 'Qué se encontró',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: respuesta! == false && valor.text.trim().isEmpty
                      ? 'Obligatoria porque la respuesta es NO'
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Seccion plegable, igual que en el registro de equipo nuevo.
