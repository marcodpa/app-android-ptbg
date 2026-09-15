import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/db_helper.dart';
import '../models/mapa_marcadores.dart';
import '../models/equipo_visual_config.dart';
import '../models/mapa_planta.dart';
import '../models/models.dart';
import '../models/orden_reparacion.dart';
import '../theme.dart';
import '../widgets/industrial_header_style.dart';
import 'black_start_screen.dart';
import 'operation_selection_screen.dart';

/// El plano de la planta con los equipos encima.
///
/// Sirve para lo que en el papel se hace con el dedo: ubicarse. El mecanico
/// que no conoce un sistema ve donde queda, se acerca, y desde el mismo
/// marcador abre el equipo y arranca el servicio sin volver a buscarlo por
/// nombre en una lista de cincuenta.
class MapaPlantaScreen extends StatefulWidget {
  const MapaPlantaScreen({super.key});

  @override
  State<MapaPlantaScreen> createState() => _MapaPlantaScreenState();
}

class _MapaPlantaScreenState extends State<MapaPlantaScreen> {
  final _transformacion = TransformationController();

  List<MarcadorMapa> _marcadores = const [];
  Map<int, Equipo> _equipos = const {};
  bool _cargando = true;

  MarcadorMapa? _elegido;

  /// Sistema resaltado desde la leyenda; el resto se apaga.
  String? _filtro;

  // El plano tiene prioridad; los sistemas se despliegan solo al necesitarlos.
  bool _leyendaAbierta = false;

  /// Tamano del plano ya escalado para cubrir la pantalla, en pixeles
  /// logicos. Es mas grande que [_ventana] en uno de los dos lados.
  Size _plano = Size.zero;

  /// Lo que se ve del plano: el hueco que deja la pantalla.
  Size _ventana = Size.zero;

  @override
  void initState() {
    super.initState();
    // El plano es apaisado. En vertical queda una franja en medio de la
    // pantalla con dos tercios desperdiciados, asi que esta pantalla se abre
    // de lado y la tablet se voltea para verla. Al salir se devuelve el
    // bloqueo vertical que usa el resto de la app.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _cargar();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
    _transformacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    var equipos = <Equipo>[];
    var conOrden = <int>{};
    try {
      equipos = await DbHelper.instance.getAllEquipos();
      final ordenes =
          await DbHelper.instance.getOrdenesReparacion(abiertas: true);
      conOrden = ordenes
          .map((OrdenReparacion o) => o.ubicacionOrigen)
          .whereType<int>()
          .toSet();
    } catch (_) {
      // Sin base de datos el mapa se dibuja igual, solo que vacio: el plano
      // por si solo ya sirve para ubicarse.
    }
    if (!mounted) return;

    final marcadores = <MarcadorMapa>[];
    final porLocalizacion = <int, Equipo>{};
    for (final equipo in equipos) {
      final punto = mapaEquipos[equipo.localizacion];
      if (punto == null) continue;
      porLocalizacion[equipo.localizacion] = equipo;
      marcadores.add(MarcadorMapa(
        localizacion: equipo.localizacion,
        punto: punto,
        nombre: equipo.equipo,
        tag: (equipo.qrCode ?? '').trim(),
        sistema: equipo.sistema,
        color: colorDeSistema(equipo.sistema),
        conOrden: conOrden.contains(equipo.localizacion),
      ));
    }
    marcadores.add(const MarcadorMapa(
      localizacion: locBlackStart,
      punto: mapaBlackStart,
      nombre: 'BLACK START',
      tag: 'GEN. DIESEL',
      sistema: 'BLACK START',
      color: Color(0xFFFFD166),
    ));

    setState(() {
      _marcadores = marcadores;
      _equipos = porLocalizacion;
      _cargando = false;
    });
  }

  double get _escala => _transformacion.value.getMaxScaleOnAxis();

  /// Los que se dibujan segun el filtro de la leyenda.
  List<MarcadorMapa> get _visibles => _filtro == null
      ? _marcadores
      : _marcadores.where((m) => m.sistema == _filtro).toList();

  // ── Movimiento del plano ──────────────────────────────────────────────

  /// Deja el plano llenando la ventana, centrado.
  ///
  /// La identidad no sirve: el plano es mas grande que la ventana, asi que
  /// sin trasladar se veria pegado a la esquina de arriba a la izquierda.
  void _verTodo() {
    setState(() => _elegido = null);
    _centrar();
  }

  /// Deja el plano llenando la ventana sin tocar la seleccion.
  ///
  /// Va aparte de [_verTodo] porque tambien se llama al girar la tablet, y
  /// ahi perder el equipo que se acababa de tocar seria un fastidio.
  void _centrar() {
    _transformacion.value = Matrix4.identity()
      ..translateByDouble(
        -(_plano.width - _ventana.width) / 2,
        -(_plano.height - _ventana.height) / 2,
        0,
        1,
      );
  }

  /// Centra la vista en un punto del plano y se acerca.
  void _irA(PuntoMapa punto, {double escala = 4}) {
    if (_plano == Size.zero) return;
    final destinoX = _ventana.width / 2 - punto.x * _plano.width * escala;
    final destinoY = _ventana.height / 2 - punto.y * _plano.height * escala;
    _transformacion.value = Matrix4.identity()
      ..translateByDouble(destinoX, destinoY, 0, 1)
      ..scaleByDouble(escala, escala, escala, 1);
  }

  void _tocar(Offset posicion) {
    if (_plano == Size.zero) return;
    // La tolerancia se divide entre el zoom para que en pixeles de dedo sea
    // siempre la misma: acercarse afina la punteria en vez de engordarla.
    final elegido = marcadorMasCercano(
      _visibles,
      posicion,
      _plano,
      _RadiosMarcador.toque / _escala,
    );
    setState(() => _elegido = elegido);
    // No se mueve la vista al tocar: el mecanico acaba de apuntar ahi y que
    // el plano salte debajo del dedo desubica mas de lo que ayuda.
  }

  Future<void> _abrir() async {
    final elegido = _elegido;
    if (elegido == null) return;
    if (elegido.esBlackStart) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BlackStartScreen()),
      );
      return;
    }
    final equipo = _equipos[elegido.localizacion];
    if (equipo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperationSelectionScreen(equipo: equipo),
      ),
    );
    // Al volver puede haber una orden nueva: los marcadores la reflejan.
    await _cargar();
  }

  Future<void> _buscar() async {
    final elegido = await showModalBottomSheet<MarcadorMapa>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaBusqueda(marcadores: _marcadores),
    );
    if (elegido == null) return;
    setState(() {
      _elegido = elegido;
      _filtro = null;
    });
    _irA(elegido.punto);
  }

  /// Vuelve, venga de donde venga.
  ///
  /// Desde el inicio y desde la barra lateral se entra con
  /// `pushReplacementNamed`, asi que no hay nada que desapilar y un `pop` a
  /// secas dejaria la app sin pantalla. Solo se desapila cuando de verdad se
  /// llego encima de otra cosa.
  void _volver() {
    final navegador = Navigator.of(context);
    if (navegador.canPop()) {
      navegador.pop();
    } else {
      navegador.pushReplacementNamed('/home');
    }
  }

  // ── Pintado ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // La pantalla se pinta sobre el plano, que es oscuro, tanto de dia como
    // de noche: un plano CAD blanco sobre fondo claro no existe y forzarlo
    // arruinaria la lectura de las lineas.
    return PopScope(
      // Sin esto, el boton de atras de Android sale de la app en vez de
      // volver al inicio, porque aqui no hay nada apilado debajo.
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _volver();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F16),
        body: SafeArea(
          child: Column(children: [
            _barraSuperior(),
            Expanded(
                child: Stack(
              children: [
                Positioned.fill(child: _mapa()),
                if (!_cargando) _leyenda(),
                if (_elegido != null)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    width: 470,
                    child: _FichaElegido(
                      marcador: _elegido!,
                      equipo: _equipos[_elegido!.localizacion],
                      onAbrir: _abrir,
                      onCerrar: () => setState(() => _elegido = null),
                    ),
                  ),
                if (_cargando) const Center(child: CircularProgressIndicator()),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  /// Una sola fila: el header del panel con marca y subtitulo consumia mucho
  /// alto en horizontal. Conserva el estilo compartido sin cambiar otras vistas.
  Widget _barraSuperior() => Container(
        key: const Key('mapa-header'),
        decoration: IndustrialHeaderStyle.decoration,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
        child: LayoutBuilder(builder: (context, limites) {
          final estado = _cargando
              ? 'Cargando equipos…'
              : '${_marcadores.length} equipos ubicados';
          return Row(children: [
            _BotonBarra(
              icono: Icons.arrow_back_rounded,
              tooltip: 'Volver',
              onTap: _volver,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: estado,
                child: const IndustrialHeaderTitle(
                  title: 'Mapa de la planta',
                  compact: true,
                ),
              ),
            ),
            if (limites.maxWidth >= 600 &&
                MediaQuery.textScalerOf(context).scale(12) <= 18) ...[
              const SizedBox(width: 12),
              Text(estado, style: IndustrialHeaderStyle.subtitle),
            ],
            const SizedBox(width: 10),
            _BotonBarra(
              icono: Icons.search_rounded,
              tooltip: 'Buscar un equipo',
              onTap: _cargando ? null : _buscar,
            ),
            const SizedBox(width: 8),
            _BotonBarra(
              icono: Icons.fit_screen_rounded,
              tooltip: 'Ver toda la planta',
              onTap: _verTodo,
            ),
          ]);
        }),
      );

  Widget _mapa() {
    return LayoutBuilder(
      builder: (context, limites) {
        // El plano CUBRE la ventana en vez de encajar dentro: se escala hasta
        // que el lado corto llena la pantalla, y lo que sobra del lado largo
        // queda fuera para moverse con el dedo. Encajandolo entero quedaban
        // franjas negras arriba y abajo, y el mapa se veia como una foto
        // pegada en medio de la pantalla en vez de como un mapa.
        var ancho = limites.maxWidth;
        var alto = ancho / planoRelacion;
        if (alto < limites.maxHeight) {
          alto = limites.maxHeight;
          ancho = alto * planoRelacion;
        }
        final plano = Size(ancho, alto);
        final ventana = Size(limites.maxWidth, limites.maxHeight);
        if (plano != _plano || ventana != _ventana) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _plano = plano;
              _ventana = ventana;
            });
            _centrar();
          });
        }

        return ClipRect(
          child: SizedBox(
            width: ventana.width,
            height: ventana.height,
            child: InteractiveViewer(
              transformationController: _transformacion,
              // Sin `constrained` el hijo se ajustaria a la ventana y volveria
              // a caber entero; aqui se quiere justo lo contrario.
              constrained: false,
              minScale: 1,
              maxScale: 14,
              // Sin margen: el borde del plano nunca entra en la pantalla, asi
              // que no se ve nada que no sea el mapa. Alejarse del todo deja
              // el plano llenando la ventana y ahi se detiene.
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: ancho,
                height: alto,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (detalle) => _tocar(detalle.localPosition),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        planoPlanta,
                        fit: BoxFit.fill,
                        // Bilineal y no cubica: el plano se reescala en cada
                        // cuadro mientras se hace zoom y la diferencia de
                        // nitidez en lineas de un pixel no compensa el costo.
                        filterQuality: FilterQuality.low,
                        // Tope de decodificacion: el PNG es de 2000 px y sin
                        // esto se descomprime a ~9 MB de RGBA en una pantalla
                        // de 800. El doble del ancho fisico deja margen de
                        // sobra para el zoom; mas alla de eso el CAD ya no
                        // tiene detalle que ganar.
                        cacheWidth: (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context) *
                                2)
                            .round(),
                      ),
                      // Todo lo que va encima del plano se pinta en un solo
                      // lienzo, no como widgets. Cincuenta y tres marcadores
                      // mas los rotulos de zona eran ochenta widgets que se
                      // reconstruian en cada cuadro del gesto, y el mapa se
                      // arrastraba. Asi el zoom no reconstruye nada: el pintor
                      // escucha la transformacion y se repinta solo.
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _PintorMapa(
                            repaint: _transformacion,
                            transformacion: _transformacion,
                            marcadores: _visibles,
                            elegido: _elegido,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Leyenda ───────────────────────────────────────────────────────────

  Widget _leyenda() {
    final resumen = resumenSistemas(_marcadores);
    return Positioned(
      right: 12,
      top: 12,
      child: _Leyenda(
        altoMaximo: _ventana.height > 80
            ? (_ventana.height - 24).clamp(56.0, 380.0)
            : 380,
        resumen: resumen,
        filtro: _filtro,
        abierta: _leyendaAbierta,
        sinUbicar: mapaEquipos.length,
        onAbrirCerrar: () => setState(() => _leyendaAbierta = !_leyendaAbierta),
        onElegir: (sistema) => setState(() {
          // Volver a tocar el mismo sistema quita el filtro: es el gesto que
          // uno intenta primero y no hace falta buscar un boton de limpiar.
          _filtro = _filtro == sistema ? null : sistema;
          if (_elegido != null &&
              _filtro != null &&
              _elegido!.sistema != _filtro) {
            _elegido = null;
          }
        }),
      ),
    );
  }
}

/// Radios de los marcadores, en pixeles de pantalla.
///
/// Van juntos aqui porque se usan en el pintor y en el toque, y tienen que
/// coincidir: si el area sensible no cubre lo que se ve dibujado, el mecanico
/// toca el punto y no pasa nada.
abstract final class _RadiosMarcador {
  static const normal = 5.0;
  static const elegido = 7.0;

  /// Mas ancho que el dibujo: el dedo tapa el marcador al apuntarlo.
  static const toque = 20.0;
}

/// Dibuja los marcadores de los equipos sobre el plano.
///
/// No dibuja rotulos de area: el plano ya los trae impresos y se leen bien a
/// cualquier zoom. Al superponerles los mios quedaban dos veces el mismo
/// texto, encimado y recortado ("CENTRIFUGA", "SISTEM").
///
/// Recibe la transformacion como [repaint] para volver a pintarse cuando se
/// hace zoom sin que el arbol de widgets se reconstruya.
class _PintorMapa extends CustomPainter {
  _PintorMapa({
    required Listenable repaint,
    required this.transformacion,
    required this.marcadores,
    required this.elegido,
  }) : super(repaint: repaint);

  final TransformationController transformacion;
  final List<MarcadorMapa> marcadores;
  final MarcadorMapa? elegido;

  @override
  void paint(Canvas lienzo, Size size) {
    final escala = transformacion.value.getMaxScaleOnAxis();
    final visible = _rectanguloVisible(size, escala);

    // El elegido se pinta al final para que quede por encima de sus vecinos:
    // donde hay seis centrifugadoras en un metro, el de abajo no se ve.
    final resaltado = elegido;
    for (final m in marcadores) {
      if (m == resaltado) continue;
      _marcador(lienzo, size, escala, m, visible, false);
    }
    if (resaltado != null) {
      _marcador(lienzo, size, escala, resaltado, visible, true);
    }
  }

  /// Que parte del plano se esta viendo, para no pintar lo que queda fuera.
  ///
  /// Con la planta entera a la vista da igual, pero acercado a una turbina
  /// evita medir y componer cincuenta textos que nadie va a ver.
  Rect _rectanguloVisible(Size size, double escala) {
    // MatrixUtils evita tener que importar vector_math solo para esto.
    final origen = MatrixUtils.transformPoint(
      Matrix4.inverted(transformacion.value),
      Offset.zero,
    );
    return Rect.fromLTWH(
      origen.dx,
      origen.dy,
      size.width / escala,
      size.height / escala,
    ).inflate(60 / escala);
  }

  void _marcador(
    Canvas lienzo,
    Size size,
    double escala,
    MarcadorMapa m,
    Rect visible,
    bool esElegido,
  ) {
    final centro = Offset(m.punto.x * size.width, m.punto.y * size.height);
    if (!visible.contains(centro)) return;

    // Los radios se dividen entre el zoom para que en pantalla el marcador
    // mida siempre lo mismo. Un punto que crece al acercarse termina tapando
    // justo el equipo que uno se acerco a mirar.
    final radio =
        (esElegido ? _RadiosMarcador.elegido : _RadiosMarcador.normal) / escala;

    // Halo oscuro: sobre el CAD, que es todo lineas claras y finas, un disco
    // de color sin separacion se confunde con el dibujo.
    lienzo.drawCircle(
      centro,
      radio + 2.2 / escala,
      Paint()..color = const Color(0xCC0B0F16),
    );

    if (m.conOrden) {
      // Anillo de aviso para lo que tiene orden abierta. Va por fuera y no
      // cambiando el color del punto para no perder de que sistema es.
      lienzo.drawCircle(
        centro,
        radio + 3.6 / escala,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 / escala
          ..color = AppColors.warning,
      );
    }

    lienzo.drawCircle(
      centro,
      radio,
      Paint()..color = esElegido ? Colors.white : m.color,
    );
    lienzo.drawCircle(
      centro,
      radio,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (esElegido ? 2.4 : 1.2) / escala
        ..color = esElegido ? m.color : const Color(0xFF0B0F16),
    );

    // El nombre sale al acercarse, y en el elegido siempre. De lejos son
    // cincuenta rotulos encimados que no se leen; el color y la leyenda
    // bastan a esa distancia.
    if (escala >= 2.4 || esElegido) {
      _etiqueta(lienzo, escala, centro, radio, m, esElegido);
    }
  }

  void _etiqueta(
    Canvas lienzo,
    double escala,
    Offset centro,
    double radio,
    MarcadorMapa m,
    bool esElegido,
  ) {
    final pintor = TextPainter(
      text: TextSpan(
        text: m.nombre,
        style: TextStyle(
          fontSize: 8 / escala,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: esElegido ? Colors.white : m.color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final margen = 3 / escala;
    final x = centro.dx + radio + 4 / escala;
    final y = centro.dy - pintor.height / 2;
    final fondo = Rect.fromLTWH(
      x - margen,
      y - margen / 2,
      pintor.width + margen * 2,
      pintor.height + margen,
    );
    // Fondo bajo el texto: sin el, un nombre encima de una linea del CAD es
    // ilegible justo donde mas se necesita.
    lienzo.drawRRect(
      RRect.fromRectAndRadius(fondo, Radius.circular(2.5 / escala)),
      Paint()..color = const Color(0xE60B0F16),
    );
    pintor.paint(lienzo, Offset(x, y));
  }

  @override
  bool shouldRepaint(_PintorMapa anterior) =>
      anterior.marcadores != marcadores || anterior.elegido != elegido;
}

/// La leyenda de sistemas, plegable.
///
/// Es lo que convierte los colores en informacion: sin ella el mapa es un
/// puñado de puntos de colores que no dicen nada. Ademas filtra, que es como
/// se responde "¿donde esta todo lo de la turbina 2?".
class _Leyenda extends StatelessWidget {
  const _Leyenda({
    required this.resumen,
    required this.filtro,
    required this.abierta,
    required this.sinUbicar,
    required this.onAbrirCerrar,
    required this.onElegir,
    required this.altoMaximo,
  });

  final List<MapEntry<String, int>> resumen;
  final String? filtro;
  final bool abierta;
  final int sinUbicar;
  final VoidCallback onAbrirCerrar;
  final ValueChanged<String> onElegir;
  final double altoMaximo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF01B2436),
      borderRadius: BorderRadius.circular(12),
      elevation: 6,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 230, maxHeight: altoMaximo),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onAbrirCerrar,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.layers_outlined,
                      size: 16, color: Color(0xFF9AB0CC)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Sistemas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppText.cuerpoFuerte.copyWith(color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    abierta
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF9AB0CC),
                  ),
                ]),
              ),
            ),
            if (abierta) ...[
              const Divider(height: 1, color: Color(0xFF2A3550)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final entrada in resumen)
                      _FilaLeyenda(
                        nombre: entrada.key,
                        cuenta: entrada.value,
                        color: colorDeSistema(entrada.key),
                        activo: filtro == entrada.key,
                        apagado: filtro != null && filtro != entrada.key,
                        onTap: () => onElegir(entrada.key),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2A3550)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.warning, width: 1.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Orden abierta',
                        style: AppText.micro
                            .copyWith(color: const Color(0xFF9AB0CC))),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaLeyenda extends StatelessWidget {
  const _FilaLeyenda({
    required this.nombre,
    required this.cuenta,
    required this.color,
    required this.activo,
    required this.apagado,
    required this.onTap,
  });

  final String nombre;
  final int cuenta;
  final Color color;
  final bool activo;
  final bool apagado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          color: activo ? const Color(0x2200B89C) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Opacity(
            opacity: apagado ? 0.35 : 1,
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  nombre,
                  style: AppText.micro.copyWith(
                    color: Colors.white,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('$cuenta',
                  style:
                      AppText.micro.copyWith(color: const Color(0xFF7E90AC))),
            ]),
          ),
        ),
      );
}

class _BotonBarra extends StatelessWidget {
  const _BotonBarra({
    required this.icono,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 48,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: IndustrialHeaderStyle.actionStyle,
          icon: Icon(icono, size: 20),
        ),
      );
}

/// La tarjeta con el equipo tocado y el boton para abrirlo.
///
/// Se toca el marcador y aparece esto en vez de abrir el equipo de una: los
/// puntos son chicos a proposito y un dedo en un plano lleno se equivoca. Que
/// diga primero cual es evita entrar al equipo que no era.
class _FichaElegido extends StatelessWidget {
  const _FichaElegido({
    required this.marcador,
    required this.equipo,
    required this.onAbrir,
    required this.onCerrar,
  });

  final MarcadorMapa marcador;

  /// El equipo de la base, para sacar su foto. Null en el black start, que no
  /// es un equipo del inventario, y si la base no cargo.
  final Equipo? equipo;
  final VoidCallback onAbrir;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: const Color(0xF51B2436),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: marcador.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          _Preview(marcador: marcador, equipo: equipo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      marcador.nombre,
                      style: AppText.subtitulo.copyWith(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (marcador.conOrden) ...[
                    const SizedBox(width: 8),
                    const _Chapa('ORDEN ABIERTA', AppColors.warning),
                  ],
                ]),
                if (marcador.tag.isNotEmpty)
                  Text(marcador.tag,
                      style: AppText.dato.copyWith(color: marcador.color)),
                Text(
                  marcador.sistema,
                  style: AppText.apoyo.copyWith(color: const Color(0xFF9AB0CC)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onAbrir, child: const Text('Abrir')),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onCerrar,
            icon: const Icon(Icons.close_rounded,
                size: 20, color: Color(0xFF9AB0CC)),
          ),
        ]),
      ),
    );
  }
}

/// La foto del equipo dentro de la ficha del mapa.
///
/// Es la misma imagen que se ve en la lista de equipos, resuelta igual (por
/// PUNTOS de la base), asi que el mecanico reconoce en el mapa lo que ya vio
/// en el inventario. Se usa la version sin los puntos de medicion marcados:
/// a este tamano las marcas son manchas.
class _Preview extends StatelessWidget {
  const _Preview({required this.marcador, required this.equipo});

  final MarcadorMapa marcador;
  final Equipo? equipo;

  // Apaisada, como las fotos de los equipos: en un cuadro se recortaban los
  // lados justo donde esta la maquina.
  static const _ancho = 104.0;
  static const _alto = 72.0;

  @override
  Widget build(BuildContext context) {
    final equipo = this.equipo;
    final imagen =
        equipo != null ? EquipoVisualResolver.previewFromEquipo(equipo) : null;
    // Se decoda al doble del tamano en pixeles reales. El doble y no el justo
    // porque con recorte `cover` la imagen se escala hasta tapar el hueco, y
    // segun la proporcion de cada foto el lado que manda es el ancho o el
    // alto: pedir exactamente el ancho del cuadro dejaba las apaisadas
    // decodificadas por debajo de lo que se dibuja, y se veian borrosas.
    final pixeles =
        (_ancho * MediaQuery.devicePixelRatioOf(context) * 2).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: _ancho,
        height: _alto,
        color: const Color(0xFF0F1724),
        child: imagen == null
            ? Icon(
                marcador.esBlackStart
                    ? Icons.bolt_rounded
                    : Icons.precision_manufacturing_outlined,
                color: marcador.color,
                size: 30,
              )
            : Image.asset(
                imagen.cleanAsset,
                // El encuadre lo decide la configuracion de cada imagen, no
                // esta pantalla. Dos equipos tienen foto vertical —el jockey
                // y el sprint— y recortarlas a la fuerza en un hueco apaisado
                // deja una franja del medio donde no se ve la maquina.
                fit: imagen.fit,
                cacheWidth: pixeles,
                // Al reducir una foto grande a este tamano, bilineal deja
                // dientes en los bordes de la maquina.
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, __) => Icon(
                  Icons.precision_manufacturing_outlined,
                  color: marcador.color,
                  size: 30,
                ),
              ),
      ),
    );
  }
}

class _Chapa extends StatelessWidget {
  const _Chapa(this.texto, this.color);

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(texto,
            style: AppText.micro
                .copyWith(color: color, fontWeight: FontWeight.w700)),
      );
}

/// Buscador de equipos del mapa.
///
/// Busca por nombre, TAG y sistema porque cada uno llama al equipo por lo que
/// tiene a mano: unos por "BOOSTER", otros por "11-MOT-6241" y otros saben
/// solo que es de la turbina 1.
class _HojaBusqueda extends StatefulWidget {
  const _HojaBusqueda({required this.marcadores});

  final List<MarcadorMapa> marcadores;

  @override
  State<_HojaBusqueda> createState() => _HojaBusquedaState();
}

class _HojaBusquedaState extends State<_HojaBusqueda> {
  final _campo = TextEditingController();
  String _texto = '';

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  List<MarcadorMapa> get _resultado {
    final busca = _texto.trim().toUpperCase();
    if (busca.isEmpty) return widget.marcadores;
    return widget.marcadores.where((m) {
      final heno = [
        m.nombre,
        m.tag,
        m.sistema,
        'LOC-${m.localizacion}',
      ].join(' ').toUpperCase();
      return heno.contains(busca);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _resultado;
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scroll) => Material(
        color: const Color(0xFF1B2436),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A4A66),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _campo,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) => setState(() => _texto = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Nombre, TAG o sistema',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Text('Sin resultados',
                        style: AppText.apoyo
                            .copyWith(color: const Color(0xFF9AB0CC))),
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: lista.length,
                    itemBuilder: (context, i) {
                      final m = lista[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: m.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(m.nombre,
                            style: AppText.cuerpoFuerte
                                .copyWith(color: Colors.white)),
                        subtitle: Text(
                          [m.tag, m.sistema]
                              .where((t) => t.isNotEmpty)
                              .join('  ·  '),
                          style: AppText.apoyo
                              .copyWith(color: const Color(0xFF9AB0CC)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(m),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
