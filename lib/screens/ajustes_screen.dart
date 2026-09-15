import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/db_helper.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});
  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  String _username = '';
  String _rol = '';
  List<Map<String, Object?>> _eventos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? '';
      _rol = prefs.getString('rol') ?? 'mecanico';
    });
    // La bitacora solo se le muestra al administrador; para el resto ni se
    // consulta.
    if (_rol == 'admin') {
      try {
        final eventos = await DbHelper.instance.getEventosAdmin();
        if (mounted) setState(() => _eventos = eventos);
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Solo lo de la sesion. Un prefs.clear() se llevaba tambien la marca del
    // catalogo y la direccion del servidor, y al volver a entrar la app creia
    // que era una tablet nueva.
    for (final clave in const [
      'username',
      'rol',
      'responsable',
      'cargo',
      'token',
    ]) {
      await prefs.remove(clave);
    }
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return IndustrialShell(
      activeRoute: '/ajustes',
      child: Scaffold(
        backgroundColor: esterThemeController.isDark
            ? AppColors.bg
            : const Color(0xFFF7FAFE),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const IndustrialContentHeader(
            title: 'Ajustes',
            subtitle: 'Configuración del sistema',
            icon: Icons.settings_outlined,
          ),
          // User info card
          const _SectionTitle('Sesión activa'),
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: Row(children: [
                Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: Center(
                        child: Text(
                            _username.isNotEmpty
                                ? _username[0].toUpperCase()
                                : 'U',
                            style: AppText.display
                                .copyWith(color: Colors.white)))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_username,
                          style: AppText.seccion
                              .copyWith(color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: _rol == 'admin'
                                  ? AppColors.warningBg
                                  : AppColors.accentLight,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(
                              _rol == 'admin' ? 'Administrador' : 'Mecánico',
                              style: AppText.etiqueta.copyWith(
                                  color: _rol == 'admin'
                                      ? AppColors.warning
                                      : AppColors.accent))),
                    ])),
                TextButton(
                    onPressed: _logout,
                    child: Text('Cerrar sesión',
                        style:
                            AppText.cuerpo.copyWith(color: AppColors.error))),
              ])),
          const SizedBox(height: 20),

          // USB Config
          const _SectionTitle('Sincronización USB'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.usb_rounded, color: AppColors.accent, size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'La descarga y la subida de datos funcionan únicamente mediante la laptop conectada por USB.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bitacora del administrador: correcciones y retro-fechados, con
          // quien, cuando y que cambio. Solo el admin la ve.
          if (_rol == 'admin') ...[
            const _SectionTitle('Registro del administrador'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: _eventos.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Sin eventos: ninguna medición ha sido corregida ni '
                        'retro-fechada.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : Column(
                      children: [
                        for (final evento in _eventos)
                          _EventoAdminRow(evento: evento),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
          ],

          // App info
          const _SectionTitle('Información'),
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: const Column(children: [
                _InfoRow('Aplicación', 'STER'),
                _InfoRow('Versión', '1.0.0'),
                _InfoRow('Base de datos', 'MariaDB + SQLite'),
                _InfoRow('Protocolo', 'ISO 10816 / ISO 20816'),
                _InfoRow('Unidad de medición', 'mm/s (velocidad RMS)'),
              ])),
          const SizedBox(height: 20),

          // ISO reference
          const _SectionTitle('Referencia ISO 10816'),
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: const Column(children: [
                _IsoRow('< 2.3 mm/s', 'Bueno', AppColors.success,
                    AppColors.successBg),
                _IsoRow('2.3 – 4.5 mm/s', 'Aceptable', AppColors.accent,
                    AppColors.accentLight),
                _IsoRow('4.5 – 7.1 mm/s', 'Alerta', AppColors.warning,
                    AppColors.warningBg),
                _IsoRow('> 7.1 mm/s', 'Crítico', AppColors.error,
                    AppColors.errorBg),
              ])),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

class _EventoAdminRow extends StatelessWidget {
  final Map<String, Object?> evento;
  const _EventoAdminRow({required this.evento});

  @override
  Widget build(BuildContext context) {
    String texto(String clave) => (evento[clave] ?? '').toString().trim();
    final accion = texto('accion');
    final servicio = texto('servicio');
    final loc = texto('localizacion');
    final detalle = texto('detalle');
    final esFecha = accion == 'FECHA MANUAL';
    final color = esFecha ? AppColors.warning : AppColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                esFecha ? Icons.history_rounded : Icons.edit_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$accion · $servicio${loc.isEmpty ? '' : ' LOC-$loc'}',
                  style: AppText.cuerpoFuerte
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              Text(
                '${texto('fecha')} ${texto('hora')}',
                style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 23, top: 2),
            child: Text(
              detalle.isEmpty ? texto('usuario') : '${texto('usuario')} · $detalle',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.apoyo.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: AppText.etiqueta
          .copyWith(color: AppColors.textSecondary, letterSpacing: 0.8));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(label,
            style: AppText.cuerpo.copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        Text(value,
            style:
                AppText.cuerpoFuerte.copyWith(color: AppColors.textPrimary)),
      ]));
}

class _IsoRow extends StatelessWidget {
  final String rango, estado;
  final Color color, bg;
  const _IsoRow(this.rango, this.estado, this.color, this.bg);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(rango,
            style: AppText.mono.copyWith(color: AppColors.textPrimary)),
        const Spacer(),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(6)),
            child: Text(estado, style: AppText.etiqueta.copyWith(color: color))),
      ]));
}
