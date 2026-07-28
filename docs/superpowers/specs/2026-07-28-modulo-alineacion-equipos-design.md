# Módulo de alineación de equipos

## Objetivo

Agregar Alineación como cuarta operación de la aplicación. El operador podrá
capturar los valores aplicables al equipo, guardarlos localmente y subirlos a
`MOT_ALN_REG` exclusivamente mediante el programa USB de la laptop.

El módulo debe seguir el patrón local-first de Vibración, Temperatura y
Reemplazo. Guardar una alineación nunca debe intentar conectarse con una API ni
con MariaDB.

## Equipos aplicables

La disponibilidad se determina únicamente con `MOT_EQUIPO.PUNTOS`:

| PUNTOS | Tipo de alineación | Columnas |
|---|---|---|
| 1, 2 o 9 | MOTOR–BOMBA | `AMB_ANGULO_V`, `AMB_ANGULO_H`, `AMB_COMPENSACION_V`, `AMB_COMPENSACION_H` |
| 6 | MOTOR–CAJA y CAJA–BOMBA | `ACM_ANGULO_V`, `ACM_ANGULO_H`, `ACM_COMPENSACION_V`, `ACM_COMPENSACION_H`, `ACB_ANGULO_V`, `ACB_ANGULO_H`, `ACB_COMPENSACION_V`, `ACB_COMPENSACION_H` |

La opción Alineación se oculta para cualquier otro valor de `PUNTOS`. No se
debe usar `PT_EQ` para decidir la disponibilidad ni el formulario.

## Selector y secuencia de operaciones

`OperationType` incorpora `alignment`. Después de escanear un equipo elegible,
la pantalla de operaciones presenta:

- Vibración.
- Medición de temperatura.
- Alineación.
- Reemplazo de equipo.

El operador puede seleccionar una o varias operaciones y decidir cuál comienza.
Al terminar una operación, la secuencia ofrece continuar con la siguiente sin
volver a escanear el equipo.

Para equipos no elegibles, Alineación no aparece y las otras operaciones
mantienen su comportamiento actual.

## Formulario

La captura se presenta en una sola pantalla desplazable, sin imagen del equipo
y sin comparación con registros anteriores.

### MOTOR–BOMBA

Una tarjeta titulada **ALINEACIÓN MOTOR–BOMBA** contiene:

1. Ángulo vertical, `AMB_ANGULO_V`, unidad `mm/100 mm`.
2. Ángulo horizontal, `AMB_ANGULO_H`, unidad `mm/100 mm`.
3. Compensación vertical, `AMB_COMPENSACION_V`, unidad `mm`.
4. Compensación horizontal, `AMB_COMPENSACION_H`, unidad `mm`.

### MOTOR–CAJA–BOMBA

La pantalla contiene dos tarjetas.

**ALINEACIÓN MOTOR–CAJA**

1. Ángulo vertical, `ACM_ANGULO_V`, unidad `mm/100 mm`.
2. Ángulo horizontal, `ACM_ANGULO_H`, unidad `mm/100 mm`.
3. Compensación vertical, `ACM_COMPENSACION_V`, unidad `mm`.
4. Compensación horizontal, `ACM_COMPENSACION_H`, unidad `mm`.

**ALINEACIÓN CAJA–BOMBA**

1. Ángulo vertical, `ACB_ANGULO_V`, unidad `mm/100 mm`.
2. Ángulo horizontal, `ACB_ANGULO_H`, unidad `mm/100 mm`.
3. Compensación vertical, `ACB_COMPENSACION_V`, unidad `mm`.
4. Compensación horizontal, `ACB_COMPENSACION_H`, unidad `mm`.

### Validación

- Todos los campos aplicables son obligatorios.
- Si una lectura no existe, el operador debe escribir `0`.
- Se aceptan valores negativos, positivos y cero.
- La coma es el único separador decimal admitido.
- Se admiten cero, uno o dos decimales.
- No se aplica un límite mínimo ni máximo.
- El formato válido sigue `^-?\d+(,\d{1,2})?$`.
- El punto decimal se rechaza con un mensaje claro.
- Antes de guardar, la aplicación convierte la coma a punto únicamente para
  producir el valor numérico interno.

La observación general es opcional. Responsable, cargo, marca, modelo y serial
se completan con los datos actuales de la sesión y del equipo. `ODT` queda
`NULL` hasta que se diseñe la integración con `MOT_INDICE`.

## Modelo y almacenamiento local

`AlignmentMeasurement` representa una captura completa. Sus valores se
organizan por el nombre exacto de las columnas de MariaDB.

SQLite incorpora `ALINEACIONES_LOCAL` con:

- `uuid` como clave primaria.
- `fecha`, `hora`, `sistema` y `localizacion`.
- Las cuatro columnas `AMB_*`.
- Las cuatro columnas `ACM_*`.
- Las cuatro columnas `ACB_*`.
- `observaciones`, `responsable`, `cargo`, `marca`, `modelo`, `serial` y `odt`.
- `sincronizado`, `error_sync` y `created_at`.

Los valores no aplicables se guardan como `NULL`:

- MOTOR–BOMBA deja `ACM_*` y `ACB_*` en `NULL`.
- MOTOR–CAJA–BOMBA deja `AMB_*` en `NULL`.

La tabla tiene un índice por `sincronizado, created_at`. Las migraciones son
aditivas y no eliminan datos existentes.

Al confirmar:

1. La aplicación valida todos los campos.
2. Inserta una fila local con `sincronizado = 0`.
3. Si SQLite falla, conserva el formulario y muestra el error.
4. Si SQLite confirma, informa que la alineación quedó pendiente para USB.
5. Regresa a la secuencia de operaciones.

No se realizan llamadas de red durante este flujo.

## Sincronización exclusiva por USB

`tablet_uploader.py` incorpora la alineación en la misma solicitud
`upload_pending` utilizada por las demás operaciones.

El orden exacto de inserción en `MOT_ALN_REG` es:

1. `FECHA`
2. `HORA`
3. `SISTEMA`
4. `LOCALIZACION`
5. `AMB_ANGULO_V`
6. `AMB_ANGULO_H`
7. `AMB_COMPENSACION_V`
8. `AMB_COMPENSACION_H`
9. `ACM_ANGULO_V`
10. `ACM_ANGULO_H`
11. `ACM_COMPENSACION_V`
12. `ACM_COMPENSACION_H`
13. `ACB_ANGULO_V`
14. `ACB_ANGULO_H`
15. `ACB_COMPENSACION_V`
16. `ACB_COMPENSACION_H`
17. `OBSERVACIONES`
18. `USUARIO`
19. `CARGO`
20. `MARCA`
21. `MODELO`
22. `SERIAL`
23. `ODT`

Cada fila se procesa en una transacción independiente:

- Si se inserta, la fila local se marca como sincronizada.
- Si ya existe una fila con la misma firma normalizada, se considera
  sincronizada sin duplicarla.
- La firma compara localización, fecha, hora, los 12 valores con dos decimales,
  los textos administrativos y `ODT`.
- Dos lecturas diferentes con la misma fecha y hora no se deben confundir.
- Si MariaDB falla, la fila permanece pendiente y guarda el error.
- El fallo de una fila no impide procesar las demás.

La pantalla Sincronización muestra las alineaciones pendientes, las incluye en
el contador general y permite revisar, editar o eliminar únicamente filas no
sincronizadas. No se agrega ningún botón ni ruta de subida por red/API.

## Historial

La pantalla Mediciones incorpora el filtro **Alineación**. Cada tarjeta muestra:

- Localización, sistema, fecha y hora.
- Tipo de conjunto.
- Solo los campos aplicables, con su unidad.
- Observación.
- Estado Pendiente o Sincronizada.
- Error USB, si existe.

Los registros locales sincronizados permanecen disponibles. El subidor USB
también mantiene una caché `ALINEACIONES_REMOTAS` con un historial acotado de
MariaDB para consulta offline. La interfaz elimina duplicados entre la caché
remota y los registros locales mediante la firma completa.

El historial no se usa para mostrar comparaciones durante una captura.

## Edición y eliminación

Desde Sincronización, una alineación pendiente puede abrir el mismo formulario
en modo revisión:

- Los valores actuales aparecen precargados.
- Se aplican las mismas reglas de validación.
- Guardar actualiza la fila local y limpia el error USB anterior.
- Eliminar requiere confirmación.
- Una fila sincronizada no puede editarse ni eliminarse desde la cola.

## Contadores

Los contadores de inicio y sincronización incluyen:

- Alineaciones pendientes.
- Alineaciones sincronizadas durante el día.
- Errores de alineación.

La incorporación no cambia la semántica de los contadores de las otras
operaciones.

## APK para trabajo USB

El subidor necesita `adb run-as`. El APK para la tablet se genera con
`build_usb_apk.ps1`, que usa una variante debug coherente:

```powershell
flutter build apk --debug --target-platform android-arm64
```

No se debe convertir una variante release en debuggable, porque mezclar el
motor precompilado con recursos debug produce un APK que se cierra al iniciar.

Después de cada APK:

1. Instalar `app-debug.apk` con `adb install -r`.
2. Abrir la actividad principal en la tablet.
3. Abrir la interfaz gráfica de `tablet_uploader.py` en la laptop.
4. Confirmar que la app permanece abierta y que USB indica `ONLINE`.

## Pruebas y criterios de aceptación

Las pruebas Dart deben cubrir:

- Visibilidad de Alineación para `PUNTOS 1, 2, 6 y 9`.
- Ausencia de Alineación para los demás códigos.
- Secuencia combinada de hasta cuatro operaciones.
- Formulario correcto para MOTOR–BOMBA.
- Formulario doble para MOTOR–CAJA–BOMBA.
- Campos obligatorios.
- Signos, coma decimal, cero y máximo dos decimales.
- Rechazo del punto decimal.
- Mapeo de columnas aplicables y valores `NULL`.
- Guardado local sin llamadas de red.
- Historial, edición y eliminación de pendientes.

Las pruebas Python deben cubrir:

- Migración aditiva de SQLite.
- Orden exacto del `INSERT` en `MOT_ALN_REG`.
- Valores no aplicables como `NULL`.
- Firma de deduplicación completa.
- Lecturas diferentes en el mismo segundo.
- Transacciones por fila.
- Marcado de éxito y error en la cola correcta.
- Inclusión en GUI, CLI y solicitudes iniciadas desde la tablet.
- Caché remota acotada y orden cronológico.

La verificación final exige:

- Suite Flutter completa aprobada.
- Suite Python completa aprobada.
- APK USB generado mediante `build_usb_apk.ps1`.
- Instalación conservando los datos locales.
- Arranque real sin error fatal.
- Estado USB `ONLINE`.
- Programa de subida visible en la laptop.

El módulo se considera terminado cuando un operador puede capturar, revisar,
editar, eliminar, consultar y subir una alineación aplicable sin usar la red de
la tablet y sin afectar las otras tres operaciones.
