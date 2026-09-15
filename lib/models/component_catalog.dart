/// Una pieza fisica del inventario: motor, bomba, caja o ventilador.
///
/// El SERIAL identifica la pieza. Dos registros con el mismo serial son la
/// misma pieza, aunque la marca o el modelo esten escritos distinto.
///
/// La fuente de verdad es la tabla maestra de MariaDB (`MOT_*_DATA`), donde
/// vive toda unidad de la planta este instalada, averiada en taller o
/// disponible en almacen. `MOT_LOG_RPL` no participa: es una bitacora
/// inmutable de permutas, no un registro de existencias.
class ComponentCatalogItem {
  const ComponentCatalogItem({
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.serial,
    required this.instalado,
    this.estado,
    this.sitio,
    this.activo,
    this.codeConjunto,
    this.localizacion,
    this.equipo,
    this.ultimaFecha,
  });

  /// 1 Motor, 2 Bomba, 3 Caja, 4 Ventilador.
  final int tipo;
  final String marca;
  final String modelo;
  final String serial;

  /// true cuando la pieza esta puesta en un equipo en este momento.
  final bool instalado;

  /// Condicion de la pieza: INSTALADO, DISPONIBLE, AVERIADO, DESECHADO.
  final String? estado;

  /// Donde esta fisicamente cuando no esta instalada: taller o almacen.
  final String? sitio;

  /// 1 operativo / 0 no operativo.
  final int? activo;
  final int? codeConjunto;

  /// Equipo del que viene la pieza: su UBICACION en la maestra.
  ///
  /// OJO: no se limpia cuando la pieza sale a un taller o a un almacen. Es a
  /// proposito y de ello depende el filtro de compatibilidad: una pieza guardada
  /// solo puede volver a un equipo de la familia de donde salio, y si aqui
  /// llegara null se ofreceria para cualquier equipo de la planta.
  ///
  /// Donde esta fisicamente la pieza es [sitio], no esto.
  final int? localizacion;
  final String? equipo;
  final String? ultimaFecha;

  String get titulo {
    final partes = [marca, modelo].where((v) => v.trim().isNotEmpty);
    return partes.isEmpty ? serial : partes.join(' · ');
  }

  /// Estado normalizado, con un valor util aunque la columna venga vacia.
  String get estadoTexto {
    final valor = (estado ?? '').trim().toUpperCase();
    if (valor.isNotEmpty) return valor;
    return instalado ? 'INSTALADO' : 'DISPONIBLE';
  }

  /// Donde esta, en una linea, para mostrar en la lista.
  String get ubicacionTexto {
    if (instalado) {
      final nombre = (equipo ?? '').trim();
      if (nombre.isNotEmpty) return 'En $nombre';
      return localizacion == null ? 'Instalada' : 'En LOC-$localizacion';
    }
    final lugar = (sitio ?? '').trim();
    return lugar.isEmpty ? 'Sin ubicacion registrada' : lugar;
  }

  /// Texto de busqueda: se compara todo junto para no tener que adivinar si el
  /// tecnico escribio la marca, el modelo o el serial.
  String get busqueda =>
      '$marca $modelo $serial ${equipo ?? ''} ${sitio ?? ''}'.toUpperCase();

  static String _text(Object? value) => (value ?? '').toString().trim();

  static String? _textOrNull(Object? value) {
    final texto = _text(value);
    return texto.isEmpty ? null : texto;
  }

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  factory ComponentCatalogItem.fromJson(int tipo, Map<String, dynamic> json) {
    return ComponentCatalogItem(
      tipo: tipo,
      marca: _text(json['marca']),
      modelo: _text(json['modelo']),
      serial: _text(json['serial']),
      // ACTIVO manda: es la fila vigente de esa posicion. Las historicas
      // quedan con ACTIVO = 0 y no estan instaladas.
      instalado: json['instalado'] == true || json['instalado'] == 1,
      estado: _textOrNull(json['estado']),
      sitio: _textOrNull(json['localizacion_fisica']) ??
          _textOrNull(json['sitio']),
      activo: _intOrNull(json['activo']),
      codeConjunto: _intOrNull(json['code_conjunto']),
      localizacion: _intOrNull(json['ubicacion']),
      equipo: _textOrNull(json['equipo']),
      ultimaFecha: _textOrNull(json['fecha']) ??
          _textOrNull(json['ultima_fecha']),
    );
  }

  factory ComponentCatalogItem.fromLocalMap(Map<String, dynamic> row) {
    return ComponentCatalogItem(
      tipo: _intOrNull(row['tipo']) ?? 0,
      marca: _text(row['marca']),
      modelo: _text(row['modelo']),
      serial: _text(row['serial']),
      instalado: _intOrNull(row['instalado']) == 1,
      estado: _textOrNull(row['estado']),
      sitio: _textOrNull(row['sitio']),
      activo: _intOrNull(row['activo']),
      codeConjunto: _intOrNull(row['code_conjunto']),
      localizacion: _intOrNull(row['localizacion']),
      equipo: _textOrNull(row['equipo']),
      ultimaFecha: _textOrNull(row['ultima_fecha']),
    );
  }

  Map<String, dynamic> toLocalMap() => {
        'tipo': tipo,
        'serial': serial,
        'marca': marca,
        'modelo': modelo,
        'instalado': instalado ? 1 : 0,
        'estado': estado,
        'sitio': sitio,
        'activo': activo,
        'code_conjunto': codeConjunto,
        'localizacion': localizacion,
        'equipo': equipo,
        'ultima_fecha': ultimaFecha,
      };
}
