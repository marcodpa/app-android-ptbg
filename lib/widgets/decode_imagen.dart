import 'package:flutter/widgets.dart';

/// Ancho en pixeles fisicos al que conviene descomprimir una imagen.
///
/// Flutter descomprime un asset a su tamano original salvo que se le pase
/// `cacheWidth`. Los JPG de esta app llegan a 1920 px de ancho y la tablet de
/// planta mide 800: cada foto ocupaba hasta 7.9 MB de bitmap para dibujarse en
/// una fraccion de eso. Se paga dos veces, en RAM y en el tiempo de subir la
/// textura a la GPU, y se nota como tiron al abrir la pantalla.
///
/// [anchoLogico] es el ancho al que se va a dibujar, si se conoce. Si no se
/// pasa, se usa el ancho de la pantalla, que es el techo de lo que cualquier
/// imagen puede llegar a ocupar.
///
/// Nunca devuelve mas que el ancho de la pantalla: pedir mas resolucion de la
/// que el panel puede mostrar no se ve, solo cuesta.
int anchoDecode(BuildContext context, {double? anchoLogico}) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final anchoPantalla = MediaQuery.sizeOf(context).width * dpr;
  if (anchoLogico == null || anchoLogico <= 0) return anchoPantalla.round();
  final pedido = anchoLogico * dpr;
  return (pedido < anchoPantalla ? pedido : anchoPantalla).round();
}
