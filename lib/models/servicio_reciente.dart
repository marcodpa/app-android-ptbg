import 'package:flutter/material.dart';

import '../theme.dart';

/// Los tipos de trabajo que se hacen sobre un equipo y suben a la planta.
///
/// El color no distingue un servicio de otro: la paleta de la app tiene un
/// solo acento —`AppColors.orange` es un alias de `teal` desde que se quito
/// el naranja— y quien identifica el servicio es el icono. La excepcion es el
/// reemplazo, en cian, porque es el unico que cambia el equipo en vez de solo
/// medirlo.
///
/// El [codigo] es el que devuelve la consulta de recientes; va escrito a mano
/// y no derivado del nombre de la tabla para que renombrar una tabla no
/// cambie en silencio lo que se muestra en pantalla.
enum TipoServicio {
  limpiezaPlato('limpieza_plato', 'Limpieza de plato',
      Icons.cleaning_services_rounded, AppColors.teal),
  vibracion('vibracion', 'Vibración', Icons.vibration_rounded, AppColors.teal),
  temperatura(
      'temperatura', 'Temperatura', Icons.thermostat_rounded, AppColors.teal),
  lubricacion(
      'lubricacion', 'Lubricación', Icons.oil_barrel_rounded, AppColors.teal),
  alineacion(
      'alineacion', 'Alineación', Icons.straighten_rounded, AppColors.teal),
  reemplazo(
      'reemplazo', 'Reemplazo', Icons.build_circle_outlined, AppColors.cyan),
  coupling('coupling', 'Cambio de coupling',
      Icons.settings_input_component_rounded, AppColors.teal),
  checklistCompresor('checklist_compresor', 'Check list compresor',
      Icons.fact_check_rounded, AppColors.teal),
  blackStart('black_start', 'Check list black start', Icons.bolt_rounded,
      AppColors.teal);

  const TipoServicio(this.codigo, this.nombre, this.icono, this.color);

  final String codigo;
  final String nombre;
  final IconData icono;
  final Color color;

  static TipoServicio? porCodigo(String? codigo) {
    for (final tipo in TipoServicio.values) {
      if (tipo.codigo == codigo) return tipo;
    }
    return null;
  }
}

/// Un trabajo que ya subio a la planta.
///
/// Sirve para lo contrario que la lista de pendientes: esa dice lo que falta,
/// esta confirma lo que llego. Sin ella el tecnico sincroniza y no vuelve a
/// ver rastro de su trabajo hasta que alguien abre el historial.
class ServicioReciente {
  const ServicioReciente({
    required this.tipo,
    required this.localizacion,
    required this.fecha,
    required this.hora,
  });

  final TipoServicio tipo;

  /// Null en el black start, que no cuelga de ningun equipo del inventario.
  final int? localizacion;

  final String fecha;
  final String hora;

  static ServicioReciente? deFila(Map<String, Object?> fila) {
    final tipo = TipoServicio.porCodigo(fila['servicio']?.toString());
    if (tipo == null) return null;
    final loc = fila['localizacion'];
    return ServicioReciente(
      tipo: tipo,
      localizacion: loc is int ? loc : int.tryParse('${loc ?? ''}'),
      fecha: (fila['fecha'] ?? '').toString(),
      hora: (fila['hora'] ?? '').toString(),
    );
  }

  /// La fecha como se lee en Venezuela, y la hora sin los segundos.
  ///
  /// En la base se guarda ISO para que ordene bien como texto, pero nadie
  /// lee "2026-08-25" de un vistazo, y los segundos de cuando se guardo un
  /// trabajo no le importan a nadie.
  String get cuando {
    final partes = fecha.split('-');
    final dia =
        partes.length == 3 ? '${partes[2]}/${partes[1]}/${partes[0]}' : fecha;
    final reloj = hora.length >= 5 ? hora.substring(0, 5) : hora;
    return reloj.isEmpty ? dia : '$dia · $reloj';
  }
}
