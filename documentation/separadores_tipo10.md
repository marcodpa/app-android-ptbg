# Separadores de combustible: tipo 10

## Alcance confirmado

- Equipos 17-06-DO_EM101_S, 17-06-DO_EM101_D y 17-06-DO_EM201 (localizaciones 43, 44 y 45).
- Imagen suministrada por el usuario: `WhatsApp Image 2026-09-08 at 9.14.08 AM.jpeg`, copiada sin editar a `assets/images/visual_separador_motor.jpg`.
- Punto 1: motor lado libre. Punto 2: motor lado acople.
- Vibracion: H1/V1/A1 y H2/V2/A2. Temperatura: T1/T2. Lubricacion: L1/L2.
- Reemplazo: solo motor. Alineacion: campos AMB existentes, con titulo del motor. Coupling habilitado; ajuste de correa no habilitado.
- Limpieza de plato exclusivamente para tipo 10. Fecha/hora del reloj de la tablet al guardar; horometro acumulado entero ingresado por el usuario; marca/modelo/serial del motor. Observaciones opcionales y responsable/cargo de la sesion.

## Guardado y sincronizacion

La tabla SQLite `LIMPIEZAS_PLATO_LOCAL` guarda UUID, localizacion, fecha/hora, horas_funcionamiento, observaciones, responsable/cargo, marca/modelo/serial, ODT y estado/error de sincronizacion. El guardado y la marca `limpieza_plato=1` en la ODT local son atomicos. Seleccionar el servicio sin guardarlo no lo marca como realizado.

El uploader seguro envia a `MOT_SEP_REG` usando las columnas confirmadas en la captura del esquema. Relaciona la localizacion mediante ODT -> `MOT_INDICE.UBICACION`; no inventa una columna LOCALIZACION en MOT_SEP_REG. Actualiza `MOT_INDICE.LIMPIEZA_PLATO`. Comprueba el UUID al reintentar y bloquea la ODT durante la transaccion. Si cambia el numero de ODT por colision, tambien cambia en el detalle local.

Al descargar, reemplaza solo el historial ya sincronizado: refleja correcciones y borrados del servidor sin borrar pendientes. Si la descarga falla o contiene datos invalidos, no vacia el historial local. La sincronizacion implementada es USB/uploader; no se agrega un endpoint HTTP.

La actualizacion de esquema local es aditiva. Una migracion de catalogo de una sola ejecucion reclasifica exclusivamente los tres equipos identificados y previamente tipo 1, sin tocar mediciones. Las siguientes descargas del catalogo siguen siendo autoridad. El catalogo incrustado mantiene su procedencia original; la reclasificacion se aplica despues de sembrarlo.

## Pendiente de entrega del usuario

Formulario oficial exclusivo del tipo 10. La app y el uploader muestran que esta pendiente en vez de rellenar una plantilla de motor-bomba incorrecta. El guardado, historial y sincronizacion no dependen del formulario. No se crea ni altera esquema MariaDB automaticamente.

## Verificacion

Pruebas de resolucion de puntos y componentes, exclusividad del menu, horometro/fecha/ODT, persistencia de pendientes, reintentos, rollback, correcciones/borrados y reasignacion de ODT. Las pruebas de servidor usan una base aislada; la validacion en MariaDB real y en tablet requiere una sincronizacion posterior con el uploader actualizado.
