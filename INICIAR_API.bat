@echo off
title SCV-PTBG API
cd /d "%~dp0"

set "API_PYTHON=%~dp0..\work\api-venv\Scripts\python.exe"

if not exist "%API_PYTHON%" (
  echo No se encontro el entorno Python de la API.
  echo Ruta esperada: %API_PYTHON%
  echo.
  pause
  exit /b 1
)

netstat -ano | findstr /R /C:":8001 .*LISTENING" >nul
if not errorlevel 1 (
  echo La API ya esta encendida en el puerto 8001.
  start "" "http://127.0.0.1:8001/docs"
  echo.
  pause
  exit /b 0
)

echo Iniciando SCV-PTBG API en el puerto 8001...
echo Para detenerla, cierre esta ventana o presione Ctrl+C.
echo.
"%API_PYTHON%" Api_scv_ptbg.py

echo.
echo La API se detuvo.
pause
