# SCV-PTBG - Subidor USB desde laptop

Este flujo evita sincronizar desde la tablet por WiFi.

La tablet solo captura mediciones y las guarda en su base local. La subida a
MariaDB se hace desde la laptop del usuario mediante USB.

## Requisitos en la laptop

- Python instalado.
- Android Platform Tools instalado o `adb.exe` disponible.
- Acceso de red desde la laptop a MariaDB `172.16.200.2:3306`.
- Tablet conectada por USB, desbloqueada y con depuracion USB autorizada.

## Configuracion de MariaDB

Las credenciales no se guardan en Git. Antes de abrir el programa, definir las
variables de entorno indicadas en `.env.example`. Como minimo:

```bat
set SCV_DB_PASSWORD=clave_local
abrir_subidor_usb.bat
```

Para dejarla configurada en Windows se puede usar
`setx SCV_DB_PASSWORD "clave_local"` y luego abrir una terminal nueva.

## Uso

1. Conectar la tablet a la laptop por USB.
2. Abrir `abrir_subidor_usb.bat`.
3. Presionar `Detectar tablet`.
4. Revisar la cantidad de mediciones pendientes.
5. Presionar `Subir pendientes`.
6. Esperar las confirmaciones:
   - `Subida confirmada`: se inserto en MariaDB y se marco como sincronizada en la tablet.
   - `Ya existia en MariaDB`: ya estaba cargada y se marca como sincronizada en la tablet.
   - `Error subiendo`: no se marco como sincronizada y queda pendiente.

## Importante

- No se usa WiFi de la tablet para subir.
- No se usa el endpoint `/mediciones` del API para sincronizar.
- La conexion a MariaDB sale desde la laptop donde se abre el programa.
- Si la laptop no puede llegar a `172.16.200.2:3306`, la subida fallara aunque la tablet este bien conectada.
