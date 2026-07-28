# Flujo de vibracion y reemplazo de equipo

## Objetivo

Permitir que, despues de escanear un equipo, el usuario seleccione Vibracion, Reemplazo de equipo o ambos. Cuando seleccione ambos, el usuario decide cual ejecutar primero y puede continuar con el modulo pendiente al terminar.

## Alcance de esta fase

- Conservar sin cambios el login, inicio, escaneo QR, captura de vibracion, sincronizacion e impresion.
- Agregar el selector de operaciones despues de pulsar `Iniciar medicion` en la vista previa del QR.
- Mantener el equipo escaneado durante todo el flujo.
- Implementar el frontend completo de Reemplazo de equipo.
- No escribir reemplazos en MariaDB hasta recibir la estructura final de las tablas de Motor, Caja y Bomba.

## Selector de operaciones

La pantalla mostrara dos opciones seleccionables:

- Vibracion.
- Reemplazo de equipo.

El usuario puede seleccionar una o ambas. Si selecciona una, el boton principal inicia esa operacion. Si selecciona ambas, la interfaz solicita elegir con cual comenzar. No existe un orden predeterminado.

La pantalla no permite continuar sin al menos una operacion seleccionada. Los toques repetidos en el boton de inicio no pueden abrir rutas duplicadas.

## Continuidad entre operaciones

El flujo conserva una lista de operaciones pendientes vinculada al equipo escaneado.

Al completar la primera operacion, si existe otra pendiente, se muestra una confirmacion con dos acciones:

- `Continuar con <operacion pendiente>`.
- `Finalizar`.

Si el usuario continua, se abre el modulo pendiente con el mismo equipo. Si finaliza, vuelve a la vista previa del equipo escaneado. Si solo selecciono una operacion, al terminar vuelve a la vista previa sin ofrecer otra.

Cancelar o salir de una operacion no se considera completarla. En ese caso se conserva el comportamiento de confirmacion de salida propio del modulo y se regresa al selector o a la vista previa.

## Reemplazo de equipo

### Componentes disponibles

Los componentes se determinan exclusivamente mediante `MOT_EQUIPO.PUNTOS`:

- PUNTOS 1, 2, 3, 7, 8 y 9: Motor y Bomba.
- PUNTOS 4 y 5: Motor y Ventilador.
- PUNTOS 6: Motor, Caja y Bomba.

Los equipos Solo Motor o Motor + Caja se agregaran cuando la base de datos proporcione su identificacion oficial. El frontend mantendra el resolver aislado para ampliar esta clasificacion sin cambiar las pantallas.

### Captura

El usuario puede seleccionar uno o varios componentes disponibles. Por cada componente seleccionado se solicitan exactamente estos datos del componente nuevo:

- Marca.
- Modelo.
- Serial.

Los tres campos son obligatorios y se limpian espacios al inicio y al final. Cada formulario identifica claramente el componente al que pertenece para evitar mezclar datos.

### Revision

Antes de finalizar, la app muestra:

- Equipo, sistema, localizacion y QR.
- Componentes seleccionados.
- Marca, modelo y serial nuevos de cada componente.

En esta fase, confirmar muestra que el frontend del reemplazo quedo completado, pero no modifica MariaDB. La conexion posterior debe guardar el valor anterior en `MOT_LOG_RPL` y actualizar la tabla vigente del componente dentro de una sola transaccion.

## Arquitectura

- `OperationSelectionScreen`: seleccion multiple y orden de inicio.
- `MeasurementFlow`: estado inmutable con equipo, operaciones seleccionadas, operacion actual y pendientes.
- `ReplacementComponentResolver`: traduce `PUNTOS` a componentes disponibles.
- `ReplacementScreen`: seleccion de componentes, formularios y resumen.
- La captura actual de vibracion se reutiliza; solo se agrega una forma de notificar que termino correctamente para ofrecer la operacion pendiente.

Los datos del futuro backend se representaran por componente, evitando mezclar Marca, Modelo y Serial del Motor con los de Caja, Bomba o Ventilador.

## Estados y errores

- Sin operacion seleccionada: boton de continuar deshabilitado.
- Sin componente seleccionado: boton de reemplazo deshabilitado.
- Campos incompletos: mensaje junto al campo y sin avanzar al resumen.
- Equipo con `PUNTOS` no reconocido: mensaje claro y regreso seguro; no se inventa una composicion.
- Salida con datos escritos: confirmacion antes de descartarlos.
- Confirmacion repetida: se bloquea mientras se procesa para evitar duplicados futuros.

## Pruebas

- El selector presenta exactamente Vibracion y Reemplazo de equipo.
- Se puede seleccionar una o ambas operaciones.
- Al seleccionar ambas, el usuario puede iniciar cualquiera primero.
- La operacion completada se elimina de pendientes y se ofrece la restante.
- Finalizar no abre el modulo pendiente.
- El resolver devuelve los componentes correctos para cada valor conocido de `PUNTOS`.
- El formulario exige Marca, Modelo y Serial para cada componente seleccionado.
- El resumen conserva el equipo escaneado y separa los datos por componente.
- Regresar con cambios solicita confirmacion.
- Las pruebas existentes de captura, QR y sincronizacion siguen pasando.

## Fuera de alcance

- Cambios de esquema en MariaDB.
- Escritura en `MOT_DATA`, tablas futuras de Caja/Bomba o `MOT_LOG_RPL`.
- Impresion de reemplazos.
- Modulos de Lubricacion, Alineacion y Temperatura.
