import 'package:flutter/foundation.dart';

/// Trabajos guardados en esta tablet que todavia no han subido al servidor.
///
/// Es un valor compartido para que el punto rojo de la barra y la pantalla de
/// sincronizar cuenten lo mismo. Cubre las ocho tablas locales que llevan
/// `sincronizado`: mediciones de vibracion, temperaturas, lubricaciones,
/// alineaciones, reemplazos, cambios de coupling, cambios de estatus y ordenes
/// de reparacion.
///
/// El punto se pinta sin numero a proposito: no importa si son 2 o 30, importa
/// que hay trabajo sin respaldar. Si la tablet se pierde o se resetea, eso es
/// lo que se pierde.
final pendientesSyncNotifier = ValueNotifier<int>(0);
