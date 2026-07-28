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
import 'operation_selection_screen.dart';

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

    return Scaffold(
      backgroundColor: AppColors.headerTop,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildHeader(),
                _buildScannerCard(),
                _buildInstructionRow(),
                if (_notFound) _buildNotFoundBox(),
                if (equipoEncontrado != null)
                  _buildEquipmentCard(equipoEncontrado),
                _buildPrimaryButton(),
                _buildManualButton(),
                if (_showManual) _buildManualInput(),
                const SizedBox(height: 18),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 172,
      decoration: const BoxDecoration(gradient: AppColors.gradPrimary),
      child: Stack(
        children: [
          Positioned.fill(
              child: CustomPaint(painter: _IndustrialHeaderPainter())),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escanear QR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Capture el código QR del equipo',
                          style: TextStyle(
                            color: Color(0xFF7EE2D8),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        color: const Color(0xFFE5E7EB),
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
        color: const Color(0xFFE5E7EB),
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
                  color: Colors.white.withValues(alpha: 0.94),
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
                    const Text(
                      'Activar cámara',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Toque aquí para escanear el código QR del equipo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
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
                  child: const Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No se pudo abrir la cámara. Revise los permisos de Android.',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
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
        child: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Código no encontrado. Verifique el QR o ingrese el código manualmente.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
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

  String _areaDisplay(Equipo eq) {
    final s = eq.sistema.toUpperCase();
    if (s.contains('BG-1')) return 'Turbina BG1';
    if (s.contains('BG-2')) return 'Turbina BG2';
    if (s.contains('FUEL')) return 'Área Combustible';
    if (s.contains('DESMINERALIZED')) return 'Planta DEMI';
    if (s.contains('CENTRIFUGADORAS')) return 'Centrifugadoras';
    if (s.contains('AGUA POTABLE')) return 'Agua Potable';
    return eq.sistema;
  }

  String _sistemaDisplay(Equipo eq) {
    final s = eq.sistema.toUpperCase();
    if (s.contains('FUEL')) return 'Combustible';
    if (s.contains('DESMINERALIZED')) return 'Agua desmineralizada';
    if (s.contains('TURBINA')) return 'Turbina';
    if (s.contains('S.C.I')) return 'Sistema contra incendio';
    return eq.sistema;
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
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
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_rounded,
                  color: AppColors.textPrimary, size: 22),
              SizedBox(width: 12),
              Text(
                'Ingresar código manual',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
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

  Widget _buildBottomNav() {
    return Container(
      height: 60 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: const Color(0xFF06213A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                  (_) => false,
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home_rounded,
                        color: Color(0xFF7EE2D8), size: 22),
                    SizedBox(height: 2),
                    Text(
                      'Inicio',
                      style: TextStyle(color: Color(0xFF7EE2D8), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 46,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/ajustes'),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.settings_rounded,
                      color: Colors.white.withValues(alpha: 0.72),
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ajustes',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
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
    final noData = value.trim().isEmpty ||
        value.trim().toUpperCase() == 'NULL' ||
        value.trim().toUpperCase() == 'SIN DATOS';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: important ? AppColors.tealLight : AppColors.bg2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: important
              ? AppColors.teal.withValues(alpha: 0.28)
              : AppColors.borderDark,
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
            style: TextStyle(
              color: important ? AppColors.teal : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            noData ? '-' : value.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: noData ? AppColors.textHint : AppColors.textPrimary,
              fontSize: important ? 12 : 11,
              fontWeight: FontWeight.w900,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          const Icon(Icons.threed_rotation_rounded,
              color: AppColors.teal, size: 17),
          const SizedBox(width: 8),
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
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tealLight.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 44, top: 7, bottom: 7),
      child: Divider(height: 1, color: AppColors.border),
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

class _IndustrialHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    for (double y = 14; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final plant = Paint()
      ..color = const Color(0xFF67D8FF).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final baseY = size.height * 0.72;
    for (double x = size.width * 0.58; x < size.width; x += 42) {
      canvas.drawRect(Rect.fromLTWH(x, baseY - 50, 10, 50), plant);
      canvas.drawRect(Rect.fromLTWH(x - 8, baseY - 54, 26, 6), plant);
      canvas.drawCircle(Offset(x + 5, baseY - 58), 13, plant);
    }

    final pipe = Paint()
      ..color = const Color(0xFF67D8FF).withValues(alpha: 0.10)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.52, baseY),
      Offset(size.width, baseY),
      pipe,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, baseY + 18),
      Offset(size.width, baseY + 18),
      pipe,
    );

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.teal.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.92, 0),
        radius: 120,
      ));
    canvas.drawCircle(Offset(size.width * 0.92, 0), 120, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _IndustrialCameraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (double y = 18; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bgLine);
    }

    final pipe = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-20, size.height * 0.43),
      Offset(size.width * 0.45, size.height * 0.43),
      pipe,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, size.height * 0.70),
      Offset(size.width + 20, size.height * 0.70),
      pipe,
    );

    final soft = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          AppColors.teal.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, soft);
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
