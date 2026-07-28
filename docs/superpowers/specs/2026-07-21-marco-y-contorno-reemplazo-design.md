# Marco y contorno del visor de reemplazo

## Objetivo

Hacer que el visor de componentes use el mismo lenguaje visual del visor de Vibracion y eliminar las lineas duplicadas cuando varias areas seleccionadas se superponen.

## Marco visual

El visor de reemplazo adopta los elementos principales de `EquipoPuntoViewer`:

- Fondo blanco exterior.
- Radio de 20 px.
- Borde `AppColors.borderDark` de 1.3 px.
- Sombra `AppColors.shadowMd`.
- Recorte `Clip.antiAlias`.
- Encabezado con gradiente horizontal `headerTop` a `headerBottom`.
- Area de imagen con fondo `Color(0xFFC9C9C9)`.

El encabezado muestra un icono de componentes, el texto `Componentes del equipo` y un indicador a la derecha:

- Sin seleccion: `Sin seleccionar`.
- Una seleccion: `1 seleccionado`.
- Varias selecciones: `<cantidad> seleccionados`.

La altura total permanece estable para no desplazar el formulario durante las transiciones.

## Union de contornos

### Causa del defecto

El pintor actual recorre cada rectangulo y dibuja su borde individualmente. Las regiones de componentes vecinos se superponen para evitar huecos visuales. Al seleccionar Motor + Caja o Caja + Bomba, los bordes de ambos rectangulos se dibujan dentro de la zona activa y producen lineas dobles.

### Solucion

Antes de pintar, todas las regiones activas se convierten a coordenadas del lienzo y se combinan mediante `PathOperation.union`.

- El recorte de la imagen enfocada usa el path combinado.
- El borde teal se dibuja una sola vez sobre el path combinado.
- Las lineas internas de zonas superpuestas desaparecen.
- Las regiones que no se tocan conservan contornos independientes dentro del mismo path, como las dos zonas del motor de Fin-Fan.

La operacion de union se centraliza en una funcion pura reutilizada por el clipper y el painter para impedir diferencias entre el area visible y su contorno.

## Estados existentes

- Sin seleccion, la imagen completa permanece normal y no se dibuja contorno.
- Con seleccion parcial, el fondo permanece aclarado y las regiones elegidas conservan contraste completo.
- Con todos los componentes seleccionados, la imagen completa permanece normal y no necesita contorno interno.
- Un error del asset conserva el fallback actual.

## Pruebas

- Dos rectangulos superpuestos producen un solo contorno exterior sin frontera interna.
- Dos rectangulos separados producen dos contornos.
- El clipper y el painter reciben el mismo path unido.
- El encabezado muestra el contador correcto para cero, una y varias selecciones.
- El visor conserva las claves de estado usadas por las pruebas actuales.
- Toda la suite Flutter y la compilacion ARM64 deben completarse antes de instalar.

## Fuera de alcance

- Cambiar las coordenadas de los componentes.
- Cambiar el nivel de aclarado.
- Modificar el visor de Vibracion.
- Escribir reemplazos en MariaDB.
