# Enfoque visual para reemplazo de componentes

## Objetivo

Mostrar la ilustracion preestablecida del conjunto durante un reemplazo y mantener con contraste normal solo los componentes seleccionados. Los componentes que no seran reemplazados se muestran mucho mas claros.

## Comportamiento

- La ilustracion aparece antes de la lista de componentes.
- Sin componentes seleccionados, toda la ilustracion se muestra con contraste normal.
- Con al menos un componente seleccionado, la ilustracion completa se muestra aclarada.
- Encima de la ilustracion aclarada se vuelven a dibujar al 100% solo las areas correspondientes a los componentes seleccionados.
- La seleccion multiple conserva normales todas las areas elegidas y aclara exclusivamente las no elegidas.
- Quitar una seleccion actualiza el efecto inmediatamente.
- La pantalla de revision muestra el mismo enfoque correspondiente a la seleccion final.

## Imagenes y composiciones

La imagen se obtiene desde `EquipoVisualResolver.fromEquipo(equipo).cleanAsset`, por lo que conserva la misma clasificacion oficial mediante `MOT_EQUIPO.PUNTOS` que usa la captura de vibracion.

Cada configuracion visual tendra un mapa normalizado de areas por componente:

- PUNTOS 1, 2, 3, 7, 8 y 9: Motor y Bomba.
- PUNTOS 4 y 5: Motor y Ventilador.
- PUNTOS 6: Motor, Caja y Bomba.

Las areas usan coordenadas relativas entre 0 y 1 para adaptarse al tamano disponible en diferentes tablets. El mapa se asocia con el identificador visual del conjunto y no con el nombre escrito del equipo.

Los futuros tipos Solo Motor o Motor + Caja se incorporaran agregando su composicion, imagen y areas normalizadas sin modificar el widget de enfoque.

## Renderizado

El visor utiliza una proporcion estable para evitar saltos en el formulario:

1. Dibuja la imagen completa.
2. Cuando existe seleccion, aplica una capa blanca con opacidad 0.78 sobre la imagen de fondo.
3. Dibuja nuevamente la imagen original recortada por la union de las areas seleccionadas.
4. Agrega un borde teal discreto alrededor de cada area activa para que sus limites sean reconocibles sin tapar la ilustracion.

La imagen usa `BoxFit.contain`. Las coordenadas del recorte se calculan sobre el rectangulo real ocupado por la imagen, no sobre los margenes vacios del contenedor.

## Arquitectura

- `ReplacementVisualLayout`: define el asset y las regiones normalizadas de cada componente para un tipo visual.
- `ReplacementVisualResolver`: traduce `Equipo.ptEq` a un layout soportado.
- `ReplacementFocusImage`: widget independiente que recibe el equipo y el conjunto de componentes seleccionados.
- `ReplacementScreen`: reutiliza el widget en captura y revision; no contiene coordenadas ni logica de recorte.

El resolver visual y el resolver de componentes deben coincidir. Si un componente esta disponible para seleccion pero no tiene region visual, el visor muestra la imagen completa normal y un aviso no bloqueante; nunca oculta toda la imagen ni inventa una region.

## Accesibilidad y estados

- La imagen es un apoyo visual; los nombres y controles de seleccion continuan disponibles como texto.
- El efecto no depende solo del color: el componente activo conserva contraste y recibe contorno.
- Un error al cargar el asset muestra el icono del equipo y permite continuar llenando el formulario.
- La transicion entre selecciones dura 180 ms y no bloquea los controles.

## Pruebas

- Cada valor conocido de `PUNTOS` resuelve el asset y los componentes visuales correctos.
- PUNTOS 6 contiene regiones independientes para Motor, Caja y Bomba.
- PUNTOS 4 y 5 contienen Motor y Ventilador.
- La seleccion multiple produce la union de todas las regiones elegidas.
- Sin seleccion se dibuja la imagen completa sin aclarado.
- Con seleccion se dibuja el fondo aclarado y las regiones activas normales.
- La captura y la revision de reemplazo muestran el mismo visor.
- Los formularios, validaciones y flujo de operaciones existentes siguen pasando sus pruebas.

## Fuera de alcance

- Crear nuevos dibujos de equipos.
- Modificar las imagenes usadas por la captura de vibracion.
- Guardar reemplazos en MariaDB.
- Agregar la composicion Solo Motor o Motor + Caja antes de recibir su identificacion oficial.
