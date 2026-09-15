@echo off
setlocal
title SCV-PTBG - Build APK Android

set "PROJECT=%~dp0"
set "FLUTTER=flutter"
if exist "C:\flutter\bin\flutter.bat" set "FLUTTER=C:\flutter\bin\flutter.bat"
if exist "%USERPROFILE%\Documents\Codex\.tools\flutter\bin\flutter.bat" set "FLUTTER=%USERPROFILE%\Documents\Codex\.tools\flutter\bin\flutter.bat"
if exist "%USERPROFILE%\Documents\Codex\.tools\flutter_git\bin\flutter.bat" set "FLUTTER=%USERPROFILE%\Documents\Codex\.tools\flutter_git\bin\flutter.bat"

cd /d "%PROJECT%"
echo Actualizando el catalogo del APK desde MariaDB...
py -3 actualizar_catalogo_apk.py
if errorlevel 1 exit /b 1
call "%FLUTTER%" pub get
if errorlevel 1 exit /b 1
call "%FLUTTER%" build apk --release
if errorlevel 1 exit /b 1

echo APK generado en:
echo %PROJECT%build\app\outputs\flutter-apk\app-release.apk
