import 'dart:ui' show Color, Offset, Size;

import 'mapa_planta.dart';

/// Un equipo listo para dibujarse sobre el plano.
///
/// Junta lo que viene de la base (nombre, TAG, sistema, si tiene orden) con la
/// posicion que se coloco a mano en `mapa_planta.py`. La pantalla no vuelve a
/// consultar nada mientras se mueve el mapa.
class MarcadorMapa {
  const MarcadorMapa({
    required this.localizacion,
    required this.punto,
    required this.nombre,
    required this.tag,
    required this.sistema,
    required this.color,
    this.conOrden = false,
  });

  /// La LOCALIZACION del equipo, o [locBlackStart].
  final int localizacion;
  final PuntoMapa punto;
  final String nombre;
  final String tag;
  final String sistema;
  final Color color;

  /// Con una orden de reparacion abierta: se dibuja con anillo de aviso.
  final bool conOrden;

  bool get esBlackStart => localizacion == locBlackStart;
}

/// El black start no tiene LOCALIZACION propia en la planta, asi que ocupa una
/// clave que ninguna localizacion real puede tener.
const locBlackStart = -1;

/// Colores por sistema.
///
/// El color es lo que hace legible el mapa sin acercarse: de lejos no se leen
/// nombres, pero si se ve que todo lo azul es la turbina 1 y todo lo cian es
/// agua desmineralizada. Por eso hay leyenda, y por eso los dos sistemas que
/// se parecen —las dos turbinas— llevan colores bien distintos y no dos tonos
/// del mismo azul.
const coloresSistema = <String, Color>{
  'TURBINA BG-1': Color(0xFF4EA1FF),
  'TURBINA BG-2': Color(0xFFB07CFF),
  'FUEL OIL': Color(0xFFF5A623),
  'DEMINERALIZED WATER': Color(0xFF00C2D1),
  'AGUA POTABLE': Color(0xFF3DDC84),
  'S.C.I': Color(0xFFFF5A5A),
  'CENTRIFUGADORAS': Color(0xFFFF8A3D),
  'AIRE COMPRIMIDO': Color(0xFFA3E635),
  'SKID DE PRUEBA': Color(0xFF9AA5B1),
  'BLACK START': Color(0xFFFFD166),
};

const colorSistemaDesconocido = Color(0xFF9AA5B1);

/// El color de un sistema, tolerante a como venga escrito en la base.
///
/// Se normaliza porque el mismo sistema aparece con y sin puntos ("S.C.I" y
/// "SCI"), con espacios de mas y en distinta caja segun quien lo cargo. Un
/// equipo pintado de gris por una diferencia de puntuacion se lee como
/// "sistema desconocido" y confunde.
Color colorDeSistema(String sistema) {
  final limpio = _normalizar(sistema);
  for (final entrada in coloresSistema.entries) {
    if (_normalizar(entrada.key) == limpio) return entrada.value;
  }
  return colorSistemaDesconocido;
}

String _normalizar(String texto) =>
    texto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// El marcador que hay bajo el dedo, o null si se toco el plano vacio.
///
/// [toque] va en pixeles del plano dibujado, del mismo sistema que [plano].
/// [radio] es la tolerancia, tambien en esos pixeles: la pantalla la calcula
/// dividiendo el radio en pixeles de dedo entre el zoom, para que acercarse
/// haga la punteria mas fina en vez de mas gruesa.
///
/// Devuelve el mas cercano y no el primero que caiga dentro: donde hay seis
/// centrifugadoras en un palmo, varias entran en la tolerancia y el que uno
/// quiere es siempre al que apunto mas de cerca.
MarcadorMapa? marcadorMasCercano(
  List<MarcadorMapa> marcadores,
  Offset toque,
  Size plano,
  double radio,
) {
  MarcadorMapa? elegido;
  var mejor = radio * radio;
  for (final m in marcadores) {
    final dx = m.punto.x * plano.width - toque.dx;
    final dy = m.punto.y * plano.height - toque.dy;
    final distancia = dx * dx + dy * dy;
    if (distancia <= mejor) {
      mejor = distancia;
      elegido = m;
    }
  }
  return elegido;
}

/// Los sistemas presentes, en orden fijo, con cuantos equipos tiene cada uno.
///
/// El orden sale de [coloresSistema] y no del recuento para que la leyenda no
/// se reordene sola: una lista que baila cada vez que se abre el mapa obliga a
/// releerla entera para encontrar el mismo sistema de ayer.
List<MapEntry<String, int>> resumenSistemas(List<MarcadorMapa> marcadores) {
  final cuenta = <String, int>{};
  for (final m in marcadores) {
    cuenta.update(m.sistema, (v) => v + 1, ifAbsent: () => 1);
  }
  final ordenados = <MapEntry<String, int>>[];
  // Se lleva la cuenta de lo ya agregado con las claves y no comparando los
  // MapEntry: MapEntry no implementa ==, asi que `contains` nunca encontraba
  // nada y cada sistema terminaba dos veces en la leyenda.
  final agregados = <String>{};
  for (final nombre in coloresSistema.keys) {
    for (final entrada in cuenta.entries) {
      if (_normalizar(entrada.key) == _normalizar(nombre) &&
          agregados.add(entrada.key)) {
        ordenados.add(entrada);
      }
    }
  }
  // Los que no estan en la tabla de colores van al final, sin perderse.
  for (final entrada in cuenta.entries) {
    if (agregados.add(entrada.key)) ordenados.add(entrada);
  }
  return ordenados;
}
