import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import '../services/api_service.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});
  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _urlCtrl = TextEditingController();
  String _username = '';
  String _rol = '';
  bool _saved = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = await ApiService.instance.baseUrl;
    setState(() {
      _urlCtrl.text = url;
      _username = prefs.getString('username') ?? '';
      _rol = prefs.getString('rol') ?? 'mecanico';
    });
  }

  Future<void> _saveUrl() async {
    await ApiService.instance.setBaseUrl(_urlCtrl.text.trim());
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppHeader(title: 'Ajustes', subtitle: 'Configuración del sistema'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // User info card
        _SectionTitle('Sesión activa'),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5)),
          child: Row(children: [
            Container(width: 50, height: 50,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: Center(child: Text(_username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_username, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _rol == 'admin' ? AppColors.warningBg : AppColors.accentLight,
                  borderRadius: BorderRadius.circular(6)),
                child: Text(_rol == 'admin' ? 'Administrador' : 'Mecánico',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _rol == 'admin' ? AppColors.warning : AppColors.accent))),
            ])),
            TextButton(onPressed: _logout,
              child: const Text('Cerrar sesión', style: TextStyle(color: AppColors.error, fontSize: 12))),
          ])),
        const SizedBox(height: 20),

        // API Config
        _SectionTitle('Conexión al servidor'),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('URL del servidor (API)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            TextField(controller: _urlCtrl,
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8000',
                prefixIcon: Icon(Icons.dns_outlined, size: 18, color: AppColors.textSecondary))),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _saveUrl,
              icon: Icon(_saved ? Icons.check_rounded : Icons.save_outlined, size: 16),
              label: Text(_saved ? 'Guardado ✓' : 'Guardar URL'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                backgroundColor: _saved ? AppColors.success : AppColors.primary)),
            const SizedBox(height: 8),
            const Text('Ej: http://192.168.1.100:8000 — IP del servidor en la red de planta',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
        const SizedBox(height: 20),

        // App info
        _SectionTitle('Información'),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5)),
          child: Column(children: [
            _InfoRow('Aplicación', 'SCV-PTBG'),
            _InfoRow('Versión', '1.0.0'),
            _InfoRow('Base de datos', 'MariaDB + SQLite'),
            _InfoRow('Protocolo', 'ISO 10816 / ISO 20816'),
            _InfoRow('Unidad de medición', 'mm/s (velocidad RMS)'),
          ])),
        const SizedBox(height: 20),

        // ISO reference
        _SectionTitle('Referencia ISO 10816'),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5)),
          child: Column(children: [
            _IsoRow('< 2.3 mm/s', 'Bueno', AppColors.success, AppColors.successBg),
            _IsoRow('2.3 – 4.5 mm/s', 'Aceptable', AppColors.accent, AppColors.accentLight),
            _IsoRow('4.5 – 7.1 mm/s', 'Alerta', AppColors.warning, AppColors.warningBg),
            _IsoRow('> 7.1 mm/s', 'Crítico', AppColors.error, AppColors.errorBg),
          ])),
        const SizedBox(height: 40),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.8));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(rango, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textPrimary)),
      const Spacer(),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(estado, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
    ]));
}
