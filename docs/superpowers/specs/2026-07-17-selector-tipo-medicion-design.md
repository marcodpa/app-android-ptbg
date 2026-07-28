# Selector de tipo de medicion

## Objetivo

Agregar una seleccion de modulo despues de escanear un QR y pulsar `Iniciar medicion`, sin cambiar el flujo actual de busqueda ni los datos del equipo.

## Flujo

1. El usuario inicia sesion y escanea el QR como hasta ahora.
2. La app muestra el equipo encontrado y el boton `Iniciar medicion`.
3. Al pulsar el boton, abre la pantalla `Tipo de medicion` con cuatro opciones: Lubricacion, Alineacion, Temperatura y Vibracion.
4. Vibracion abre la captura existente con el mismo equipo escaneado.
5. Los otros tres modulos muestran el aviso `Modulo proximamente disponible` y permanecen en el selector.
6. El boton de regreso vuelve a la vista previa del equipo escaneado.

## Interfaz

La nueva pantalla usa el encabezado, colores, tipografia y espaciado existentes en la app. Cada modulo aparece como una opcion grande con icono, nombre y estado. Vibracion se muestra disponible; los demas incluyen la etiqueta `Proximamente`.

La interfaz debe funcionar en orientacion vertical, mantener areas tactiles amplias para tablet y no usar tarjetas anidadas.

## Arquitectura

- Crear una pantalla independiente para seleccionar el tipo de medicion.
- Registrar una ruta para abrir el selector recibiendo el `Equipo` escaneado.
- Cambiar exclusivamente la accion `Iniciar medicion` del escaner para abrir el selector.
- Reutilizar `CaptureScreen` sin modificar su logica de captura, guardado o sincronizacion.

## Estados y errores

- Si el selector no recibe un equipo valido, no debe iniciar ninguna captura y debe permitir regresar.
- Los modulos futuros no navegan a pantallas vacias; muestran una confirmacion breve de que aun no estan disponibles.
- Los toques repetidos no deben abrir multiples pantallas de captura.

## Pruebas

- Verificar que el selector presenta exactamente los cuatro modulos.
- Verificar que Vibracion abre `CaptureScreen` con el mismo equipo.
- Verificar que los otros modulos muestran el estado `Proximamente` y no abren la captura.
- Verificar que regresar conserva la vista previa del QR.
- Ejecutar las pruebas Flutter, el analisis estatico y compilar el APK Android ARM64 antes de instalarlo en la tablet.

## Fuera de alcance

No se implementan formularios, tablas, sincronizacion ni formatos de impresion para Lubricacion, Alineacion o Temperatura en esta fase.
