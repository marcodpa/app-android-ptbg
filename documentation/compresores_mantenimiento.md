# Ultimo mantenimiento de compresores

El control de mantenimiento se resuelve por tarea: lubricacion, inhibidores,
filtro de aire y aceite/filtro pueden tener fechas distintas.

- SI registra la nueva fecha, horometro y observacion de esa tarea.
- NO guarda esa tarea vacia; la pantalla y la impresion consultan la ultima
  fila con fecha u horas del mismo compresor. No se registra otra vez como
  un mantenimiento nuevo.
- Sin antecedente se muestra "Sin registro previo". No se inventan datos.
- Una planilla historica solo toma antecedentes hasta su fecha y hora, no
  trabajos futuros. Se conserva la fecha de la inspeccion en la cabecera y
  la fecha real del mantenimiento en el control.
- Los datos de una tarea se recuperan juntos: no se mezcla una fecha nueva
  con horas u observaciones de una tarea vieja.

El uploader descarga todas las planillas de compresores, no solo la ultima:
una tablet nueva necesita los antecedentes aunque las ultimas inspecciones
no tengan mantenimiento. Mantiene intactos los pendientes locales y actualiza
las copias sincronizadas con las correcciones de MariaDB.

Para imprimir, el uploader lee la planilla elegida y su historial de MariaDB.
El generador completa una copia en memoria; no actualiza ni inserta registros
en MariaDB por imprimir. Las planillas antiguas que ya traian datos copiados
siguen siendo compatibles y no se reescriben.

Instalar el APK actualizado, cerrar y abrir el uploader seguro actualizado y
realizar la descarga USB para disponer de los antecedentes en la tablet.
