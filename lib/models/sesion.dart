import 'package:shared_preferences/shared_preferences.dart';

/// Quien esta usando la tablet y que puede hacer.
///
/// Hay dos roles. El mecanico captura mediciones y las sube: nada mas. El
/// administrador ademas puede corregir mediciones pendientes y retro-fechar
/// una medicion hecha sin la tablet a mano; cada una de esas acciones queda
/// en la bitacora EVENTOS_ADMIN con la hora real del reloj, para que las
/// correcciones tengan nombre y no haya forma de maquillar datos en silencio.
class Sesion {
  Sesion._();

  /// Respaldo por nombre. La via normal es MDB_USERS.ROL = 'ADMIN', que la
  /// planta administra sola; esta lista solo cubre el caso de que ese rol
  /// llegue vacio (tablet sin descargar todavia, por ejemplo).
  static const administradores = {'ADMIN', 'DANIEL BERRUETA'};

  static bool esUsuarioAdmin(String? usuario, String? cargo, {String? rol}) {
    // MDB_USERS.ROL es lo que la planta administra: ahi dice ADMIN o USUARIO
    // y es la via para nombrar a otro administrador sin tocar la app.
    if ((rol ?? '').trim().toUpperCase().contains('ADMIN')) return true;
    final nombre = (usuario ?? '').trim().toUpperCase();
    if (administradores.contains(nombre)) return true;
    // Ultima red: algunos cargos traen ADMINISTRADOR escrito dentro.
    return (cargo ?? '').trim().toUpperCase().contains('ADMIN');
  }

  /// El rol guardado al iniciar sesion.
  static Future<bool> esAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('rol') == 'admin';
    } catch (_) {
      return false;
    }
  }

  static Future<String> usuarioActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString('responsable') ??
              prefs.getString('username') ??
              '')
          .trim();
    } catch (_) {
      return '';
    }
  }

  static Future<String> cargoActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString('cargo') ?? prefs.getString('rol') ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}

/// Que cambio entre dos versiones de una medicion, en una linea legible:
/// "T1: 61.0 → 63.0 · obs: RUIDO → SIN NOVEDAD". Es lo que se guarda como
/// detalle del evento de edicion; si no cambio nada devuelve vacio y el
/// evento ni se registra.
String resumenCambios(Map<String, Object?> antes, Map<String, Object?> despues) {
  String plano(Object? v) {
    final texto = (v ?? '').toString().trim();
    return texto.isEmpty || texto.toLowerCase() == 'null' ? '—' : texto;
  }

  final partes = <String>[];
  for (final clave in despues.keys) {
    final a = plano(antes[clave]);
    final d = plano(despues[clave]);
    if (a != d) partes.add('$clave: $a → $d');
  }
  return partes.join(' · ');
}
