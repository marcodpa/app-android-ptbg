import 'package:flutter/foundation.dart';

/// Ordenes abiertas en este momento.
///
/// Es un valor compartido para que el globo de la barra, la tarjeta del menu y
/// el acceso del inventario muestren siempre lo mismo. Antes cada pantalla lo
/// contaba por su cuenta al montarse, asi que al crear una orden el numero no
/// cambiaba hasta navegar o sincronizar.
final ordenesAbiertasNotifier = ValueNotifier<int>(0);

/// Ordenes creadas o cerradas aqui que aun no han subido.
///
/// Va aparte de [ordenesAbiertasNotifier] porque son dos avisos distintos: una
/// orden abierta es trabajo que alguien tiene que ir a cerrar, y una sin enviar
/// es trabajo que ni siquiera existe todavia para el resto de la planta y que
/// no se puede finalizar hasta sincronizar.
final ordenesSinEnviarNotifier = ValueNotifier<int>(0);

/// Destinos a donde puede irse un componente a reparar.
const destinosReparacion = <String>[
  'TALLER ELECTRICO',
  'TALLER MECANICO',
  'TALLER EXTERNO',
  'ALMACEN PRINCIPAL',
  'ALMACEN DE MOTORES',
];

/// Como termina una orden.
///
/// El resultado decide en que estatus queda la pieza, por eso son estos tres y
/// no texto libre: el estatus deja de escribirse a mano y pasa a ser una
/// consecuencia de lo que se hizo.
const resultadosReparacion = <String, String>{
  'REPARADO': 'DISPONIBLE',
  'NO REPARABLE': 'DESECHADO',
  'SIN INTERVENCION': 'AVERIADO',
};

/// Estatus que lleva la pieza mientras la orden esta abierta.
const estadoEnReparacion = 'EN REPARACION';

/// Una orden de reparacion: el componente sale a un taller y vuelve.
///
/// Una orden es siempre de UNA pieza. Dos motores llevados el mismo dia
/// vuelven en fechas distintas y con trabajos distintos, asi que agruparlos
/// obligaria a cerrar media orden.
class OrdenReparacion {
  const OrdenReparacion({
    required this.uuid,
    required this.tipo,
    required this.serial,
    required this.destino,
    required this.fechaSalida,
    required this.horaSalida,
    this.marca = '',
    this.modelo = '',
    this.ubicacionOrigen,
    this.motivo,
    this.usuarioSalida,
    this.cargoSalida,
    this.odt,
    this.estadoOrden = 'ABIERTA',
    this.fechaRetorno,
    this.horaRetorno,
    this.usuarioCierre,
    this.cargoCierre,
    this.trabajoRealizado,
    this.resultado,
    this.ubicacionFinal,
    this.observaciones,
    this.sincronizado = false,
    this.errorSync,
  });

  final String uuid;

  /// 1 Motor, 2 Bomba, 3 Caja, 4 Ventilador.
  final int tipo;
  final String serial;
  final String marca;
  final String modelo;

  /// Localizacion del equipo de donde salio la pieza.
  final int? ubicacionOrigen;

  final String destino;
  final String? motivo;
  final String fechaSalida;
  final String horaSalida;
  final String? usuarioSalida;
  final String? cargoSalida;
  final int? odt;

  /// ABIERTA mientras la pieza esta afuera, CERRADA cuando volvio.
  final String estadoOrden;

  final String? fechaRetorno;
  final String? horaRetorno;
  final String? usuarioCierre;
  final String? cargoCierre;
  final String? trabajoRealizado;
  final String? resultado;
  final String? ubicacionFinal;
  final String? observaciones;
  final bool sincronizado;
  final String? errorSync;

  bool get abierta => estadoOrden.trim().toUpperCase() != 'CERRADA';

  /// Una orden que todavia no subio no existe para el resto de la planta.
  ///
  /// Finalizarla antes de enviarla dejaria que apertura y cierre viajen juntos
  /// en el mismo paquete: el servidor recibiria una orden que nacio cerrada y
  /// las demas tablets nunca verian la pieza en reparacion. La orden tiene que
  /// dar la vuelta completa —crear, sincronizar, volver— antes de cerrarse.
  bool get puedeFinalizarse => abierta && sincronizado;

  /// Solo se descarta lo que nunca salio de esta tablet.
  ///
  /// Una vez enviada la orden ya no es nuestra para borrarla: el registro vive
  /// en el servidor y lo unico que corresponde es cerrarla.
  bool get puedeDescartarse => abierta && !sincronizado;

  /// Estatus que le corresponde a la pieza segun el momento de la orden.
  String get estadoPieza {
    if (abierta) return estadoEnReparacion;
    return resultadosReparacion[(resultado ?? '').trim().toUpperCase()] ??
        'DISPONIBLE';
  }

  String get titulo {
    final partes = [marca, modelo].where((v) => v.trim().isNotEmpty);
    return partes.isEmpty ? serial : partes.join(' · ');
  }

  String get nombreTipo {
    switch (tipo) {
      case 1:
        return 'Motor';
      case 2:
        return 'Bomba';
      case 3:
        return 'Caja';
      case 4:
        return 'Ventilador';
      default:
        return 'Componente';
    }
  }

  /// Dias que lleva fuera, o que estuvo fuera si ya cerro.
  int? get diasFuera {
    final salida = DateTime.tryParse(fechaSalida);
    if (salida == null) return null;
    final fin = abierta
        ? DateTime.now()
        : (DateTime.tryParse(fechaRetorno ?? '') ?? DateTime.now());
    return fin.difference(salida).inDays;
  }

  OrdenReparacion cerrar({
    required String fecha,
    required String hora,
    required String resultado,
    String? trabajoRealizado,
    String? ubicacionFinal,
    String? observaciones,
    String? usuario,
    String? cargo,
  }) =>
      OrdenReparacion(
        uuid: uuid,
        tipo: tipo,
        serial: serial,
        marca: marca,
        modelo: modelo,
        ubicacionOrigen: ubicacionOrigen,
        destino: destino,
        motivo: motivo,
        fechaSalida: fechaSalida,
        horaSalida: horaSalida,
        usuarioSalida: usuarioSalida,
        cargoSalida: cargoSalida,
        odt: odt,
        estadoOrden: 'CERRADA',
        fechaRetorno: fecha,
        horaRetorno: hora,
        usuarioCierre: usuario,
        cargoCierre: cargo,
        trabajoRealizado: trabajoRealizado,
        resultado: resultado,
        ubicacionFinal: ubicacionFinal,
        observaciones: observaciones,
        sincronizado: false,
      );

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoONulo(Object? value) {
    final texto = _texto(value);
    return texto.isEmpty ? null : texto;
  }

  static int? _entero(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  factory OrdenReparacion.fromMap(Map<String, dynamic> map) => OrdenReparacion(
        uuid: _texto(map['uuid']),
        tipo: _entero(map['tipo']) ?? 0,
        serial: _texto(map['serial']),
        marca: _texto(map['marca']),
        modelo: _texto(map['modelo']),
        ubicacionOrigen: _entero(map['ubicacion_origen']),
        destino: _texto(map['destino']),
        motivo: _textoONulo(map['motivo']),
        fechaSalida: _texto(map['fecha_salida']),
        horaSalida: _texto(map['hora_salida']),
        usuarioSalida: _textoONulo(map['usuario_salida']),
        cargoSalida: _textoONulo(map['cargo_salida']),
        odt: _entero(map['odt']),
        estadoOrden: _texto(map['estado_orden']).isEmpty
            ? 'ABIERTA'
            : _texto(map['estado_orden']),
        fechaRetorno: _textoONulo(map['fecha_retorno']),
        horaRetorno: _textoONulo(map['hora_retorno']),
        usuarioCierre: _textoONulo(map['usuario_cierre']),
        cargoCierre: _textoONulo(map['cargo_cierre']),
        trabajoRealizado: _textoONulo(map['trabajo_realizado']),
        resultado: _textoONulo(map['resultado']),
        ubicacionFinal: _textoONulo(map['ubicacion_final']),
        observaciones: _textoONulo(map['observaciones']),
        sincronizado: (_entero(map['sincronizado']) ?? 0) == 1,
        errorSync: _textoONulo(map['error_sync']),
      );

  Map<String, dynamic> toDbMap() => {
        'uuid': uuid,
        'tipo': tipo,
        'serial': serial,
        'marca': marca,
        'modelo': modelo,
        'ubicacion_origen': ubicacionOrigen,
        'destino': destino,
        'motivo': motivo,
        'fecha_salida': fechaSalida,
        'hora_salida': horaSalida,
        'usuario_salida': usuarioSalida,
        'cargo_salida': cargoSalida,
        'odt': odt,
        'estado_orden': estadoOrden,
        'fecha_retorno': fechaRetorno,
        'hora_retorno': horaRetorno,
        'usuario_cierre': usuarioCierre,
        'cargo_cierre': cargoCierre,
        'trabajo_realizado': trabajoRealizado,
        'resultado': resultado,
        'ubicacion_final': ubicacionFinal,
        'observaciones': observaciones,
        'sincronizado': sincronizado ? 1 : 0,
        'error_sync': errorSync,
      };
}
