# Prueba de tablet de origen — STER 1.1.1+3

## Qué cambia

Las nuevas ODT guardan `tablet_origen` en la tablet y el uploader lo envía a
`MOT_INDICE.TABLET_ORIGEN` (VARCHAR 100, admite NULL). Incluye las órdenes
de equipos y las órdenes sueltas de black start. El origen se captura al crear
la ODT, no al subirla. Los registros previos no se rellenan retrospectivamente.

El identificador tiene el formato `modelo / identificador Android`, por ejemplo
`TAB_R7 / 1234567890abcdef` (ejemplo, no identificación real de la tablet).
El identificador Android corresponde a dispositivo, usuario Android y firma de
la app; no es el serial del cable USB. Actualizaciones con la misma firma y el
mismo usuario conservan esa identidad. Un restablecimiento del dispositivo o
cambio de usuario/firma puede cambiarla. No se obtiene de la base copiada.

## Prueba de campo

1. Cerrar y abrir **el uploader seguro** para cargar el código actualizado.
   Ingresar la contraseña únicamente en su ventana local, no en el chat.
2. Usar la app 1.1.1+3. Crear una **ODT nueva**, registrar un servicio real o una
   prueba autorizada y claramente identificada, y anotar el número de ODT.
   No reutilizar las ODT anteriores esperando que aparezca un origen nuevo.
3. Conectar la tablet y subir los pendientes. Comprobar ausencia de errores.
   El registro del uploader indica número de ODT y tablet de origen.
4. Buscar esa ODT en `MOT_INDICE`: `TABLET_ORIGEN` debe contener el modelo y su
   identificador. Los servicios de esa orden deben tener la misma ODT.
5. Reintentar la sincronización: no debe aparecer otra ODT ni cambiar el origen.
6. Con una segunda tablet actualizada, crear un trabajo distinto y sincronizar:
   debe tener otro identificador, aunque el modelo sea igual.

Consulta de comprobación (solo lectura):

```sql
SELECT ID, ODT, FECHA, HORA, EQUIPO, TABLET_ORIGEN,
       VIBRACION, TEMPERATURA, LUBRICACION, LIMPIEZA_PLATO
FROM MOT_INDICE
ORDER BY ID DESC
LIMIT 20;
```

## Protecciones y límites

- Si Android no proporciona identidad válida, no se crea una ODT sin origen.
- Una ODT antigua mantiene NULL; no se le atribuye la tablet que la transporta.
- Dos orígenes conocidos distintos no se consideran la misma ODT por coincidir
  equipo, fecha y hora. Al reasignar se actualizan las referencias locales de
  servicios, incluidos correa, limpieza de plato y checklists.
- Una coincidencia entre un origen conocido y otro desconocido se retiene para
  revisión, sin sobrescribir el origen ni adivinar que son el mismo trabajo.
- Si falla una ODT, la subida de servicios se retiene hasta resolverla y reintentar.
  Pueden quedar servicios pendientes de otras ODT del mismo lote; no se eliminan.
- El uploader toma el origen del registro, nunca del argumento del dispositivo USB.
- No es una solución completa de concurrencia entre varias estaciones de subida.
  La prueba automatizada de dos tablets usa dos bases locales aisladas y subidas
  secuenciales; no sustituye una prueba simultánea real con la base de planta.
- No se modifican formularios ni se añaden columnas de origen en cada servicio:
  se mantiene la regla acordada de una tablet capturadora por ODT.

## Verificado localmente el 10/09/2026

- 275 pruebas Flutter aprobadas y análisis sin errores.
- 118 pruebas Python aprobadas, incluidas 9 nuevas de origen, migración, colisión,
  reintento, confirmación interrumpida y retención por columna remota ausente.
- Las pruebas Python usan SQLite temporal y un adaptador de servidor simulado;
  no insertan registros de prueba en MariaDB de planta.
- La lectura directa del esquema real no se completó: la sesión no tenía la
  contraseña del uploader seguro. La estructura se tomó de la captura del usuario.
  La prueba de campo queda pendiente de realizar mediante ese uploader.
