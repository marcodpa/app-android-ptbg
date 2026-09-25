# Módulo de filtros — implementación del 21/09/2026

Estado: código implementado, análisis y pruebas locales realizados, APK debug
ARM64 compilado e instalado como actualización en TABR70000000012091.
**Sin cambios en el servidor y sin validación de producción.** No se hizo commit ni push.

Actualización del catálogo: el usuario entregó `MDB_SYSTEM (1).csv` correcto.
Se validaron los tres CSV: 7 sistemas, 31 subsistemas y 46 registros de filtros;
CODE_SYS 3 = Combustible diésel y 4 = Agua. Queda resuelta la duda de códigos.

## Interfaz y flujo

Acceso por el icono de filtros de la barra lateral, ruta `/filtros`.
Se reutilizan el tema STER y los encabezados existentes. El módulo prioriza
orientación vertical: listas y formularios de una columna, controles apilados,
áreas seguras y desplazamiento vertical. La barra lateral ahora permite
desplazarse cuando la altura no alcanza para todos los accesos.

- Sistemas → subsistemas → filtros. Se relacionan por CODE_SYS/CODE_SUB_SYS,
  nunca por ID ni por nombres deducidos. Solo ramas habilitadas.
- Registro con revisión/confirmación, cambio de cantidad completa bloqueada,
  modelo, marca, especificaciones y observaciones. Campos limitados al esquema.
- Fecha/hora automáticas al confirmar; responsable y cargo de la sesión;
  UUID e identidad persistente de la tablet. No se añadió retrofechado.
- Una ODT por cambio en esta primera implementación, con numeración general
  compartida. No se implementó agrupación de varios filtros en una ODT.
- Historial por filtro o general, búsqueda por fecha, ODT, responsable/tablet,
  estado pendiente/sincronizado y errores. Sin datos de mantenimiento inventados.
- Administración solo para administradores: catálogo, alta de filtros y
  habilitación/deshabilitación de sistemas y subsistemas existentes.
  Las solicitudes administrativas se guardan pendientes, sin cambiar el
  catálogo vigente hasta recibir confirmación por USB. El uploader vuelve a
  comprobar el rol ADMIN/ADMINISTRADOR en MDB_USERS antes de aplicar cambios.

Las guías de interfaz se aplicaron a etiquetas visibles, validación, controles
verticales, estados de error y adaptación de texto; no se cambió el diseño de
los módulos de motores. Las pruebas visuales usan datos simulados, no lecturas
de la planta. Referencia: `test/goldens/filtros_vertical_readable.png`.

## Persistencia y sincronización

SQLite pasa de versión 12 a 13 con creación aditiva e idempotente. Tablas:
FILTROS_SYSTEM, FILTROS_SUBSYSTEM, FILTROS_ELEMENTS, FILTROS_CAMBIOS_LOCAL y
FILTROS_CATALOGO_PENDING y FILTROS_META. **Estas son tablas locales; no se creó ninguna tabla
ni columna remota.**

La orden/reserva y el cambio se insertan en una transacción. Se incorpora
`modulo` a ORDENES_TRABAJO_LOCAL, por defecto `motores`. Las reservas de filtros
se etiquetan `filtros` y llevan `sincronizado=1` en esa tabla exclusivamente
para impedir que un uploader antiguo las mande a MOT_INDICE. Su estado real
de envío está en FILTROS_CAMBIOS_LOCAL, también contado y visible en Sync.
No interpretar la reserva como un mantenimiento ya enviado.

`filter_sync.py`, llamado por `tablet_uploader.py`, implementa:

- Lectura explícita de PTBG_DAT.MDB_SYSTEM/MDB_SUBSYSTEM y
  PTBG_FLT.FLT_ELEMENTS/FLT_CHANGE. El APK incluye ahora el catálogo semilla
  validado en `assets/data/filter_catalog.json`. Solo se carga cuando no hay
  metadatos, catálogos, historial ni solicitudes previas. Una descarga marca
  origen servidor incluso cuando el catálogo está vacío: nunca se repone desde
  el APK un filtro borrado por la BD. La semilla no reemplaza futuras descargas.
- Descarga completa validada antes de reemplazar cachés locales, en transacción.
  Borrados del servidor eliminan solo historial confirmado; se conservan pendientes.
  Un fallo mantiene el catálogo anterior y se informa en el estado USB.
- Inserción de cambios en FLT_CHANGE sin duplicar un UUID en reintentos,
  comparando el contenido; conflictos y fallos quedan pendientes con error.
- Cantidad y pertenencia al catálogo se comprueban de nuevo antes de subir;
  si cambiaron, no se sobreescribe ni se adapta silenciosamente la captura.
- Bloqueo MariaDB `STER_ODT_GENERAL` compartido con el uploader de motores.
  La asignación revisa MOT_INDICE y FLT_CHANGE. Reasigna colisiones conservando
  identidad y relaciones locales, sin renumerar historial confirmado de otro módulo.
- Altas idempotentes por localización y contenido, sin sobrescribir un filtro
  distinto. Habilitaciones sobre códigos existentes, sin borrados de historial.

La cantidad se conserva en la captura local, pero FLT_CHANGE no tiene campo
para esa copia histórica. No se inventa la cantidad de registros descargados
ni se reconstruye desde el catálogo actual. Sigue pendiente resolver esa
limitación remota si se necesita para reportes. No se añadió registro del
elemento retirado ni una quinta tabla remota.

## Verificación realizada

- `flutter analyze --no-pub`: sin incidencias.
- Suite Flutter completa tras integrar la semilla: 291 pruebas aprobadas.
- Pruebas focalizadas posteriores de filtros/encabezados: 15 aprobadas,
  incluyendo 375×812, 600×960 y 960×600, temas día/noche, texto al 200% y
  movimiento reducido. Captura gráfica adicional revisada con fuentes legibles.
- Python: 104 pruebas aprobadas de filtros, tablet de origen, uploader y
  limpieza de plato; bases SQLite aisladas como dobles del servidor.
- Casos de filtros: migración repetible, códigos distintos de ID, cantidad
  completa, reintento, fallo de commit, commit confirmado sin acuse local,
  colisiones de ODT entre módulos, lock ocupado, UUID conflictivo, borrados,
  catálogo inválido, permisos de administrador y altas repetidas.
- APK debug ARM64 compilado mediante el SDK Android y JDK17 ya instalados,
  con variables de entorno limitadas al proceso. Archivo:
  `build/app/outputs/flutter-apk/app-debug.apk`.
- La compilación advierte sobre compatibilidad futura de Kotlin en
  mobile_scanner/shared_preferences_android; no impide este build. No se
  actualizaron dependencias ajenas al alcance.
- Graphify actualizado por AST, sin API. Conservó 34 nodos de 9 archivos
  existentes fuera del escaneo y renombró comunidades por sus nodos principales;
  no se forzó una purga del grafo.

Se respaldó y actualizó la tablet TABR70000000012091 con `adb install -r`.
La aplicación arrancó y la BD tuvo integridad `ok`. Comparación antes/después:
27 tablas y 697 registros anteriores sin cambios, además de los nuevos 7 sistemas,
31 subsistemas y 46 filtros. No se creó ningún mantenimiento de prueba.
Respaldo: `output/tablet-backups/20260921-131537-TABR70000000012091/`.

No se probaron lector de pantalla, lector QR, conexión real de dos tablets ni
restricciones/índices reales de MariaDB. El servidor responde, pero la conexión
sin contraseña fue rechazada. Se preparó `verificar_filtros_bd.py` con ventana
local de credenciales, transacción de solo lectura y salida sin secretos.
La validación permanece pendiente hasta completar ese acceso.

## Antes de usarlo en planta

### Revisión visual del 21/09/2026

Las ocho vistas usan ahora componentes visuales específicos de filtros:
ilustraciones vectoriales turquesa, tarjetas y barra lateral del estilo STER,
adaptadas a vertical. Home incluye una tarjeta «Cambio de filtros» que navega
a `/filtros`; se verificó su acceso en la tablet. No cambia la lógica de datos.
Análisis final limpio y 293 pruebas Flutter aprobadas; APK instalado con `-r`.
Capturas reales en `output/design/filtros/qa/after-home-tablet.png` y
`after-systems-tablet.png`. Los screenshots de las ocho vistas de prueba están
en `test/goldens/filtros_01_sistemas.png` a `filtros_08_disponibilidad.png`.

### Validaciones operativas pendientes

1. Catálogo y códigos resueltos mediante los CSV correctos; confirmar contra
   una descarga actual de la BD antes de operar en planta.
2. Actualizar **todos** los uploaders que puedan asignar ODT: una versión antigua
   no toma el nuevo bloqueo y no puede garantizar coordinación entre módulos.
3. Revisar DDL, permisos y motores transaccionales. Recomendable validar unicidad
   de UUID/ODT y códigos en el servidor antes de habilitar varios escritores;
   el bloqueo solo coordina a clientes que lo respetan, no ediciones manuales.
4. Respaldo e instalación completados en una tablet; falta descargar el catálogo
   desde la BD real. El APK no hizo una nueva descarga del catálogo de motores.
5. Hacer una captura controlada, subirla, verificar FLT_CHANGE y descargarla en
   la segunda tablet. Probar reintento y pérdida de conexión sin borrar pendientes.

No ejecutar pruebas destructivas ni modificar índices de producción sin
revisión y autorización específica.
