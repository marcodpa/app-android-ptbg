# Prueba del módulo de filtros

Esta entrega contiene un APK debug ARM64 y el uploader seguro actualizado.
No es una validación completa de producción. No incluye contraseñas ni copias
de datos de las tablets. Instalar como actualización; no desinstalar ni borrar datos.

## Catálogo inicial

La primera apertura carga el catálogo validado del 21/09/2026:
7 sistemas, 31 subsistemas y 46 registros de filtros. Para filtros están habilitados
1 BG1 (18), 2 BG2 (18), 3 Combustible diésel (4) y 4 Agua (6).
Los registros pueden representar varios elementos; el reemplazo es completo.
No contiene mantenimientos ficticios. El catálogo de motores no se refrescó
desde el servidor al compilar esta entrega.

El catálogo incluido se usa solo si nunca se inicializó el módulo y no hay
catálogo, historial ni solicitudes administrativas previas. Una descarga por USB
manda sobre el APK, incluso si está vacía o elimina filtros. Actualizar el APK
no restaura filtros borrados ni sobrescribe los datos pendientes.

## Uploader

1. Extraer `uploader_seguro.zip` en una carpeta nueva en la laptop.
2. Cerrar cualquier uploader anterior. Abrir `abrir_subidor_usb.bat` e introducir
   las credenciales exclusivamente en la ventana local del uploader seguro.
3. Actualizar TODOS los uploaders antes de registrar cambios desde varias tablets:
   comparten el bloqueo para la numeración ODT de motores y filtros.
4. Mantener Python y ADB instalados. La conexión a la BD sale de la laptop.
   No copiar contraseñas al APK ni enviar credenciales por chat.

Para revisar primero la BD sin escribir, ejecutar `VERIFICAR_FILTROS_BD.bat`.
El resultado se guarda en `output/validacion_filtros_bd.json`. No modifica la BD
ni comprueba permisos de escritura mediante inserciones: inspecciona los permisos.

## Prueba controlada pendiente

- Respaldar las tablets y comprobar que el historial y los pendientes anteriores
  permanezcan después de instalar con actualización.
- Descargar el catálogo real mediante el uploader actualizado.
- Comprobar sistemas → subsistemas → filtros en orientación vertical.
- Elegir con el responsable un reemplazo real o una BD aislada para la prueba.
  No registrar trabajos ficticios en producción.
- Confirmar cantidad completa, fecha/hora automática, responsable, UUID,
  TABLET_ORIGEN y ODT compartida en FLT_CHANGE.
- Repetir el envío: debe conservar un único registro. Descargar en una segunda
  tablet y verificar que aparece el mismo cambio.
- Simular cortes/reintentos exclusivamente en un entorno de prueba. Comprobar que
  no desaparezcan pendientes ni se dupliquen ODT.

FLT_CHANGE todavía no guarda la cantidad histórica ni el elemento retirado.
No se han alterado columnas, índices ni restricciones de producción.
