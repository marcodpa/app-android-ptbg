/// Que piezas sirven para que equipo, segun la ubicacion donde estan.
///
/// No todos los motores valen para todo: un motor de un FIN FAN no sirve en una
/// bomba de patin. Los equipos generales se agrupan en familias y una pieza
/// solo puede montarse dentro de la familia de donde salio.
///
/// Sirve para que al reemplazar no le aparezcan al mecanico las piezas
/// disponibles de toda la planta, sino unicamente las que le sirven.
class CompatibilidadEquipos {
  const CompatibilidadEquipos._();

  /// Familias por ubicacion. El orden es el de la clasificacion oficial.
  static const familias = <_Familia>[
    _Familia(1, 'Booster', [1, 8]),
    _Familia(2, 'NOX liquido y gas', [2, 3, 9, 10]),
    _Familia(3, 'Ventiladores de turbina', [4, 5, 11, 12]),
    _Familia(4, 'Ventiladores de generador', [6, 7, 13, 14]),
    _Familia(5, 'Fin Fan', [15, 16, 17, 18]),
    _Familia(6, 'Arrancador hidraulico', [19, 21]),
    _Familia(7, 'Sprint', [20, 22]),
    _Familia(8, 'Patines 10, 11 y 12', [
      23, 24, 25, 26, 27, 28, 29, 30,
      34, 35, 36, 37, 38, 39,
      48, 49, 50, 51,
    ]),
    _Familia(9, 'Bombas de transferencia de centrifugadoras', [40, 41, 42]),
    _Familia(10, 'Motores de centrifugadoras', [43, 44, 45]),
  ];

  /// Ubicaciones sin familia: son equipos unicos y no comparten piezas con
  /// nadie. Hoy el sistema contra incendio (31, 32 y 33).
  ///
  /// Se resuelven con una familia propia por ubicacion, asi una pieza de la 31
  /// solo puede volver a la 31.
  static _Familia? _buscar(int ubicacion) {
    final asignada = _asignadas[ubicacion];
    if (asignada != null) {
      for (final familia in familias) {
        if (familia.id == asignada) return familia;
      }
    }
    for (final familia in familias) {
      if (familia.ubicaciones.contains(ubicacion)) return familia;
    }
    return null;
  }

  /// Familias elegidas al registrar un equipo nuevo en campo.
  ///
  /// La lista de arriba solo cubre las 51 ubicaciones originales. Un equipo
  /// registrado despues no cae en ninguna, y sin esto no se le podria montar
  /// ninguna pieza existente. La familia se pregunta al crearlo porque no se
  /// deduce del sistema ni del subsistema: VENT TURB y VENT GEN comparten los
  /// dos y son familias distintas.
  static Map<int, int> _asignadas = const {};

  /// Carga las familias de los equipos registrados en campo.
  ///
  /// Se llama al abrir la app y despues de sincronizar. Es un mapa completo,
  /// no un anadido: asi una familia corregida en la planta reemplaza a la que
  /// tenia la tablet en vez de acumularse.
  static void cargarAsignadas(Map<int, int> porUbicacion) {
    _asignadas = Map.unmodifiable(porUbicacion);
  }

  /// Identificador de familia de una ubicacion.
  ///
  /// Las que no estan clasificadas devuelven un id negativo derivado de su
  /// propia ubicacion: nunca coincide con otra, que es justo lo que se quiere
  /// para un equipo unico.
  static int familiaDe(int ubicacion) {
    final familia = _buscar(ubicacion);
    return familia?.id ?? -ubicacion;
  }

  /// Familias que se pueden elegir al registrar un equipo, id -> nombre.
  static Map<int, String> get opciones => {
        for (final familia in familias) familia.id: familia.nombre,
      };

  static String nombreFamilia(int ubicacion) {
    final familia = _buscar(ubicacion);
    if (familia != null) return familia.nombre;
    return 'Equipo unico (LOC-$ubicacion)';
  }

  /// true si una pieza que estuvo en [origen] puede montarse en [destino].
  ///
  /// Una pieza sin origen conocido no se bloquea: no hay dato para decidir, y
  /// esconderla dejaria al mecanico sin repuestos por falta de informacion en
  /// vez de por incompatibilidad real.
  static bool compatible({required int? origen, required int destino}) {
    if (origen == null || origen <= 0) return true;
    return familiaDe(origen) == familiaDe(destino);
  }
}

class _Familia {
  const _Familia(this.id, this.nombre, this.ubicaciones);
  final int id;
  final String nombre;
  final List<int> ubicaciones;
}
