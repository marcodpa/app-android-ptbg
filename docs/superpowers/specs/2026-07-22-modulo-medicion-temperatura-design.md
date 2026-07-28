# Implementar el módulo de medición de temperatura

Esta especificación define un módulo completo para capturar temperaturas en grados Celsius (°C), trabajar sin conexión, sincronizar con MariaDB y consultar el historial. El módulo reutiliza la secuencia visual de puntos de Vibración, pero registra una sola temperatura por ubicación física.

## Objetivo y alcance

El operador debe poder seleccionar **Temperatura** después de escanear un equipo. La app guía la captura, guarda el resultado en la tablet y lo sincroniza con `MOT_TEMP_MUES` mediante la API o el subidor USB.

El alcance incluye:

- Selección y orden de operaciones
- Captura guiada en °C
- Última lectura por equipo y punto
- Persistencia local sin conexión
- Sincronización por API y USB
- Consulta del historial
- Pruebas automáticas y regresión de Vibración

Lubricación y Alineación quedan fuera de alcance.

## Flujo del operador

1. El operador escanea el código QR y pulsa **Iniciar medición**.
2. La pantalla de operaciones muestra Vibración, Temperatura y Reemplazo.
3. El operador selecciona una o más operaciones y define cuál comienza cuando corresponde.
4. Temperatura abre la captura guiada con el equipo escaneado.
5. La app muestra un punto físico, su nombre, su referencia visual y un campo numérico en °C.
6. El operador registra una lectura y avanza al siguiente punto.
7. Los equipos FIN-FAN incluyen el último paso `T10`, identificado como `Correa (FIN-FAN)`.
8. Al finalizar, la app solicita una observación general y guarda la medición.
9. Si queda otra operación seleccionada, la app ofrece continuar con ella.

## Arquitectura

Temperatura mantiene modelos y almacenamiento propios. Esta separación evita cambios de comportamiento en Vibración y permite reutilizar componentes visuales sin duplicarlos.

Los componentes principales serán:

- `TemperatureCaptureScreen`: controla la captura guiada y el estado de la pantalla
- `TemperaturePlanResolver`: convierte la configuración física del equipo en pasos `T1` a `T10`
- `TemperatureMeasurement`: representa una medición local y su estado de sincronización
- `TemperatureReading`: representa la última lectura remota de un equipo
- `TemperatureService`: consulta y sincroniza temperaturas mediante la API
- `DbHelper`: crea y administra las tablas locales de temperatura
- `MedicionesScreen`: separa el historial de Vibración y Temperatura
- `tablet_uploader.py`: sube pendientes y actualiza las últimas temperaturas mediante USB
- `Api_scv_ptbg.py`: inserta y consulta filas de `MOT_TEMP_MUES`

La pantalla reutiliza `EquipoVisualResolver`, `EquipoPuntoViewer` y los recursos gráficos existentes. El nuevo resolutor controla las columnas de temperatura y agrega `T10` cuando el plan corresponde a FIN-FAN.

## Mapeo de columnas

Cada paso escribe una sola columna de `MOT_TEMP_MUES`:

| Columna | Ubicación física |
| --- | --- |
| `T1` | Lado libre del motor |
| `T2` | Lado acople del motor |
| `T3` | Lado eje baja de la caja, junto al motor |
| `T4` | Lado eje alta de la caja, junto a la bomba |
| `T5` | Lado acople de la bomba |
| `T6` | Lado libre de la bomba |
| `T7` | Ventilador, lado superior, acople o punto 1 |
| `T8` | Ventilador, lado inferior, libre o punto 2 |
| `T9` | Lado libre del ventilador FIN-FAN |
| `T10` | Correa del FIN-FAN |

`TemperaturePlanResolver` debe seguir el mismo código físico que usa el plan actual de Vibración. El resolutor solo incluye las columnas aplicables al equipo:

| Código de puntos | Columnas de temperatura |
| --- | --- |
| `1`, `2`, `3`, `7`, `8`, `9` | `T1`, `T2`, `T5`, `T6` |
| `4` | `T1`, `T2`, `T9`, `T10` |
| `5` | `T1`, `T2`, `T7`, `T8` |
| `6` | `T1`, `T2`, `T3`, `T4`, `T5`, `T6` |

Las columnas que no aplican se envían como `0.00`. Este valor coincide con los valores predeterminados de `MOT_TEMP_MUES`.

## Captura y validación

La pantalla conserva el patrón de captura de Vibración:

- Encabezado con identificación del equipo
- Imagen con el punto actual resaltado
- Nombre de la ubicación física
- Progreso de la secuencia
- Campo numérico con sufijo `°C`
- Lectura anterior del mismo punto, con fecha y hora
- Navegación anterior y siguiente
- Observación general al finalizar

El campo acepta enteros y decimales con punto o coma. La app no permite avanzar cuando el campo está vacío o no contiene un número válido. La primera versión no bloquea valores por rango, porque la tabla admite `DECIMAL(10,2)` y no existe un límite operativo confirmado.

La app enfoca el campo y abre el teclado numérico al entrar o avanzar. Un bloqueo de guardado evita registros duplicados por pulsaciones repetidas. Si el operador intenta salir después de capturar datos, la app solicita confirmación antes de descartarlos.

## Modelo local

La base SQLite agrega una tabla exclusiva para temperatura. Cada fila contiene:

- `uuid`
- `fecha`
- `hora`
- `sistema`
- `localizacion`
- `T1` a `T10`
- `observaciones`
- `usuario`
- `cargo`
- `marca`
- `modelo`
- `serial`
- `odt`
- `sincronizado`
- `error_sync`

La migración debe conservar todas las mediciones locales existentes. `odt` admite `NULL`. La app envía un ODT cuando el flujo de equipo lo entrega; de lo contrario, guarda y sincroniza `NULL`.

Una tabla o caché separada conserva las últimas temperaturas descargadas. La clave funcional para elegir la lectura más reciente es `localizacion`, seguida por fecha y hora.

## API y sincronización

La API agrega superficies específicas para temperatura:

- `POST /temperaturas`: inserta una medición en `MOT_TEMP_MUES`
- `GET /temperaturas`: devuelve el historial de temperatura
- `GET /temperaturas/ultimas`: devuelve la última medición por localización
- `GET /temperaturas/ultima/{localizacion}`: devuelve la última temperatura de un equipo

El payload refleja los nombres de `MOT_TEMP_MUES`. La API valida la localización, convierte `T1` a `T10` a valores decimales e inserta los campos administrativos. La autenticación sigue las reglas de los endpoints actuales de mediciones.

El subidor USB debe:

1. Detectar las filas pendientes de temperatura en la copia SQLite de la tablet.
2. Insertarlas en `MOT_TEMP_MUES` dentro de una transacción.
3. Marcar cada fila local como sincronizada después de confirmar la inserción.
4. Guardar el mensaje en `error_sync` cuando falle una fila.
5. Descargar las últimas temperaturas y actualizar la caché local.

Una caída de red o MariaDB no elimina datos locales. La interfaz muestra el error y permite reintentar. La sincronización debe ser idempotente por `uuid` en el lado local y evitar que dos pulsaciones inicien el mismo proceso.

## Historial

La pantalla **Mediciones** debe distinguir los tipos de lectura. Una pestaña o filtro permite elegir Vibración o Temperatura sin mezclar mm/s y °C.

Cada registro de temperatura muestra:

- Equipo y localización
- Fecha y hora
- Valores `T` aplicables con unidad °C
- Usuario responsable
- Estado local, pendiente o sincronizado
- Observaciones, cuando existan

El historial usa la caché local cuando la API no está disponible. La descarga remota actualiza la caché sin borrar mediciones locales pendientes.

## Estados y errores

El módulo debe manejar estos estados:

- Carga inicial del plan, datos del equipo y última lectura
- Captura disponible aunque falle la consulta de la última lectura
- Error de entrada numérica sin perder el texto válido anterior
- Guardado local antes de intentar sincronizar
- Medición pendiente cuando falla la red
- Error de sincronización con mensaje y opción de reintento
- Confirmación al salir con datos sin guardar
- Finalización única aunque el operador pulse varias veces

Un equipo con un código de puntos desconocido usa el mismo plan de respaldo que Vibración: `T1`, `T2`, `T5` y `T6`. La app debe registrar el caso para facilitar la corrección de datos maestros.

## Pruebas

La implementación seguirá desarrollo guiado por pruebas. Cada comportamiento nuevo debe tener una prueba que falle antes de agregar el código correspondiente.

Las pruebas unitarias cubrirán:

- Resolución de columnas para cada código de puntos
- Inclusión de `T10` en FIN-FAN
- Exclusión de columnas que no aplican
- Conversión de coma y punto decimal
- Serialización y lectura del modelo local
- Construcción del payload de API
- Selección de la última lectura por fecha y hora

Las pruebas de widgets cubrirán:

- Presencia de Temperatura en el selector
- Selección y orden de las tres operaciones
- Una sola lectura por punto, sin controles H, V o A
- Unidad °C y mensajes de validación
- Navegación entre puntos
- Confirmación al salir
- Finalización sin duplicados
- Visualización del historial de temperatura

Las pruebas de integración cubrirán:

- Migración SQLite sin pérdida de mediciones
- Guardado pendiente sin conexión
- Sincronización API hacia `MOT_TEMP_MUES`
- Sincronización USB hacia `MOT_TEMP_MUES`
- Descarga y caché de últimas temperaturas
- Reintento después de un error
- Regresión del flujo completo de Vibración

La verificación final debe ejecutar las pruebas de Dart y Python, `flutter analyze` y la compilación Android usada para la tablet.

## Criterios de aceptación

El módulo queda aceptado cuando:

- El operador puede seleccionar Temperatura después de escanear un equipo
- Cada equipo presenta las columnas `T` definidas por su código de puntos
- FIN-FAN incluye `T10` para la correa
- Cada punto acepta una sola lectura en °C
- La app guarda la medición antes de sincronizar
- La API y el subidor USB insertan en `MOT_TEMP_MUES`
- El historial muestra temperaturas locales y remotas
- Un fallo de conexión no pierde lecturas
- Las pruebas de Vibración continúan aprobadas

## Decisiones confirmadas

- Las lecturas se registran manualmente en °C
- Temperatura usa los puntos físicos de Vibración, con una lectura por punto
- FIN-FAN agrega una lectura para la correa en `T10`
- La primera entrega incluye captura, almacenamiento, API, USB e historial
- El módulo mantiene almacenamiento y servicios separados de Vibración
- `odt` se guarda como `NULL` cuando no está disponible
