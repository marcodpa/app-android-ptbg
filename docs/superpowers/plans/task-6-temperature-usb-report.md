# Task 6 — Sincronización USB de temperatura

## Estado

Implementado en `tablet_uploader.py` con TDD estricto y sin modificar el comportamiento funcional de vibración o reemplazo.

## Alcance implementado

- Compatibilidad y migración no destructiva de `TEMPERATURAS_LOCAL`.
- Lectura exclusiva de temperaturas pendientes (`sincronizado = 0`).
- Normalización de `T1` a `T10`: valores ausentes o `NULL` se envían como `0.0`.
- Payload en el orden exacto de `MOT_TEMP_MUES`: `FECHA`, `HORA`, `SISTEMA`, `LOCALIZACION`, `T1`–`T10`, campos administrativos y `ODT`.
- Detección idempotente por `LOCALIZACION + FECHA + HORA`.
- Inserción por fila con `commit`; ante error se ejecuta `rollback` y se conserva la fila pendiente con `error_sync`.
- Marcado local de filas insertadas o ya existentes sin tocar `MEDICIONES_LOCAL`.
- Inclusión del resumen de temperaturas en `upload_pending_work`, usado por CLI, solicitud automática desde la tablet y GUI manual.
- Conteo y visualización de temperaturas pendientes en los flujos de dispositivo y GUI.
- Descarga de `MOT_TEMP_MUES` a `TEMPERATURAS_REMOTAS` y selección de la última lectura por equipo en `ULTIMA_TEMPERATURA`.
- La actualización de caché remota elimina y reconstruye solo las tablas remotas; no borra ni modifica temperaturas locales pendientes.

## Evidencia TDD

### RED

Comando:

```powershell
& 'C:\Users\home-it\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest test_tablet_uploader.py -v
```

Resultado esperado observado: fallo de importación porque `TEMPERATURE_COLUMNS` todavía no existía en `tablet_uploader.py`.

### GREEN dirigido

Se ejecutaron las diez pruebas nuevas de temperatura, resumen combinado,
rollback e integración del flujo de dispositivo.

Resultado: `Ran 10 tests ... OK`.

### Regresión completa

```powershell
& 'C:\Users\home-it\AppData\Local\Python\pythoncore-3.14-64\python.exe' -m unittest test_tablet_uploader.py -v
```

Resultado: `Ran 22 tests ... OK`.

## Archivos modificados

- `tablet_uploader.py`
- `test_tablet_uploader.py`
- `docs/superpowers/plans/task-6-temperature-usb-report.md`

No se creó commit porque el directorio no es un repositorio Git.

## Seguimiento de revisión P2/P3

Se reforzó `test_tablet_uploader.py` con evidencia automática adicional:

- Comparación completa de `TEMPERATURE_INSERT_COLUMNS` y de todos los valores producidos por `build_temperature_insert_values`, incluyendo su orden exacto.
- Excepción real durante el `INSERT` de la primera de dos temperaturas: verifica un `rollback`, persistencia de `error_sync`, permanencia en la cola pendiente y continuación exitosa con la segunda fila.
- Integración de `perform_usb_upload_for_device` usando SQLite y la lógica real de cola/subida/marcado/resumen. Solo se sustituyen límites externos (ADB, sincronizaciones remotas auxiliares y conexión MariaDB); verifica conteo pendiente, resumen específico de temperatura, descarga histórica, marcado local, escritura de la base a la tablet y estado final `DONE`.

Las pruebas nuevas pasaron en su primera ejecución contra la implementación existente. Por tanto, caracterizaron comportamiento correcto ya presente y no revelaron un defecto que justificara modificar producción.

## Correcciones bloqueantes posteriores

### Deduplicación por firma completa

La coincidencia por `LOCALIZACION + FECHA + HORA` ahora solo selecciona las filas remotas candidatas. Una lectura se considera duplicada únicamente cuando también coincide su firma completa:

- `T1`–`T10`, normalizadas a dos decimales con redondeo decimal.
- Sistema, observaciones, usuario/responsable, cargo, marca, modelo y serial, normalizados como texto sin espacios exteriores.
- `ODT`, normalizada para que representaciones equivalentes como entero o texto coincidan.

Si cualquier temperatura o campo difiere, se inserta una fila nueva aunque comparta el mismo segundo. El ciclo RED reprodujo el falso `skipped` con `T1` distinta; después del cambio ambas pruebas —idéntica y distinta— quedaron en GREEN.

### Caché remota acotada y combinación local

- Se eliminó la lectura ilimitada `SELECT * FROM MOT_TEMP_MUES`.
- El historial offline se limita a las 500 filas más recientes mediante `ORDER BY ID DESC LIMIT 500`.
- Una consulta agregada separada obtiene `MAX(ID)` por `LOCALIZACION`, transfiriendo solo la última fila de cada equipo.
- `ULTIMA_TEMPERATURA` se reconstruye comparando las últimas remotas con `TEMPERATURAS_LOCAL`.
- Una lectura local más nueva se conserva; una pendiente local también prevalece ante empate de fecha y hora.
- `TEMPERATURAS_REMOTAS` continúa conteniendo exclusivamente filas descargadas de MariaDB y no consume ni modifica la cola local.

Pruebas añadidas verifican el límite SQL, la consulta por localización y la supervivencia de una pendiente local más reciente frente a un remoto más antiguo.

### Orden cronológico remoto

El límite de 500 filas y la selección de la última lectura por localización usan ahora el mismo orden cronológico:

1. `FECHA DESC`
2. `HORA DESC`
3. `ID DESC`, únicamente como desempate

El historial aplica ese orden antes de `LIMIT 500`. Para la última lectura, MariaDB calcula `ROW_NUMBER()` por `LOCALIZACION` con el orden anterior y conserva `chronological_rank = 1`; se eliminó el criterio incorrecto basado exclusivamente en `MAX(ID)`.

La prueba de contrato SQL falló primero al encontrar `ORDER BY ID DESC` y quedó en GREEN después de aplicar el orden cronológico y la ventana por localización.

### Fechas almacenadas como texto

Como `FECHA` y `HORA` pueden venir en formato ISO o `dd/mm/yyyy`, el orden remoto ya no compara texto directamente. Tanto el historial limitado como `ROW_NUMBER()` usan:

```sql
COALESCE(
  STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%Y-%m-%d %H:%i:%s'),
  STR_TO_DATE(CONCAT(FECHA, ' ', HORA), '%d/%m/%Y %H:%i:%s')
) DESC,
ID DESC
```

Se añadió una prueba de cruce de año (`31/12/2025 23:59:59` frente a `2026-01-01 00:00:00`) y el contrato SQL exige ambas conversiones en las dos consultas. El ciclo RED detectó la comparación textual anterior y quedó en GREEN con la conversión cronológica.
