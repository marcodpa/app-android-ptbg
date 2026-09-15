import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/compatibilidad_equipos.dart';
import '../models/equipo_nuevo.dart';
import '../models/equipo_visual_config.dart';
import '../theme.dart';
import '../widgets/avisos.dart';
import '../widgets/decode_imagen.dart';
import '../widgets/formulario_industrial.dart';
import 'qr_etiqueta_screen.dart';
import '../widgets/industrial_navigation.dart';

/// Registro de un equipo que todavia no existe en la planta.
///
/// Va en acordeon y no en pasos porque no es un tramite con orden: el tecnico
/// llega con la placa a la vista y llena lo que puede leer, en el orden que
/// pueda. Cada seccion dice cuanto le falta, asi que puede saltar entre ellas
/// sin perder de vista lo que queda.
///
/// Se pide todo porque un equipo se da de alta una sola vez en su vida: lo que
/// se deje para despues termina en fichas a medias que nadie vuelve a
/// completar. La unica salida es declarar que el equipo no se lubrica.
class NuevoEquipoScreen extends StatefulWidget {
  const NuevoEquipoScreen({super.key});

  @override
  State<NuevoEquipoScreen> createState() => _NuevoEquipoScreenState();
}

class _NuevoEquipoScreenState extends State<NuevoEquipoScreen> {
  int? _localizacion;
  List<Map<String, dynamic>> _sistemas = const [];
  List<String> _subsistemas = const [];
  bool _guardando = false;

  int? _codeSys;
  int? _ptEq;
  int? _familia;

  /// Pide una familia propia en vez de sumarse a una existente.
  bool _familiaPropia = false;

  Map<int, String> _familias = const {};
  int _familiaPropuesta = 0;
  bool _sinLubricacion = false;

  /// Que seccion esta abierta. Solo una a la vez: en una tablet de 800 px, dos
  /// secciones abiertas dejan al tecnico haciendo scroll a ciegas.
  int _abierta = 0;

  final _nombre = TextEditingController();
  final _subsistema = TextEditingController();
  final _tagname = TextEditingController();
  final _codeQr = TextEditingController();
  String _ultimaSugerencia = '';

  final _campos = <String, TextEditingController>{};
  final _piezas = <int, Map<String, TextEditingController>>{};

  /// Cuantos campos faltan en cada seccion.
  ///
  /// Es un ValueNotifier y no estado del widget a proposito: escribir una letra
  /// solo repinta las pastillas de estado y el boton final, no las treinta
  /// cajas de texto. Con setState en cada tecla la pantalla se arrastraba.
  final _faltantes = ValueNotifier<Map<int, int>>(const {});

  static const _camposMotor = <String, String>{
    'marca': 'Marca',
    'modelo': 'Modelo',
    'serial': 'Serial',
    'hp': 'Potencia (HP)',
    'arranque': 'Arranque',
    'voltaje': 'Voltaje',
    'corriente': 'Corriente (FLA)',
    'sf': 'Factor de servicio (SF)',
    'ciclo': 'Ciclo (Hz)',
    'ph': 'Fases (PH)',
    'rpm': 'RPM',
    'frame': 'Frame',
    'brgs_drive': 'Rodamiento lado acople',
    'brgs_opp': 'Rodamiento lado libre',
  };

  static const _camposLubricacion = <String, String>{
    'lubricacion': 'Tipo de lubricacion',
    'motores_lub': 'Lubricante del motor',
    'cant_mot_lub': 'Gramos por motor',
    'elec_mot_lub': 'Gramos motor - electrico',
    'man_mot_lub': 'Gramos motor - manual',
    'elemento_lub': 'Elemento lubricado',
    'cant_elem_lub': 'Gramos por elemento',
    'elec_elem_lub': 'Gramos elemento - electrico',
    'man_elem_lub': 'Gramos elemento - manual',
  };

  static const _numericos = <String>{
    'cant_mot_lub',
    'elec_mot_lub',
    'man_mot_lub',
    'cant_elem_lub',
    'elec_elem_lub',
    'man_elem_lub',
  };

  static const _nombrePieza = <int, String>{
    2: 'Bomba',
    3: 'Caja multiplicadora',
    4: 'Ventilador',
  };

  @override
  void initState() {
    super.initState();
    for (final clave in [..._camposMotor.keys, ..._camposLubricacion.keys]) {
      _campos[clave] = TextEditingController()..addListener(_recontar);
    }
    _nombre.addListener(_recontar);
    _subsistema.addListener(_recontar);
    _codeQr.addListener(_recontar);
    _tagname.addListener(_sugerirQr);
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    for (final pieza in _piezas.values) {
      for (final c in pieza.values) {
        c.dispose();
      }
    }
    _nombre.dispose();
    _subsistema.dispose();
    _tagname.dispose();
    _codeQr.dispose();
    _faltantes.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final siguiente = await DbHelper.instance.siguienteLocalizacion();
      final sistemas = await DbHelper.instance.sistemasDisponibles();
      final familias = await DbHelper.instance.familiasExistentes();
      final proximaFamilia = await DbHelper.instance.siguienteFamilia();
      if (!mounted) return;
      setState(() {
        _localizacion = siguiente;
        _sistemas = sistemas;
        _familias = familias;
        _familiaPropuesta = proximaFamilia;
      });
      _recontar();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _cargarSubsistemas(int codeSys) async {
    final lista = await DbHelper.instance.subsistemasDe(codeSys);
    if (mounted) setState(() => _subsistemas = lista);
  }

  /// Propone el TAG como codigo QR mientras no se escriba otro.
  ///
  /// No se antepone el area de planta (10, 11, 12) porque no se deduce del
  /// sistema: DEMINERALIZED WATER tiene equipos con las tres. El tecnico copia
  /// lo que diga la etiqueta real, que es lo que el lector va a encontrar.
  void _sugerirQr() {
    final sugerido = _tagname.text.trim();
    if (_codeQr.text.isEmpty || _codeQr.text == _ultimaSugerencia) {
      _codeQr.text = sugerido;
      _ultimaSugerencia = sugerido;
    }
    _recontar();
  }

  Map<String, TextEditingController> _controlesPieza(int tipo) =>
      _piezas.putIfAbsent(
        tipo,
        () => {
          'marca': TextEditingController()..addListener(_recontar),
          'modelo': TextEditingController()..addListener(_recontar),
          'serial': TextEditingController()..addListener(_recontar),
        },
      );

  bool _vacio(TextEditingController c) => c.text.trim().isEmpty;

  /// Recalcula cuanto falta en cada seccion sin repintar el formulario.
  void _recontar() {
    var identidad = 0;
    if (_vacio(_nombre)) identidad++;
    if (_codeSys == null) identidad++;
    if (_vacio(_subsistema)) identidad++;
    if (_vacio(_tagname)) identidad++;
    if (_vacio(_codeQr)) identidad++;

    final tipo = _ptEq == null ? 1 : 0;
    final compat = (_familiaPropia || _familia != null) ? 0 : 1;

    var motor = 0;
    for (final clave in _camposMotor.keys) {
      if (_vacio(_campos[clave]!)) motor++;
    }
    if (!_sinLubricacion) {
      for (final clave in _camposLubricacion.keys) {
        if (_vacio(_campos[clave]!)) motor++;
      }
    }

    var piezas = 0;
    for (final t in EquipoNuevo.tiposDePieza(_ptEq ?? 0)) {
      for (final c in _controlesPieza(t).values) {
        if (_vacio(c)) piezas++;
      }
    }

    _faltantes.value = {0: identidad, 1: tipo, 2: compat, 3: motor, 4: piezas};
  }

  String _txt(String clave) => _campos[clave]!.text.trim();

  double? _num(String clave) {
    final texto = _txt(clave).replaceAll(',', '.');
    return texto.isEmpty ? null : double.tryParse(texto);
  }

  Future<void> _guardar() async {
    if (_guardando || _localizacion == null) return;
    setState(() => _guardando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ahora = DateTime.now().toIso8601String();
      final sistema = _sistemas.firstWhere(
        (s) => s['code'] == _codeSys,
        orElse: () => const {'nombre': ''},
      );

      final equipo = EquipoNuevo(
        uuid: const Uuid().v4(),
        localizacion: _localizacion!,
        equipo: _nombre.text.trim(),
        codeSys: _codeSys!,
        sistema: (sistema['nombre'] ?? '').toString(),
        subsistema: _subsistema.text.trim(),
        tagname: _tagname.text.trim(),
        codeQr: _codeQr.text.trim(),
        ptEq: _ptEq!,
        // CODE_CONJUNTO es el codigo del sistema, no un dato aparte: en las 79
        // ordenes y las 99 piezas de la planta son siempre el mismo numero.
        codeConjunto: _codeSys!,
        // Nunca va vacia: si el equipo es el primero de los suyos pide una
        // familia propia y el numero se lo pone el servidor al subir.
        familiaCompat: _familiaPropia
            ? EquipoNuevo.familiaNueva
            : _familia ?? EquipoNuevo.familiaNueva,
        motor: FichaMotor(
          marca: _txt('marca'),
          modelo: _txt('modelo'),
          serial: _txt('serial'),
          hp: _txt('hp'),
          arranque: _txt('arranque'),
          voltaje: _txt('voltaje'),
          corriente: _txt('corriente'),
          sf: _txt('sf'),
          ciclo: _txt('ciclo'),
          ph: _txt('ph'),
          rpm: _txt('rpm'),
          frame: _txt('frame'),
          brgsDrive: _txt('brgs_drive'),
          brgsOpp: _txt('brgs_opp'),
          lubricacion: _sinLubricacion ? '' : _txt('lubricacion'),
          motoresLub: _sinLubricacion ? '' : _txt('motores_lub'),
          cantMotLub: _sinLubricacion ? null : _num('cant_mot_lub'),
          elecMotLub: _sinLubricacion ? null : _num('elec_mot_lub'),
          manMotLub: _sinLubricacion ? null : _num('man_mot_lub'),
          elementoLub: _sinLubricacion ? '' : _txt('elemento_lub'),
          cantElemLub: _sinLubricacion ? null : _num('cant_elem_lub'),
          elecElemLub: _sinLubricacion ? null : _num('elec_elem_lub'),
          manElemLub: _sinLubricacion ? null : _num('man_elem_lub'),
          sinLubricacion: _sinLubricacion,
        ),
        piezas: [
          for (final tipo in EquipoNuevo.tiposDePieza(_ptEq!))
            PiezaEquipo(
              tipo: tipo,
              marca: _controlesPieza(tipo)['marca']!.text.trim(),
              modelo: _controlesPieza(tipo)['modelo']!.text.trim(),
              serial: _controlesPieza(tipo)['serial']!.text.trim(),
            ),
        ],
        usuario: (prefs.getString('responsable') ?? prefs.getString('username'))
            ?.trim(),
        cargo: (prefs.getString('cargo') ?? prefs.getString('rol'))?.trim(),
        fecha: ahora.substring(0, 10),
        hora: ahora.substring(11, 19),
      );

      await DbHelper.instance.crearEquipoNuevo(equipo);
      CompatibilidadEquipos.cargarAsignadas(
        await DbHelper.instance.familiasAsignadas(),
      );
      if (!mounted) return;
      await _ofrecerEtiqueta(equipo);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      avisar(context, 'No se pudo registrar: $error', AppColors.error);
    }
  }

  /// Un equipo nuevo no tiene etiqueta pegada todavia, asi que se ofrece aqui
  /// mismo: es el momento en que el tecnico sigue parado frente al equipo.
  Future<void> _ofrecerEtiqueta(EquipoNuevo equipo) async {
    final ver = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Equipo registrado'),
        content: Text(
          '${equipo.equipo} quedo guardado como LOC-${equipo.localizacion}.\n\n'
          'Todavia no tiene etiqueta pegada. Puedes generar su QR ahora y '
          'guardarlo o imprimirlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('DESPUES'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('VER QR'),
          ),
        ],
      ),
    );
    if (ver != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QrEtiquetaScreen(
          codeQr: equipo.codeQr,
          equipo: equipo.equipo,
          localizacion: equipo.localizacion,
          sistema: equipo.sistema,
          subsistema: equipo.subsistema,
          tag: equipo.tagname,
        ),
      ),
    );
  }

  // ── Construccion ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_localizacion == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const IndustrialAppBar(
        titulo: 'Registrar equipo nuevo',
        subtitulo: 'Alta de un conjunto en planta',
        panel: true,
      ),
      body: Column(
        children: [
          _cabecera(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              children: [
                SeccionPlegable(
                  indice: 0,
                  abierta: _abierta == 0,
                  icono: Icons.badge_outlined,
                  titulo: 'Identificacion',
                  resumen: 'Como se llama y como se encuentra',
                  explicacion:
                      'El nombre y el sistema son con los que el equipo va a '
                      'aparecer en las listas y en los reportes. El codigo QR '
                      'es lo que leera el lector en planta.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _identidad,
                ),
                SeccionPlegable(
                  indice: 1,
                  abierta: _abierta == 1,
                  icono: Icons.precision_manufacturing_outlined,
                  titulo: 'Tipo de equipo',
                  resumen: 'Define que se le mide y con que dibujo',
                  explicacion:
                      'De esta eleccion salen la imagen que vera el tecnico al '
                      'medir y los puntos que se le toman. Elige el que se '
                      'parezca al equipo real.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _tipo,
                ),
                SeccionPlegable(
                  indice: 2,
                  abierta: _abierta == 2,
                  icono: Icons.link_rounded,
                  titulo: 'Compatibilidad',
                  resumen: 'Que repuestos podra recibir',
                  explicacion:
                      'Cuando una pieza vuelve del taller solo se ofrece para '
                      'equipos de su familia. Sin familia, este equipo quedaria '
                      'aislado y solo aceptaria piezas salidas de el mismo.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _compatibilidad,
                ),
                SeccionPlegable(
                  indice: 3,
                  abierta: _abierta == 3,
                  icono: Icons.bolt_rounded,
                  titulo: 'Placa del motor',
                  resumen: 'Los datos grabados en la chapa',
                  explicacion:
                      'Se copian tal cual estan en la placa. Son los que salen '
                      'en la ficha tecnica y en la planilla oficial impresa.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _motor,
                ),
                SeccionPlegable(
                  indice: 4,
                  abierta: _abierta == 4,
                  icono: Icons.settings_rounded,
                  titulo: 'Demas piezas',
                  resumen: _resumenPiezas(),
                  explicacion:
                      'De estas se guarda marca, modelo y serial, igual que en '
                      'un reemplazo. El serial es su identidad en el '
                      'inventario de componentes.',
                  faltantes: _faltantes,
                  onTap: _alternar,
                  hijo: _piezasSeccion,
                ),
              ],
            ),
          ),
          _pie(),
        ],
      ),
    );
  }

  void _alternar(int indice) {
    setState(() => _abierta = _abierta == indice ? -1 : indice);
  }

  String _resumenPiezas() {
    if (_ptEq == null) return 'Elige antes el tipo de equipo';
    final tipos = EquipoNuevo.tiposDePieza(_ptEq!);
    if (tipos.isEmpty) return 'Este tipo solo lleva motor';
    return tipos.map((t) => _nombrePieza[t] ?? 'Pieza').join(' y ');
  }

  Widget _cabecera() => Container(
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.pin_drop_rounded,
                size: 19, color: AppColors.teal),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sera la LOC-$_localizacion',
                  style: AppText.seccion.copyWith(color: AppColors.teal),
                ),
                Text(
                  'Ese numero es su identidad: de el cuelgan el QR, las '
                  'mediciones y todo su historial.',
                  style: AppText.apoyo.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ]),
      );

  /// Pie fijo. Solo se repinta el, no el formulario, cuando cambia lo que falta.
  Widget _pie() => PieFormulario(
        faltantes: _faltantes,
        textoBoton: 'REGISTRAR EQUIPO',
        textoBotonGuardando: 'REGISTRANDO...',
        guardando: _guardando,
        onGuardar: _guardar,
      );

  // ── Contenido de cada seccion ─────────────────────────────────────────────

  Widget _campo(
    TextEditingController control,
    String etiqueta, {
    String? ayuda,
    bool numerico = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: control,
          textCapitalization: TextCapitalization.characters,
          keyboardType: numerico
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          inputFormatters: numerico
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          decoration: InputDecoration(
            labelText: etiqueta,
            helperText: ayuda,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget get _identidad => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _campo(_nombre, 'Nombre del equipo',
              ayuda: 'Como se le dice en planta: NOX-LIQUIDO, VENT TURB A...'),
          DropdownButtonFormField<int>(
            initialValue: _codeSys,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sistema',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final sistema in _sistemas)
                DropdownMenuItem(
                  value: sistema['code'] as int,
                  child: Text('${sistema['nombre']}'),
                ),
            ],
            onChanged: (valor) {
              if (valor == null) return;
              setState(() {
                _codeSys = valor;
                _subsistema.text = '';
              });
              _cargarSubsistemas(valor);
              _recontar();
            },
          ),
          const SizedBox(height: 10),
          if (_subsistemas.isNotEmpty) ...[
            Text(
              'Subsistemas que ya existen en ese sistema:',
              style: AppText.apoyo.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 6),
            // Se ofrecen los existentes para no crear variantes por un acento
            // o un plural: el subsistema agrupa equipos en los filtros.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sub in _subsistemas)
                  ActionChip(
                    label: Text(sub, style: AppText.apoyo),
                    onPressed: () {
                      _subsistema.text = sub;
                      _recontar();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _campo(_subsistema, 'Subsistema'),
          _campo(_tagname, 'TAG del SCADA', ayuda: 'Por ejemplo MOT-6242'),
          _campo(_codeQr, 'Codigo QR',
              ayuda: 'Lo que dice la etiqueta pegada al equipo. Si aun no '
                  'tiene, al terminar se genera para imprimir.'),
        ],
      );

  Widget get _tipo => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var t = 1; t <= 10; t++) _opcionTipo(t),
        ],
      );

  Widget _opcionTipo(int tipo) {
    final config = EquipoVisualResolver.porTipo(tipo);
    if (config == null) return const SizedBox.shrink();
    final elegido = _ptEq == tipo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _ptEq = tipo);
          _recontar();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color:
                elegido ? AppColors.teal.withValues(alpha: .12) : AppColors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: elegido ? AppColors.teal : AppColors.border,
              width: elegido ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 78,
                height: 56,
                color: const Color(0xFFC0C0C0),
                child: Image.asset(
                  config.cleanAsset,
                  fit: BoxFit.contain,
                  cacheWidth: anchoDecode(context, anchoLogico: 78),
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.precision_manufacturing_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.nombre,
                    style: AppText.seccion.copyWith(
                      color: elegido ? AppColors.teal : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tipo $tipo · ${_descripcionPiezas(tipo)}',
                    style: AppText.apoyo.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              elegido
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: elegido ? AppColors.teal : AppColors.textHint,
              size: 21,
            ),
          ]),
        ),
      ),
    );
  }

  String _descripcionPiezas(int tipo) {
    final piezas = EquipoNuevo.tiposDePieza(tipo);
    if (piezas.isEmpty) return 'solo motor';
    const cortos = {2: 'bomba', 3: 'caja', 4: 'ventilador'};
    return 'motor y ${piezas.map((t) => cortos[t]).join(', ')}';
  }

  Widget get _compatibilidad => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _familiaPropia,
            activeThumbColor: AppColors.teal,
            title: const Text(
              'Es el primero de su familia',
              style: AppText.cuerpoFuerte,
            ),
            subtitle: Text(
              'Hoy no comparte piezas con ningun otro equipo. Se le abre la '
              'familia $_familiaPropuesta para que cuando entre su gemelo '
              '—el de la otra turbina, por ejemplo— se le pueda sumar.',
              style: AppText.apoyo,
            ),
            onChanged: (valor) {
              setState(() {
                _familiaPropia = valor;
                if (valor) _familia = null;
              });
              _recontar();
            },
          ),
          if (!_familiaPropia) ...[
            const SizedBox(height: 6),
            Text(
              'Elige la familia a la que pertenece:',
              style: AppText.apoyo.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 8),
            for (final entrada in _familias.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () {
                    setState(() => _familia = entrada.key);
                    _recontar();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 10),
                    decoration: BoxDecoration(
                      color: _familia == entrada.key
                          ? AppColors.teal.withValues(alpha: .12)
                          : AppColors.bg2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _familia == entrada.key
                            ? AppColors.teal
                            : AppColors.border,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        _familia == entrada.key
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: _familia == entrada.key
                            ? AppColors.teal
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 9),
                      // El numero se muestra: es el que el supervisor ve en la
                      // base de datos, y asi la pantalla y la tabla hablan el
                      // mismo idioma.
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${entrada.key}',
                          style: AppText.dato.copyWith(
                            color: _familia == entrada.key
                                ? AppColors.teal
                                : AppColors.textHint,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entrada.value,
                          style: AppText.cuerpo
                              .copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ],
      );

  Widget get _motor => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entrada in _camposMotor.entries)
            _campo(_campos[entrada.key]!, entrada.value),
          const Divider(height: 24),
          Text(
            'Lubricacion',
            style: AppText.seccion.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Cuanta grasa lleva y por donde. Es lo que despues propone la app '
            'al registrar una lubricacion.',
            style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sinLubricacion,
            activeThumbColor: AppColors.teal,
            title: const Text(
              'Este equipo no lleva lubricacion',
              style: AppText.cuerpoFuerte,
            ),
            subtitle: const Text(
              'Rodamientos sellados o sin graseras.',
              style: AppText.apoyo,
            ),
            onChanged: (valor) {
              setState(() => _sinLubricacion = valor);
              _recontar();
            },
          ),
          if (!_sinLubricacion)
            for (final entrada in _camposLubricacion.entries)
              _campo(
                _campos[entrada.key]!,
                entrada.value,
                numerico: _numericos.contains(entrada.key),
              ),
        ],
      );

  Widget get _piezasSeccion {
    if (_ptEq == null) {
      return Text(
        'Primero elige el tipo de equipo: de el depende que piezas lleva.',
        style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
      );
    }
    final tipos = EquipoNuevo.tiposDePieza(_ptEq!);
    if (tipos.isEmpty) {
      return Text(
        'Este tipo solo tiene motor, y ya quedo en la seccion anterior.',
        style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tipo in tipos) ...[
          Row(children: [
            Icon(
              tipo == 2
                  ? Icons.water_drop_rounded
                  : tipo == 3
                      ? Icons.settings_rounded
                      : Icons.air_rounded,
              size: 17,
              color: AppColors.teal,
            ),
            const SizedBox(width: 7),
            Text(
              _nombrePieza[tipo] ?? 'Pieza',
              style: AppText.seccion.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ]),
          const SizedBox(height: 9),
          _campo(_controlesPieza(tipo)['marca']!, 'Marca'),
          _campo(_controlesPieza(tipo)['modelo']!, 'Modelo'),
          _campo(_controlesPieza(tipo)['serial']!, 'Serial'),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
