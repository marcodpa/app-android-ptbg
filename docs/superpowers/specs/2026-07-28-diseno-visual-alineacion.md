# Diseño visual del módulo de alineación

Fecha: 2026-07-28

## Objetivo

Transformar la captura de alineación en una experiencia visual coherente con
los módulos de vibración y temperatura. La pantalla debe ayudar al técnico a
identificar el conjunto que está midiendo y mostrar una referencia inequívoca
de cómo luce una alineación perfecta, sin calcular diagnósticos ni tolerancias
que no hayan sido definidos.

## Equipos habilitados

- `PUNTOS 1`, `PUNTOS 2` y `PUNTOS 9`: alineación MOTOR–BOMBA.
- `PUNTOS 6`: alineaciones MOTOR–CAJA y CAJA–BOMBA.
- FIN-FAN, VENTILADORES y cualquier otro valor de `PUNTOS`: no muestran la
  opción de alineación ni permiten abrir esta pantalla.

Esta regla se conserva en el selector de operaciones y se refuerza al entrar a
la pantalla para evitar una captura no válida por navegación accidental.

## Dirección visual

La interfaz mantiene la identidad industrial existente: fondo gris azulado,
encabezados azul marino, superficies blancas y verde turquesa para acciones y
referencias correctas.

El elemento distintivo será una tarjeta técnica de referencia situada después
de los datos del equipo. Mostrará el tren del equipo de perfil, con los cuerpos
de las máquinas en azul y los ejes/acoples sobre una línea central turquesa.
Dos miras concéntricas y una línea continua comunicarán que los ejes están
perfectamente centrados. La leyenda será:

> Referencia de alineación correcta

Debajo se indicará que la ilustración es una guía visual y no un resultado
calculado con los valores capturados.

No se mostrará un estado “correcto/incorrecto” basado en los números porque no
existen tolerancias oficiales configuradas.

## Variantes de la referencia

### MOTOR–BOMBA

La ilustración muestra motor, acople y bomba. El acople central aparece
resaltado. La tarjeta de captura se titula `Alineación Motor–Bomba`.

### MOTOR–CAJA–BOMBA

La ilustración muestra motor, primer acople, caja, segundo acople y bomba. Los
dos acoples se distinguen con etiquetas discretas:

- `Motor–Caja`
- `Caja–Bomba`

Debajo aparecen dos tarjetas de captura completas y separadas, en ese mismo
orden.

## Estructura de la pantalla

1. Barra superior: `Medición de alineación` o `Revisar alineación`.
2. Tarjeta compacta del equipo: nombre, sistema y localización.
3. Tarjeta de referencia de alineación perfecta.
4. Una o dos tarjetas de captura según el tipo del equipo.
5. Observaciones opcionales.
6. Botón principal `Guardar alineación`.

Todo permanece en un único formulario desplazable, como solicitó el usuario.

## Tarjetas de captura

Cada tarjeta agrupa los cuatro campos mediante dos bloques semánticos:

- `Ángulo (mm/100 mm)`: vertical y horizontal.
- `Compensación (mm)`: vertical y horizontal.

Cada campo conserva una etiqueta permanente, el indicador `V` o `H`, la unidad
visible y el ejemplo `0,05`. El orden de lectura es vertical y luego
horizontal. Los campos continúan siendo obligatorios.

## Validación y estados

- Solo se acepta coma decimal.
- Se permiten valores positivos, negativos y cero.
- Se aceptan como máximo dos decimales y no se impone límite numérico.
- El error aparece debajo del campo con la instrucción para corregirlo.
- La referencia visual no cambia según el valor introducido.
- Mientras se guarda, el botón se deshabilita y muestra progreso.
- Si SQLite rechaza el registro, se conservan todos los valores escritos.
- Al guardar correctamente se confirma que quedó local en la tablet y que se
  subirá posteriormente por USB.

## Persistencia y sincronización

El rediseño no cambia el contrato de datos:

- El registro se guarda primero en SQLite local.
- `ODT` permanece nulo.
- Los campos no aplicables se guardan como `NULL`.
- No se llama a ningún API al guardar.
- La carga a MariaDB continúa exclusivamente desde Sincronización mediante la
  laptop conectada por USB.

## Accesibilidad y tablet

- Zonas táctiles de al menos 48 píxeles.
- Contraste suficiente entre texto, fondo y línea de referencia.
- El significado de vertical/horizontal no depende únicamente del color.
- El diseño se adapta al ancho de tablet sin introducir desplazamiento
  horizontal.
- El teclado numérico firmado y decimal se conserva.

## Pruebas

- MOTOR–BOMBA muestra una referencia de tres componentes y una tarjeta.
- MOTOR–CAJA–BOMBA muestra cinco componentes, dos acoples y dos tarjetas.
- FIN-FAN y VENTILADORES no muestran la operación de alineación.
- La pantalla rechaza equipos no elegibles si se intenta abrir directamente.
- Se mantienen las reglas de coma, signo y dos decimales.
- El guardado sigue siendo local y la subida sigue siendo únicamente por USB.
- Las pruebas actuales de contrato de base de datos y sincronización continúan
  pasando.
