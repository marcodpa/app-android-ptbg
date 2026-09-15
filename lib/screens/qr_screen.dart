import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/mock_data.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../models/qr_code_matcher.dart' as qr_matcher;
import '../models/equipo_visual_config.dart';
import '../services/api_service.dart';
import '../services/equipo_service.dart';
import '../theme.dart';
import '../widgets/industrial_navigation.dart';
import 'checklist_compresor_screen.dart';
import 'operation_selection_screen.dart';
import '../widgets/decode_imagen.dart';

class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  MobileScannerController? _cam;
  final TextEditingController _manualCtrl = TextEditingController();

  bool _camOn = false;
  bool _detected = false;
  bool _loading = false;
  bool _camErr = false;
  bool _showManual = false;
  bool _notFound = false;

  Equipo? _found;
  List<Equipo> _equipos = [];

  @override
  void initState() {
    super.initState();
    _loadEquipos();
  }

  @override
  void dispose() {
    _cam?.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEquipos() async {
    try {
      final list = await EquipoService.instance.cargar();
      if (!mounted) return;

      setState(() {
        _equipos = list.isNotEmpty ? list : mockEquipos;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _equipos = mockEquipos;
      });
    }
  }

  Future<void> _toggleCam() async {
    if (_camOn) {
      try {
        await _cam?.stop();
        await _cam?.dispose();
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _cam = null;
        _camOn = false;
        _camErr = false;
        _detected = false;
        _loading = false;
      });

      return;
    }

    final ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    if (!mounted) return;

    setState(() {
      _cam = ctrl;
      _camOn = true;
      _camErr = false;
      _detected = false;
      _loading = false;
      _notFound = false;
      _found = null;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_detected || _loading) return;
    if (capture.barcodes.isEmpty) return;

    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    if (!mounted) return;

    setState(() {
      _detected = true;
    });

    try {
      await _cam?.stop();
    } catch (_) {}

    await _lookup(rawValue);
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return;

    if (!mounted) return;

    setState(() {
      _loading = true;
      _notFound = false;
      _found = null;
    });

    Equipo? eq;

    try {
      eq = EquipoService.instance.buscarPorQr(code);
    } catch (_) {}

    eq ??= _buscarLocal(code);

    if (eq == null) {
      // Primero intentamos con las variantes numéricas.
      // Ejemplo: si el QR viejo o manual viene como PTBG-004,
      // la app prueba /equipos/4 antes de insistir con /equipos/PTBG-004.
      for (final candidate in _remoteLookupCandidates(code)) {
        try {
          eq = await ApiService.instance.fetchEquipoByQr(candidate);
          if (eq != null) break;
        } catch (_) {}
      }
    }

    if (!mounted) return;

    if (eq != null) {
      eq = await _completeEquipoInfo(eq);
      try {
        await _cam?.stop();
        await _cam?.dispose();
      } catch (_) {}

      setState(() {
        _cam = null;
        _found = eq;
        _loading = false;
        _camOn = false;
        _camErr = false;
        _detected = false;
        _showManual = false;
        _notFound = false;
        _manualCtrl.text = eq?.qrDisplay ?? code;
      });

      return;
    }

    setState(() {
      _loading = false;
      _notFound = true;
      _detected = false;
    });

    if (_camOn && _cam != null) {
      try {
        await _cam?.start();
      } catch (_) {}
    }
  }

  Future<Equipo> _completeEquipoInfo(Equipo eq) async {
    if (eq.info != null && !eq.info!.isEmpty) return eq;

    EquipoInfo? info;
    try {
      info = await DbHelper.instance.getEquipoInfo(eq.localizacion);
    } catch (_) {}

    if (info == null || info.isEmpty) {
      try {
        info = await ApiService.instance.fetchEquipoInfo(eq.localizacion);
        if (info != null && !info.isEmpty) {
          try {
            await DbHelper.instance.upsertEquipoInfo(info);
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (info == null || info.isEmpty) return eq;
    return eq.copyWith(info: info);
  }

  Equipo? _buscarLocal(String code) {
    final inputKeys = _qrKeysLocal(code);
    if (inputKeys.isEmpty) return null;

    final fuentes = _equipos.isNotEmpty ? _equipos : mockEquipos;
    for (final e in fuentes) {
      if (_equipoMatchesQrLocal(e, inputKeys)) return e;
    }
    return null;
  }

  void _iniciarMedicion() {
    final eq = _found;
    if (eq == null) return;
    // Un compresor no se mide: se le llena el check list. Se enruta aqui y no
    // en la pantalla de operaciones porque alli ya seria tarde, el tecnico
    // habria visto una lista de servicios que no le aplican.
    if (EquipoService.instance.esCompresorDeAire(eq)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChecklistCompresorScreen(compresor: eq),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OperationSelectionScreen(equipo: eq),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final equipoEncontrado = _found;

    return IndustrialShell(
      activeRoute: '/qr',
      child: Scaffold(
        backgroundColor: esterThemeController.isDark
            ? AppColors.bg
            : const Color(0xFFF7FAFE),
        body: ListView(
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          children: [
            const IndustrialContentHeader(
              title: 'Escanear QR',
              subtitle: 'Identifique el equipo para iniciar el trabajo',
              icon: Icons.qr_code_scanner_rounded,
            ),
            _buildScannerCard(),
            _buildInstructionRow(),
            if (_notFound) _buildNotFoundBox(),
            if (equipoEncontrado != null) _buildEquipmentCard(equipoEncontrado),
            _buildPrimaryButton(),
            _buildManualButton(),
            if (_showManual) _buildManualInput(),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerCard() {
    final h = MediaQuery.of(context).size.height;
    final cardHeight = h < 760 ? 270.0 : 320.0;
    final controller = _cam;

    return Container(
      height: cardHeight,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      decoration: BoxDecoration(
        color: esterThemeController.isDark
            ? AppColors.surface
            : const Color(0xFFEAF2FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.teal.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_camOn && controller != null && !_camErr)
              MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;

                    setState(() {
                      _camErr = true;
                      _camOn = false;
                      _loading = false;
                    });
                  });

                  return _buildCameraPlaceholder(showTapText: true);
                },
              )
            else
              _buildCameraPlaceholder(showTapText: true),
            if (_camOn && controller != null && !_camErr) ...[
              Container(
                color: Colors.black.withValues(alpha: 0.12),
              ),
              Center(
                child: SizedBox(
                  width: 250,
                  height: 180,
                  child: CustomPaint(
                    painter: _ScanFramePainter(),
                  ),
                ),
              ),
              if (!_loading) const _ScanLine(),
            ],
            if (_loading)
              Container(
                color: Colors.black.withValues(alpha: 0.18),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.teal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder({required bool showTapText}) {
    return GestureDetector(
      onTap: showTapText ? _toggleCam : null,
      child: Container(
        color: esterThemeController.isDark
            ? AppColors.surface2
            : const Color(0xFFEAF2FB),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _InactiveCameraPainter(),
              ),
            ),
            Center(
              child: Container(
                width: 220,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: esterThemeController.isDark
                      ? AppColors.surface
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.borderDark,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        color: AppColors.teal,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Activar cámara',
                      textAlign: TextAlign.center,
                      style: AppText.titulo
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toque aquí para escanear el código QR del equipo',
                      textAlign: TextAlign.center,
                      style: AppText.subtitulo
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (_camErr)
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No se pudo abrir la cámara. Revise los permisos de Android.',
                          style:
                              AppText.apoyo.copyWith(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Color(0xFF7EE2D8),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Alinee el código QR del equipo dentro del recuadro',
              textAlign: TextAlign.center,
              style: AppText.cuerpo.copyWith(
                color: esterThemeController.isDark
                    ? AppColors.textPrimary
                    : const Color(0xFF123A68),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Código no encontrado. Verifique el QR o ingrese el código manualmente.',
                style: AppText.apoyo.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _qrPreviewAsset(Equipo eq) {
    return EquipoVisualResolver.previewFromEquipo(eq).cleanAsset;
  }

  Widget _buildEquipmentCard(Equipo eq) {
    // En el preview del QR se usa SIEMPRE la imagen limpia, sin puntos.
    final imgAsset = _qrPreviewAsset(eq);
    final info = eq.info;
    final serial = _cleanInfoPreview(info?.serial, fallback: 'Sin serial');
    final modelo = _cleanInfoPreview(info?.modelo, fallback: 'Sin modelo');
    final marca = _cleanInfoPreview(info?.marca, fallback: 'Sin marca');
    final dark = esterThemeController.isDark;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppColors.surface : Colors.white,
        border: dark ? null : Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.shadowLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset(
                      imgAsset,
                      width: 82,
                      height: 82,
                      fit: BoxFit.contain,
                      cacheWidth: anchoDecode(context, anchoLogico: 82),
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.precision_manufacturing_outlined,
                        color: AppColors.teal,
                        size: 48,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.teal.withValues(alpha: 0.38),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 19),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  eq.equipo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.seccion.copyWith(
                    color:
                        dark ? AppColors.textPrimary : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                        child: _PreviewInfoBox(
                            label: 'Serial', value: serial, important: true)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _PreviewInfoBox(
                            label: 'Modelo', value: modelo, important: true)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _PreviewInfoBox(
                            label: 'Marca', value: marca, important: true)),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                        child: _PreviewInfoBox(
                            label: 'LC', value: eq.localizacion.toString())),
                    const SizedBox(width: 6),
                    Expanded(
                        child:
                            _PreviewInfoBox(label: 'QR', value: eq.qrDisplay)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _PreviewInfoBox(
                            label: 'Sistema', value: eq.sistema)),
                  ],
                ),
                const SizedBox(height: 8),
                _AxisPreviewCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _cleanInfoPreview(String? value, {String fallback = 'Sin datos'}) {
    if (value == null) return fallback;
    final v = value.trim();
    if (v.isEmpty ||
        v.toUpperCase() == 'NULL' ||
        v.toUpperCase() == 'SIN DATOS') {
      return fallback;
    }
    return v;
  }

  Widget _buildPrimaryButton() {
    final enabled = _found != null;
    final text = enabled
        ? 'Iniciar medición'
        : _camOn
            ? 'Detener cámara'
            : 'Activar cámara QR';
    final icon = enabled
        ? Icons.show_chart_rounded
        : _camOn
            ? Icons.stop_circle_outlined
            : Icons.qr_code_scanner_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: GestureDetector(
        onTap: enabled ? _iniciarMedicion : _toggleCam,
        child: Container(
          height: 58,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient:
                _camOn && !enabled ? AppColors.gradError : AppColors.gradTeal,
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled || !_camOn ? AppColors.shadowTeal : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.65)),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: AppText.seccion.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showManual = !_showManual;
            if (_found != null) _found = null;
            _notFound = false;
          });
        },
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
            boxShadow: AppColors.shadowSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.keyboard_rounded,
                  color: AppColors.textPrimary, size: 22),
              const SizedBox(width: 12),
              Text(
                'Ingresar código manual',
                style:
                    AppText.seccion.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.shadowSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _lookup,
                decoration: const InputDecoration(
                  hintText: 'Ej: PTBG-001',
                  isDense: true,
                  prefixIcon: Icon(Icons.qr_code_2_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              width: 58,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _lookup(_manualCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.search_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _PreviewInfoBox extends StatelessWidget {
  final String label;
  final String value;
  final bool important;

  const _PreviewInfoBox({
    required this.label,
    required this.value,
    this.important = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    final noData = value.trim().isEmpty ||
        value.trim().toUpperCase() == 'NULL' ||
        value.trim().toUpperCase() == 'SIN DATOS';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        // En modo noche el fondo destacado no puede ser el teal claro: el
        // valor va casi blanco y quedaba blanco sobre claro, invisible.
        color: important
            ? (dark
                ? AppColors.teal.withValues(alpha: 0.14)
                : AppColors.tealLight)
            : dark
                ? AppColors.bg2
                : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: important
              ? AppColors.teal.withValues(alpha: 0.28)
              : dark
                  ? AppColors.borderDark
                  : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(
              color: important
                  ? (dark ? AppColors.teal : AppColors.tealDark)
                  : dark
                      ? AppColors.textSecondary
                      : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            noData ? '-' : value.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.etiqueta.copyWith(
              color: noData
                  ? dark
                      ? AppColors.textHint
                      : const Color(0xFF94A3B8)
                  : dark
                      ? AppColors.textPrimary
                      : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisPreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? AppColors.bg2 : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: dark ? AppColors.borderDark : const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.threed_rotation_rounded,
              color: AppColors.teal, size: 17),
          SizedBox(width: 8),
          Expanded(
              child: _AxisPreviewItem(
                  axis: 'X', name: 'Horizontal', color: Colors.black)),
          Expanded(
              child: _AxisPreviewItem(
                  axis: 'Y', name: 'Vertical', color: Color(0xFF9CA3AF))),
          Expanded(
              child: _AxisPreviewItem(
                  axis: 'Z', name: 'Axial', color: Color(0xFFD50000))),
        ],
      ),
    );
  }
}

class _AxisPreviewItem extends StatelessWidget {
  final String axis;
  final String name;
  final Color color;

  const _AxisPreviewItem(
      {required this.axis, required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    final dark = esterThemeController.isDark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$axis $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(
              color: dark ? AppColors.textPrimary : const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 42.0;
    final w = size.width;
    final h = size.height;

    canvas.drawLine(const Offset(0, 0), const Offset(corner, 0), p);
    canvas.drawLine(const Offset(0, 0), const Offset(0, corner), p);

    canvas.drawLine(Offset(w - corner, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), p);

    canvas.drawLine(Offset(0, h - corner), Offset(0, h), p);
    canvas.drawLine(Offset(0, h), Offset(corner, h), p);

    canvas.drawLine(Offset(w, h - corner), Offset(w, h), p);
    canvas.drawLine(Offset(w - corner, h), Offset(w, h), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: -78, end: 78).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Center(
          child: Transform.translate(
            offset: Offset(0, _animation.value),
            child: Container(
              width: 260,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF35FFE5).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF35FFE5).withValues(alpha: 0.70),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InactiveCameraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE5E7EB),
          Color(0xFFD1D5DB),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = 1;

    for (double y = 18; y < size.height; y += 22) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        line,
      );
    }

    for (double x = 18; x < size.width; x += 24) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        line,
      );
    }

    final ring = Paint()
      ..color = AppColors.teal.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;

    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.15),
      92,
      ring,
    );

    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.86),
      74,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Set<String> _qrKeysLocal(String? raw) {
  return qr_matcher.qrKeys(raw);
}

List<String> _remoteLookupCandidates(String raw) {
  return qr_matcher.remoteLookupCandidates(raw);
}

bool _equipoMatchesQrLocal(Equipo e, Set<String> inputKeys) {
  return qr_matcher.equipoMatchesQr(e, inputKeys);
}
