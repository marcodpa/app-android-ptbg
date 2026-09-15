import 'coercion.dart';
import 'historial_servicio.dart';

/// Check list de mantenimiento a compresores de aire (formato SF-OP-FOR-040).
///
/// Los compresores no se miden como el resto de la planta: no llevan vibracion,
/// temperatura, alineacion, lubricacion, cambio de coupling, ajuste de correas
/// ni reemplazo de piezas. Su mantenimiento es una inspeccion visual guiada por
/// este formulario, y por eso tienen su propia tabla y su propia pantalla en
/// vez de reutilizar el flujo de medicion.
class ChecklistCompresor {
  const ChecklistCompresor({
    required this.uuid,
    required this.localizacion,
    required this.equipo,
    required this.subsistema,
    required this.tag,
    required this.fecha,
    required this.hora,
    required this.horaInicio,
    required this.horaFin,
    required this.numeroHoras,
    required this.numeroArranques,
    required this.actividades,
    required this.observaciones,
    required this.mantenimientos,
    this.usuario,
    this.cargo,
    this.odt,
    this.sincronizado = false,
    this.errorSync,
  });

  final String uuid;
  final int localizacion;
  final String equipo;
  final String subsistema;
  final String tag;

  final String fecha;
  final String hora;
  final String horaInicio;
  final String horaFin;

  /// Horometro y contador de arranques que marca la unidad.
  final int numeroHoras;
  final int numeroArranques;

  /// Respuesta de cada una de las 11 inspecciones: true = SI, false = NO.
  ///
  /// Se guarda como lista y no como campos sueltos porque el formulario las
  /// numera y las recorre en orden; en la base se reparten en ACT1..ACT11.
  final List<bool> actividades;
  final List<String> observaciones;

  /// Las cuatro filas de "Control de mantenimiento", en el orden del formato.
  /// Al guardar, las no realizadas quedan vacias. Las copias de presentacion
  /// completan esas filas con referencias al historial, sin volver a guardarlas.
  final List<MantenimientoCompresor> mantenimientos;

  final String? usuario;
  final String? cargo;
  final int? odt;
  final bool sincronizado;
  final String? errorSync;

  /// Las 11 inspecciones, con el texto tal cual sale en el formato impreso.
  ///
  /// Se copian literales a proposito: el tecnico compara la tablet contra el
  /// papel que ya conoce, y cualquier reescritura "mejorada" le haria dudar de
  /// si esta respondiendo la misma pregunta.
  static const preguntas = <String>[
    '¿Se encuentra el nivel de aceite en el rango optimo (visor de nivel)?',
    '¿Está el compresor libre de fugas de aceite en el modulo y carter?',
    '¿Está el compresor libre de fugas de aire en tuberias, conexiones '
        'internas y accesorios?',
    '¿Está el compresor libre de fugas de aire en su sistema externo '
        '(tuberias y accesorios)?',
    '¿Se inspeccionaron mangueras, tubos flexibles y arneses en busca de '
        'desgaste o roces?',
    '¿Se verificó e inspeccionó el estado operativo visual de las válvulas '
        'de seguridad?',
    '¿Se inspeccionó el paquete de enfriadores (coolers) y estan sus aletas '
        'limpias?',
    '¿Se encuentra el filtro de aire en buen estado (revisado con la unidad '
        'detenida)?',
    '¿Se encuentra la unidad libre de acumulación de polvo en su estructura '
        'interna?',
    '¿Están las superficies exteriores y accesorios libres de corrosión o '
        'impactos?',
    '¿Se encuentra el area limpia y adecuada para su funcionamiento?',
  ];

  /// Las cuatro tareas del control de mantenimiento, con su periodo.
  static const tareasMantenimiento = <String>[
    'LUBRICACIÓN (2000 HORAS)',
    'INSPECCIÓN Y/O CAMBIO DE INHIBIDORES DE SONIDO (4k horas o 6 meses)',
    'CAMBIO DE FILTRO DE AIRE (6 meses)',
    'CAMBIO DE ACEITE Y FILTRO (8k horas o 1 año)',
  ];

  /// Prefijo de la columna de cada tarea en MOT_COMP_CHKL.
  static const _clavesMantenimiento = <String>['lub', 'inh', 'air', 'ace'];

  /// Cuantas inspecciones salieron mal. Es lo que decide si el equipo queda
  /// conforme: una sola respuesta en NO ya obliga a mirar la observacion.
  int get hallazgos => actividades.where((r) => !r).length;

  bool get conforme => hallazgos == 0;

  static String _texto(Object? v) => textoDe(v);
  static String? _textoONulo(Object? v) => textoONuloDe(v);
  static int _entero(Object? v) => enteroDe(v);

  factory ChecklistCompresor.fromMap(Map<String, dynamic> m) {
    return ChecklistCompresor(
      uuid: _texto(m['uuid']),
      localizacion: _entero(m['localizacion']),
      equipo: _texto(m['equipo']),
      subsistema: _texto(m['subsistema']),
      tag: _texto(m['tag']),
      fecha: _texto(m['fecha']),
      hora: _texto(m['hora']),
      horaInicio: _texto(m['h_inicio']),
      horaFin: _texto(m['h_fin']),
      numeroHoras: _entero(m['n_horas']),
      numeroArranques: _entero(m['n_arranques']),
      actividades: [
        for (var i = 1; i <= preguntas.length; i++) _entero(m['act$i']) == 1,
      ],
      observaciones: [
        for (var i = 1; i <= preguntas.length; i++) _texto(m['act${i}_obs']),
      ],
      mantenimientos: [
        for (final clave in _clavesMantenimiento)
          MantenimientoCompresor(
            ultimaFecha: _texto(m['mtto_${clave}_uf']),
            horas: _texto(m['mtto_${clave}_uh']),
            observacion: _texto(m['mtto_${clave}_obs']),
          ),
      ],
      usuario: _textoONulo(m['usuario']),
      cargo: _textoONulo(m['cargo']),
      odt: m['odt'] == null ? null : _entero(m['odt']),
      sincronizado: _entero(m['sincronizado']) == 1,
      errorSync: _textoONulo(m['error_sync']),
    );
  }

  Map<String, dynamic> toDbMap() {
    final mapa = <String, dynamic>{
      'uuid': uuid,
      'localizacion': localizacion,
      'equipo': equipo,
      'subsistema': subsistema,
      'tag': tag,
      'fecha': fecha,
      'hora': hora,
      'h_inicio': horaInicio,
      'h_fin': horaFin,
      'n_horas': numeroHoras,
      'n_arranques': numeroArranques,
      'usuario': usuario,
      'cargo': cargo,
      'odt': odt,
      'sincronizado': sincronizado ? 1 : 0,
      'error_sync': errorSync,
    };
    for (var i = 0; i < preguntas.length; i++) {
      mapa['act${i + 1}'] = actividades[i] ? 1 : 0;
      mapa['act${i + 1}_obs'] = observaciones[i];
    }
    for (var i = 0; i < _clavesMantenimiento.length; i++) {
      final clave = _clavesMantenimiento[i];
      mapa['mtto_${clave}_uf'] = mantenimientos[i].ultimaFecha;
      mapa['mtto_${clave}_uh'] = mantenimientos[i].horas;
      mapa['mtto_${clave}_obs'] = mantenimientos[i].observacion;
    }
    return mapa;
  }
}

/// Una fila del control de mantenimiento: cuando se hizo por ultima vez.
class MantenimientoCompresor {
  const MantenimientoCompresor({
    this.ultimaFecha = '',
    this.horas = '',
    this.observacion = '',
  });

  final String ultimaFecha;

  /// Horometro que marcaba la unidad en esa fecha. Va como texto porque en el
  /// papel a veces se anota un rango o un "no registra".
  final String horas;
  final String observacion;

  bool get tieneRegistro =>
      ultimaFecha.trim().isNotEmpty || horas.trim().isNotEmpty;
}

/// Solo las tareas realizadas se registran como datos nuevos. Las otras se
/// consultan del historial al mostrar o imprimir, nunca se vuelven a subir.
List<MantenimientoCompresor> mantenimientosRealizados(
  List<bool> hechos,
  List<MantenimientoCompresor> datos,
) =>
    [
      for (var i = 0; i < datos.length; i++)
        hechos[i] ? datos[i] : const MantenimientoCompresor(),
    ];

/// Copias para PRESENTACION, del mas reciente al mas antiguo. No modifica las
/// planillas originales ni escribe los datos heredados en la base. Cada tarea
/// se resuelve como una fila completa, sin mezclar fechas/horas de trabajos
/// diferentes. Una planilla antigua nunca hereda datos de una futura.
List<ChecklistCompresor> historialCompresorConReferencias(
  Iterable<ChecklistCompresor> historial,
) {
  final ordenado = historial.toList()
    ..sort((a, b) {
      final fecha =
          claveHistorial(a.toDbMap()).compareTo(claveHistorial(b.toDbMap()));
      return fecha != 0 ? fecha : a.uuid.compareTo(b.uuid);
    });
  final anteriores = <int, List<MantenimientoCompresor>>{};
  final resultado = <ChecklistCompresor>[];
  for (final checklist in ordenado) {
    final previos = anteriores[checklist.localizacion];
    final mapa = checklist.toDbMap();
    final resueltos = <MantenimientoCompresor>[];
    for (var i = 0; i < checklist.mantenimientos.length; i++) {
      final actual = checklist.mantenimientos[i];
      final dato = actual.tieneRegistro ? actual : (previos?[i] ?? actual);
      resueltos.add(dato);
      final clave = ChecklistCompresor._clavesMantenimiento[i];
      mapa['mtto_${clave}_uf'] = dato.ultimaFecha;
      mapa['mtto_${clave}_uh'] = dato.horas;
      mapa['mtto_${clave}_obs'] = dato.observacion;
    }
    anteriores[checklist.localizacion] = resueltos;
    resultado.add(ChecklistCompresor.fromMap(mapa));
  }
  return resultado.reversed.toList();
}
