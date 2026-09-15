import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/orden_reparacion.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import 'black_start_screen.dart';
import 'inventario_screen.dart';
import 'ruta_screen.dart';

/// Entrada al modulo de equipos.
///
/// Separa dos cosas que antes estaban mezcladas: los equipos generales
/// (NOX, Booster...) donde se mide, y el inventario de piezas sueltas
/// (motores, bombas, cajas, ventiladores) donde se consulta que hay y donde
/// esta cada una.
class TodosEquiposScreen extends StatefulWidget {
  const TodosEquiposScreen({super.key});

  @override
  State<TodosEquiposScreen> createState() => _TodosEquiposScreenState();
}

class _TodosEquiposScreenState extends State<TodosEquiposScreen> {
  int? _equipos;
  int? _piezas;
  int? _blackStart;

  @override
  void initState() {
    super.initState();
    _contar();
  }

  Future<void> _contar() async {
    try {
      final equipos = await DbHelper.instance.getAllEquipos();
      var piezas = 0;
      for (final tipo in const [1, 2, 3, 4]) {
        piezas += (await DbHelper.instance.getComponentCatalog(tipo)).length;
      }
      final blackStart = await DbHelper.instance.getChecklistsBlackStart();
      await DbHelper.instance.refrescarContadoresOrdenes();
      if (mounted) {
        setState(() {
          _equipos = equipos.length;
          _piezas = piezas;
          _blackStart = blackStart.length;
        });
      }
    } catch (_) {
      // Sin catalogo local todavia: las tarjetas se muestran sin conteo.
    }
  }

  String _etiquetaBlackStart() =>
      _blackStart == 1 ? '1 planilla' : '$_blackStart planillas';

  @override
  Widget build(BuildContext context) {
    return IndustrialShell(
      activeRoute: '/equipos',
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: const IndustrialAppBar(
          titulo: 'Todos los equipos',
          subtitulo: 'Conjuntos de planta e inventario de piezas',
          panel: true,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              Text(
                'Que quieres ver?',
                style: AppText.titulo.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Los conjuntos de la planta o el inventario de piezas.',
                style: AppText.subtitulo.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              _TarjetaModulo(
                imagen: 'assets/images/fondo_equipos_generales.jpg',
                icono: Icons.precision_manufacturing_rounded,
                titulo: 'Equipos generales',
                detalle:
                    'NOX, Booster y demas conjuntos. Aqui se mide, se imprime y '
                    'se consulta el historial.',
                chip: _equipos == null ? null : '$_equipos equipos',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RutaScreen()),
                ),
              ),
              const SizedBox(height: 16),
              // Escucha los dos avisos: las abiertas (hay que ir a cerrarlas) y
              // las que no han subido (no se pueden cerrar todavia).
              AnimatedBuilder(
                animation: Listenable.merge(
                  [ordenesAbiertasNotifier, ordenesSinEnviarNotifier],
                ),
                builder: (context, _) => _TarjetaModulo(
                  alerta: ordenesAbiertasNotifier.value,
                  sinEnviar: ordenesSinEnviarNotifier.value,
                  imagen: 'assets/images/fondo_equipos_especificos.jpg',
                  icono: Icons.inventory_2_rounded,
                  titulo: 'Componentes de equipos',
                  detalle:
                      'Motores, bombas, cajas y ventiladores: donde esta cada '
                      'pieza y en que estado.',
                  chip: _piezas == null ? null : '$_piezas piezas',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InventarioScreen(),
                      ),
                    );
                    _contar();
                  },
                ),
              ),
              const SizedBox(height: 16),
              _TarjetaModulo(
                imagen: 'assets/images/visual_black_start.jpg',
                icono: Icons.bolt_rounded,
                titulo: 'Black start',
                detalle:
                    'Generador de arranque en negro. Se le llena el check list '
                    'SF-OP-FOR-036.',
                chip: _blackStart == null ? null : _etiquetaBlackStart(),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BlackStartScreen(),
                    ),
                  );
                  _contar();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con imagen de portada y degradado, para que el texto se lea encima.
class _TarjetaModulo extends StatelessWidget {
  const _TarjetaModulo({
    required this.imagen,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.chip,
    this.alerta = 0,
    this.sinEnviar = 0,
  });

  final String imagen;
  final IconData icono;
  final String titulo;
  final String detalle;
  final String? chip;

  /// Pendientes que exigen accion, hoy las ordenes de reparacion abiertas. Se
  /// pinta aparte del chip de conteo porque no es un dato mas: es algo que
  /// alguien tiene que ir a cerrar.
  final int alerta;

  /// Ordenes que aun no han subido. Se avisa aparte de [alerta] porque es un
  /// pendiente distinto: no hay que ir al taller, hay que pasar por USB. Y
  /// hasta que eso pase la orden no se puede finalizar.
  final int sinEnviar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 16:9 es la proporcion de las fotos: asi entran completas y no
            // se recorta ni el motor ni la caja ni la bomba.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Las fotos son de 1920x1080 y la tablet mide 800 px de
                  // ancho. Sin cacheWidth, Flutter las descomprime a tamano
                  // completo: 7.9 MB de bitmap por tarjeta, dos tarjetas, y el
                  // tiron se ve al entrar a la pantalla. Se decodifican al
                  // ancho real de la pantalla, que es el techo de lo que la
                  // tarjeta puede llegar a ocupar.
                  Image.asset(
                    imagen,
                    fit: BoxFit.cover,
                    cacheWidth: (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  // La marca de agua ya no esta en el archivo: se recorto. El
                  // degradado de arriba solo asienta la foto bajo la barra de
                  // titulo, y el de abajo la funde con el tema oscuro.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x99111D35),
                          Color(0x00111D35),
                          Color(0x00111D35),
                          Color(0xE6111D35),
                        ],
                        stops: [0.0, 0.18, 0.55, 1.0],
                      ),
                    ),
                  ),
                  if (chip != null)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.headerTop.withValues(alpha: .88),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          chip!,
                          style: AppText.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 12, 15),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: AppColors.teal.withValues(alpha: .40),
                      ),
                    ),
                    child: Icon(icono, color: AppColors.teal, size: 22),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: AppText.seccion.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detalle,
                          style: AppText.apoyo.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (alerta > 0 || sinEnviar > 0) ...[
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              // Lo sin enviar va primero: es lo que bloquea al
                              // tecnico, porque una orden sin subir no se puede
                              // finalizar.
                              if (sinEnviar > 0)
                                _ChipAviso(
                                  icono: Icons.cloud_off_rounded,
                                  color: AppColors.error,
                                  texto: sinEnviar == 1
                                      ? '1 orden sin sincronizar'
                                      : '$sinEnviar ordenes sin sincronizar',
                                ),
                              if (alerta > 0)
                                _ChipAviso(
                                  icono: Icons.assignment_late_rounded,
                                  color: AppColors.warning,
                                  texto: alerta == 1
                                      ? '1 orden abierta'
                                      : '$alerta ordenes abiertas',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso corto sobre la tarjeta. El color separa los dos casos: ambar es
/// trabajo que hay que ir a cerrar, rojo es trabajo que ni siquiera salio de
/// esta tablet.
class _ChipAviso extends StatelessWidget {
  const _ChipAviso({
    required this.icono,
    required this.color,
    required this.texto,
  });

  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              texto,
              style: AppText.micro.copyWith(color: color),
            ),
          ],
        ),
      );
}
