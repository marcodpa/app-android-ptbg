import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../db/db_helper.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  bool _loading = false;
  bool _loadingUsuarios = true;
  String? _error;
  String? _selectedUsuario;
  List<Map<String, String>> _usuarios = [];
  late AnimationController _ac;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
    _loadUsuarios();
  }

  @override
  void dispose() {
    _ac.dispose();
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsuarios() async {
    final merged = <String, Map<String, String>>{
      'ADMIN': {'usuario': 'admin', 'cargo': 'ADMIN'},
    };

    try {
      final locales = await DbHelper.instance.getUsuariosLocales();
      for (final user in locales) {
        final name = (user['usuario'] ?? '').trim();
        if (name.isEmpty) continue;
        merged[name.toUpperCase()] = user;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _usuarios = merged.values.toList()
          ..sort((a, b) => (a['usuario'] ?? '').compareTo(b['usuario'] ?? ''));
        _loadingUsuarios = false;
      });
    }

    try {
      final remotos = await ApiService.instance.fetchUsuarios();
      for (final user in remotos) {
        final name = (user['usuario'] ?? '').trim();
        if (name.isEmpty) continue;
        merged[name.toUpperCase()] = user;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _usuarios = merged.values.toList()
          ..sort((a, b) => (a['usuario'] ?? '').compareTo(b['usuario'] ?? ''));
        _loadingUsuarios = false;
      });
    }
  }

  String _cargoSeleccionado(String usuario) {
    final key = usuario.trim().toUpperCase();
    for (final item in _usuarios) {
      if ((item['usuario'] ?? '').trim().toUpperCase() == key) {
        final cargo = (item['cargo'] ?? '').trim();
        if (cargo.isNotEmpty) return cargo;
      }
    }
    return usuario.toLowerCase() == 'admin' ? 'ADMIN' : 'MECANICO';
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    if (user.isEmpty) {
      setState(() => _error = 'Seleccione usuario');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final cargo = _cargoSeleccionado(user);
    await _go(
      user,
      cargo,
      username: user,
      rol: user.toLowerCase() == 'admin' ? 'admin' : 'mecanico',
    );
  }

  Future<void> _go(
    String responsable,
    String cargo, {
    required String username,
    required String rol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('rol', rol);
    await prefs.setString('responsable', responsable);
    await prefs.setString('cargo', cargo);
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Stack(
      children: [
        // Fondo oscuro top
        Positioned(
          top: 0, left: 0, right: 0, height: h * 0.45,
          child: Container(color: AppColors.primary),
        ),
        // Fondo claro bottom
        Positioned(
          top: h * 0.45, left: 0, right: 0, bottom: 0,
          child: Container(color: AppColors.bg),
        ),
        // Patron tecnico
        Positioned(
          top: 0, left: 0, right: 0, height: h * 0.45,
          child: CustomPaint(painter: _CircuitPainter()),
        ),
        // Franja naranja
        Positioned(
          top: h * 0.44, left: 0, right: 0,
          child: Container(height: 3, color: AppColors.orange),
        ),
        // Contenido principal
        SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              children: [
                _buildLogo(),
                Expanded(child: _buildCard()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      height: 130,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(13),
                boxShadow: AppColors.shadowOrange,
              ),
              child: const Icon(Icons.graphic_eq_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SCV-PTBG',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                Text('Captura de Vibraciones PTBG',
                  style: TextStyle(
                    color: AppColors.orange.withValues(alpha: 0.9),
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.shadowLg,
          border: const Border(
              top: BorderSide(color: AppColors.orange, width: 3)),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Titulo
            Row(
              children: [
                Container(
                  width: 4, height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Acceso al sistema',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 14, top: 2),
              child: Text('Personal autorizado PTBG',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            const _Lbl('USUARIO'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedUsuario,
              isExpanded: true,
              items: _usuarios.map((user) {
                final usuario = user['usuario'] ?? '';
                final cargo = user['cargo'] ?? '';
                return DropdownMenuItem<String>(
                  value: usuario,
                  child: Text(
                    cargo.trim().isEmpty ? usuario : '$usuario - $cargo',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _loadingUsuarios
                  ? null
                  : (value) {
                      setState(() {
                        _selectedUsuario = value;
                        _userCtrl.text = value ?? '';
                      });
                    },
              decoration: InputDecoration(
                hintText: _loadingUsuarios
                    ? 'Cargando usuarios...'
                    : 'Seleccione usuario',
                prefixIcon: const Icon(Icons.badge_outlined,
                    color: AppColors.textSecondary, size: 18),
              ),
            ),

            const SizedBox(height: 24),

            // Boton ingresar
            GestureDetector(
              onTap: _loading ? null : _login,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 54,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: _loading ? null : AppColors.gradPrimary,
                  color: _loading ? AppColors.borderDark : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _loading ? [] : AppColors.shadowPrimary,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    else
                      const Icon(Icons.login_rounded,
                          color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _loading ? 'Verificando...' : 'Ingresar',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o',
                    style: TextStyle(
                        color: AppColors.textHint, fontSize: 12)),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 12),

          ],
        ),
      ),
    );
  }
}

class _Lbl extends StatelessWidget {
  final String t;
  const _Lbl(this.t);
  @override
  Widget build(BuildContext context) => Text(t,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 1.0,
    ));
}

class _CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double y = 40; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (double x = 40; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    final pd = Paint()
      ..color = AppColors.orange.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    for (double y = 40; y < size.height; y += 60) {
      for (double x = 40; x < size.width; x += 60) {
        canvas.drawCircle(Offset(x, y), 2, pd);
      }
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
