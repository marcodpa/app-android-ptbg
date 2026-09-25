# Módulo de cambio de filtros — especificación inicial

Fecha: 21/09/2026. Estado actualizado: **implementado en código y probado
localmente; APK compilado e instalado en una tablet, no validado en producción**.
Ver [implementación y requisitos de puesta en marcha](MODULO_FILTROS_IMPLEMENTACION.md).
Las secciones siguientes conservan las decisiones y límites de la fase de diseño;
el documento de implementación distingue lo resuelto de lo todavía pendiente.

## Alcance confirmado por el usuario

Módulo nuevo e independiente de los servicios actuales, con el diseño existente
de STER. Recorrido: sistema → subsistema → elemento filtrante → registrar cambio
o consultar historial. Mantener los módulos actuales sin migrarlos a estos
catálogos por inferencia.

Catálogos compartidos en `PTBG_DAT`: `MDB_SYSTEM` y `MDB_SUBSYSTEM`.
Catálogo y movimientos de filtros en `PTBG_FLT`: `FLT_ELEMENTS` y `FLT_CHANGE`.
La bandera `PTBG_FLT = 1` habilita sistemas y subsistemas en este módulo;
`0` no los muestra. Propuesta defensiva: NULL tampoco habilita.

Sistemas confirmados por `MDB_SYSTEM (1).csv`, entregado el 21/09/2026.
Esta exportación corrige el orden 3/4 del mensaje inicial:

| CODE_SYS | SISTEMA |
| --- | --- |
| 1 | TURBOGENERADOR_CT_GTG_001 |
| 2 | TURBOGENERADOR_CT_GTG_002 |
| 3 | COMBUSTIBLE DIESEL |
| 4 | AGUA |

No confundir estos códigos con identificadores de catálogos anteriores ni con
el orden de la primera imagen conceptual, que mostraba siete sistemas ilustrativos.
No fijar permanentemente estos cuatro en código: deben provenir del catálogo habilitado.

## Estructura observada en las capturas

Transcripción para preparar la integración, no sustituto de un `SHOW CREATE TABLE`.
No se verificaron directamente columnas, restricciones, índices únicos ni motores
en el servidor. Los tamaños de INT/SMALLINT/TINYINT mostrados entre paréntesis
en la herramienta no se interpretan como longitud de texto ni límite de dígitos.

### PTBG_DAT.MDB_SYSTEM

`ID` INT, clave primaria autoincremental; `SISTEMA` VARCHAR(50);
`CODE_SYS` SMALLINT; `PTBG_FLT` TINYINT.

### PTBG_DAT.MDB_SUBSYSTEM

`ID` INT, clave primaria autoincremental; `CODE_SYS` SMALLINT;
`NAME_SUB_SYS` VARCHAR(100); `CODE_SUB_SYS` SMALLINT; `PTBG_FLT` TINYINT.

Seleccionar los subsistemas por el `CODE_SYS` del sistema elegido y por su
propia bandera. No usar el ID autoincremental como sustituto de CODE_SYS o
CODE_SUB_SYS. No asumir que el código de subsistema sea globalmente único:
la selección deberá respetar ambos códigos.

### PTBG_FLT.FLT_ELEMENTS

| Columna | Tipo observado |
| --- | --- |
| ID | INT, clave primaria autoincremental |
| TAGNAME | VARCHAR(150) |
| CODE_SYS | SMALLINT |
| CODE_SUB_SYS | SMALLINT |
| ELEMENTO | VARCHAR(150) |
| CANTIDAD | SMALLINT |
| LOCALIZACION | SMALLINT |
| MODELO | VARCHAR(150) |
| MARCA | VARCHAR(150) |
| ESPECIFICACIONES | VARCHAR(50), comentario: micrones |

Filtrar por CODE_SYS y CODE_SUB_SYS, validando que ambos pertenezcan a la rama
habilitada. La captura indica 46 filas, pero no muestra el catálogo completo
y corta algunos nombres: **no cargar un catálogo parcial transcrito de la foto**.
TAGNAME, MODELO, MARCA y ESPECIFICACIONES muestran valores `SIN DATOS` en filas
visibles; no inventar datos para reemplazarlos ni usar TAGNAME como clave única.
La unicidad y estabilidad de LOCALIZACION requieren confirmación.

### PTBG_FLT.FLT_CHANGE

| Columna | Tipo observado |
| --- | --- |
| ID | INT, clave primaria autoincremental |
| FECHA | DATE |
| HORA | TIME |
| SISTEMA | VARCHAR(50) |
| CODE_SYS | INT |
| CODE_SUB_SYS | INT |
| LOCALIZACION | SMALLINT |
| TAGNAME | VARCHAR(150) |
| ELEMENTO | VARCHAR(150) |
| OBSERVACIONES | TEXT |
| USUARIO | VARCHAR(150) |
| CARGO | VARCHAR(150) |
| MODELO | VARCHAR(150) |
| MARCA | VARCHAR(150) |
| ESPECIFICACIONES | VARCHAR(50) |
| ODT | INT |
| UUID | CHAR(36) |
| TABLET_ORIGEN | VARCHAR(100) |

La captura presenta campos no anulables y mayoritariamente sin valor
predeterminado. Confirmar con DDL antes de implementar inserciones y decidir
tratamiento de datos desconocidos sin fabricar modelo, marca o micraje.
No aparece CANTIDAD ni CANTIDAD_CAMBIADA en esta tabla.

Confirmación del usuario el 21/09: **siempre se cambia la cantidad completa**
configurada en FLT_ELEMENTS.CANTIDAD. No admitir cambios parciales ni pedir al
operador una cantidad diferente. Se descarta la propuesta de CANTIDAD_CAMBIADA.
La pantalla deberá mostrar la cantidad completa antes de confirmar el registro.
Límite del esquema actual: FLT_CHANGE no guarda una copia de esa cantidad;
si el catálogo cambia posteriormente, no permite demostrar por sí solo la
cantidad histórica de un cambio. No deducirla retrospectivamente del catálogo.

## Interfaz propuesta, pendiente de aprobación detallada

1. Sistemas habilitados: mismo encabezado compacto, barra lateral, tema y tarjetas de STER.
2. Subsistemas habilitados del sistema seleccionado, con buscador.
3. Elementos del subsistema: ELEMENTO como nombre principal; mostrar TAGNAME
   si está informado, LOCALIZACION, cantidad configurada y datos técnicos.
4. Cambio: contexto del elemento seleccionado, datos técnicos del recambio,
   responsable, cargo, fecha/hora y observaciones. Confirmar semántica exacta
   de los datos técnicos antes de implementarlos. UUID y tablet de origen
   no serían campos editables por el usuario.
5. Historial: conservar los valores propios de cada evento, sin reconstruir
   registros antiguos a partir de un catálogo modificado posteriormente.

Propuesta separada para administración: alta de filtros y habilitación de
sistemas/subsistemas existentes. Pendientes permisos, forma de acceso y
sincronización de estas operaciones. No activar catálogos automáticamente
por guardar un mantenimiento, ni actualizar silenciosamente datos maestros.

## Integración revisada y límites

- `lib/services/tablet_identity.dart`: `TabletIdentity.origin()` obtiene la
  identidad de la tablet y valida que no esté vacía ni supere 100 caracteres.
  Es candidato a reutilizar, no a sustituir por la identidad del PC uploader.
- `lib/models/work_order.dart`: `WorkOrder` representa servicios de equipos
  actuales; todavía no representa cambios de filtros.
- `tablet_uploader.py`: `upload_pending_work_orders()` inserta en MOT_INDICE
  y gestiona conflictos de ODT existentes. Su lógica actual no acredita soporte
  para FLT_CHANGE ni para numeración entre módulos distintos.
- `lib/db/db_helper.dart`: contiene `createWorkOrder()` y almacenamiento local
  de servicios. Una ampliación requerirá migración aditiva, conservación de
  pendientes e incorporación explícita del nuevo dominio.

Confirmación del usuario el 21/09: **filtros comparte la numeración general de
ODT con los mantenimientos actuales**, sin una secuencia independiente.
Esto es un requisito confirmado, no una integración ya implementada. La
asignación y resolución de conflictos deberán considerar ambos módulos y las
distintas tablets. Si una ODT provisional se reasigna, todos sus registros
relacionados deberán conservar la vinculación, UUID y tablet de origen.
Compartir numeración no implica agrupar automáticamente trabajos diferentes
en una misma ODT. El registro central y su representación del nuevo servicio
requieren diseño compatible con el esquema existente; no se ha alterado MOT_INDICE.

Propuesta: catálogo local para uso sin conexión y cola local de cambios con
UUID persistente, reintentos idempotentes y TABLET_ORIGEN de captura. No marcar
como sincronizado antes de confirmar la escritura remota. El índice único de
UUID y la estrategia de conflictos requieren revisión del DDL; no asumir que
la columna por sí sola impide duplicados.

No reutilizar reglas de purga de servicios actuales sin revisar este dominio:
una baja o deshabilitación de catálogo no debe borrar cambios pendientes o
historial por accidente. Las lecturas de PTBG_DAT y escrituras de PTBG_FLT
necesitan rutas explícitas y permisos comprobados.

## Decisiones necesarias antes del guardado y la sincronización

1. **Cantidad — resuelto:** siempre se sustituye la cantidad completa.
   No implementar selección parcial ni agregar CANTIDAD_CAMBIADA. La conservación
   de la cantidad histórica si cambia el catálogo sigue siendo una limitación
   documentada; no se autorizó modificar el esquema para resolverla.
2. **Fecha/hora:** confirmar captura automática de tablet y posibilidad de
   edición para trabajos anteriores.
3. **Catálogos completos — resuelto el 21/09:** recibido `MDB_SYSTEM (1).csv`
   correcto, validado junto con los subsistemas y los 46 filtros. Combustible
   es código 3 y Agua es 4. La revisión del DDL real continúa pendiente.
4. **Numeración ODT — resuelto:** compartida con los mantenimientos actuales.
   Queda por definir si una ODT puede agrupar cambios de varios filtros y la
   representación del nuevo servicio en el registro central. No crear una
   secuencia independiente ni asumir que el uploader actual ya soporta esta integración.
5. **Elemento retirado:** el usuario dejó esta decisión para más adelante.
   No crear todavía una quinta tabla ni afirmar que los campos actuales
   almacenan simultáneamente especificaciones anteriores y nuevas.

## Comprobaciones futuras (no ejecutadas)

- Jerarquía y banderas: ningún subsistema/filtro aparece bajo otro sistema.
- Migración local sin pérdida de datos existentes o pendientes.
- Guardado offline con identidad y UUID estables; reintento sin duplicado.
- Cambios de catálogo sin reescritura de historial y bajas sin pérdida de pendientes.
- Numeración ODT compartida entre filtros y servicios actuales: conflictos
  entre dos tablets, reintentos y conservación de relaciones tras reasignación.
- Escritura en PTBG_FLT y lectura de PTBG_DAT sin afectar los servicios anteriores.
- Cantidad completa visible y sin captura parcial; límites de columnas, fechas
  y valores desconocidos.
- Prueba visual con el diseño actual y tamaños de tablet; después, prueba real autorizada.

## Evidencias y estado de entrega

Mensajes y cuatro capturas aportadas el 21/09 (archivos WhatsApp fechados 18/09),
además de la estructura de MDB_SYSTEM enviada anteriormente. La fecha del nombre
de una imagen no acredita la fecha de una modificación en el servidor.
Consulta Graphify con `system subsystem work order tablet` y lectura focalizada
de los archivos citados. No se consultó ni alteró la BD, no se modificó código,
no se ejecutaron pruebas funcionales y no se compiló ni instaló APK en esta revisión.

## CSV recibidos y comprobados el 21/09/2026

Lectura sin modificar los originales, separados por punto y coma y con cabecera:
`C:/Users/home/Downloads/FLT_ELEMENTS.csv`, `MDB_SUBSYSTEM.csv` y `MDB_SYSTEM.csv`.

- FLT_ELEMENTS: 46 filas; distribución por CODE_SYS: 1 → 18, 2 → 18,
  3 → 4 y 4 → 6. Cantidades positivas en todas las filas.
- MDB_SUBSYSTEM: 31 filas, 16 habilitadas para filtros.
- No se encontraron pares de subsistema duplicados, localizaciones de filtro
  duplicadas, filtros sin par de subsistema ni filtros bajo subsistemas deshabilitados.
  Son comprobaciones de los CSV, no de restricciones reales del servidor.
- MDB_SYSTEM tiene 31 filas y la misma cabecera y contenido que MDB_SUBSYSTEM:
  falta SISTEMA y aparecen NAME_SUB_SYS y CODE_SUB_SYS. Ambos archivos comparten
  SHA256 `e3a865de516516626a15da8239b9997a8de690039e3ad160a12b6fd95e277074`.
- Contradicción pendiente: el usuario indicó 3 = AGUA y 4 = COMBUSTIBLE DIESEL;
  el CSV pone COMBUSTIBLE TRATADO ENVIO COMBUSTIBLE (subsistema 19) bajo 3,
  y AGUA DE SERVICIO, AGUA DESMINERALIZADA y CONTRA INCENDIO (22, 23 y 24) bajo 4.
  No se intercambiaron códigos ni se consideró resuelta la relación por inferencia.
- Las primeras tres filas de BG1 tienen TAGNAME = N/A, cantidades 152, 152 y 160,
  y localizaciones 1, 2 y 3. Esto actualiza los ejemplos de las capturas previas.

Se pidió al usuario una exportación correcta de MDB_SYSTEM y aclaración de los
códigos 3/4. Esta discrepancia impide dar por validada la integración, pero no
impide proponer las pantallas con datos fiables de BG1.

## Entrega visual — ocho pantallas

Cuatro láminas generadas como propuestas visuales con ImageGen integrado,
revisadas visualmente y copiadas al proyecto. Índice:
[Diseños del módulo de filtros](../output/design/filtros/README.md).

1. Sistemas y subsistemas.
2. Elementos filtrantes y registro de cambio.
3. Historial y administración del catálogo.
4. Alta de filtro y habilitación de sistemas/subsistemas.

Las guías de interfaz orientaron las etiquetas visibles, la jerarquía y los
controles para tablet, conservando el tema oscuro existente. El historial es
un estado vacío ilustrativo, no una consulta real. Permisos administrativos,
fecha/hora, códigos de agua/combustible y agrupación de ODT siguen pendientes.
No se modificó código de la aplicación ni datos del servidor; los botones de
las imágenes no son funcionales. No se requiere actualización AST de Graphify
por estos cambios de documentación e imágenes.
