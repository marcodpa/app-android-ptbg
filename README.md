# STER — Sistema de Trazabilidad de Equipos Rotativos

Aplicacion Flutter para inspeccion de equipos rotativos. Permite trabajar sin
red en la tablet y guardar localmente:

- Mediciones de vibracion.
- Reemplazos de equipos.
- Mediciones de temperatura en grados Celsius.
- Alineacion MOTOR-BOMBA y MOTOR-CAJA-BOMBA.

Las mediciones pendientes se suben exclusivamente desde una laptop conectada
a la tablet mediante USB/ADB. La tablet no envia mediciones por red ni por API.

## Continuar el desarrollo en otra laptop

1. Instalar Git LFS, Flutter, Android SDK y Python 3.
2. Clonar el repositorio y ejecutar `git lfs pull`.
3. Ejecutar `flutter pub get`.
4. Conectar una tablet y usar `flutter install`, o instalar
   `build/app/outputs/flutter-apk/app-debug.apk`.
5. Configurar las variables descritas en `.env.example` antes de abrir el
   subidor USB.

## Verificacion

```text
flutter test
py -3 -m unittest test_tablet_uploader.py
```
