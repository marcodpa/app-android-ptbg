# Catalogo inicial del APK

Para preparar un APK con los equipos actuales de MariaDB, usar
`build_apk.bat` (release) o `build_usb_apk.ps1` (debug USB).

Ambos ejecutan primero `actualizar_catalogo_apk.py`. Este consulta todo
`MOT_EQUIPO` y sus sistemas en una transaccion de solo lectura. No tiene limite
de 51 ni de 56 equipos. Genera `lib/data/mock_data.dart` con cantidad, fecha UTC
y huella del contenido. Solo aumenta la version si cambian los equipos.

Si no hay una clave configurada localmente, aparece la misma ventana de acceso
del uploader seguro. La clave permanece en memoria y no entra en el APK.
En un entorno sin ventanas se puede ejecutar
`py -3 actualizar_catalogo_apk.py --sin-dialogo` con las variables `SCV_DB_*`
ya configuradas. No incluir claves en comandos, archivos versionados ni el APK.

Si MariaDB no esta disponible, se cancela el acceso o el catalogo es invalido,
el proceso falla y los scripts no compilan. El APK que hubiera de una
compilacion anterior no es un APK actualizado: comprobar siempre el resultado.
Una compilacion directa con `flutter build apk` no ejecuta esta preparacion;
usar los scripts anteriores para distribuir instalaciones actualizadas.

La primera apertura de una tablet vacia siembra el catalogo incluido en el APK.
Una tablet que ya tiene datos los conserva: instalar encima no borra equipos,
fichas ni trabajos pendientes. Para traer altas posteriores a esa tablet, usar
la descarga del uploader seguro por USB. Un archivo APK ya generado no puede
cambiar por si solo cuando cambia MariaDB; hay que sincronizar la tablet o
preparar un nuevo APK.
