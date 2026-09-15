import 'package:flutter/material.dart';

import '../theme.dart';

/// Avisos al usuario: snackbars y diálogos de una sola pieza.
///
/// Antes había cuatro helpers `_snack` privados con cuatro estilos distintos
/// y otras cuarenta llamadas crudas, más diecisiete diálogos de confirmación
/// clonados a mano. Todo pasa por aquí para que un aviso se vea igual lo
/// dispare la pantalla que lo dispare.
///
/// Ninguna función asume que el `context` siga montado: quien llama desde un
/// `await` debe comprobar `mounted` antes, igual que siempre.

/// Mensaje corto flotante. [color] marca la intención: éxito, aviso o error.
///
/// [duracion] solo se pasa cuando el aviso tiene que quedarse más de lo
/// normal: los que explican algo que el técnico debe alcanzar a leer antes
/// de seguir, como "revise la laptop" durante una impresión.
void avisar(
  BuildContext context,
  String mensaje,
  Color color, {
  Duration? duracion,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje, style: AppText.cuerpoFuerte),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: duracion ?? const Duration(seconds: 4),
    ),
  );
}

/// El texto de un error sin el ruido de `Exception:` delante.
///
/// `error.toString().replaceFirst('Exception: ', '')` estaba copiado seis
/// veces por la app; el prefijo es un detalle de Dart que al técnico no le
/// dice nada.
String mensajeDeError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

/// Confirmación binaria. Devuelve true solo si el usuario confirma.
///
/// [destructivo] pinta el botón de confirmar en rojo: borrar y descartar se
/// ven igual en toda la app, no con cuatro estilos según la pantalla.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoConfirmar = 'ACEPTAR',
  String textoCancelar = 'CANCELAR',
  bool destructivo = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(textoCancelar),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: destructivo
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Aviso con un solo botón. Para errores y estados sin decisión que tomar.
Future<void> avisarDialogo(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoBoton = 'ENTENDIDO',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(textoBoton),
        ),
      ],
    ),
  );
}

/// Confirmación de guardado exitoso, con su check verde.
///
/// Cinco pantallas de captura tenían cada una su versión —dos con icono,
/// tres sin— para decir exactamente lo mismo: "quedó guardado en la tablet".
Future<void> avisarGuardado(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoBoton = 'CERRAR',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success),
        const SizedBox(width: 8),
        Expanded(child: Text(titulo)),
      ]),
      content: Text(mensaje),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(textoBoton),
        ),
      ],
    ),
  );
}
