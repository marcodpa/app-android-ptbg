@echo off
title SCV-PTBG — Build y Deploy
color 0A

echo.
echo ================================================
echo   SCV-PTBG — Build automatico
echo ================================================
echo.

set FLUTTER=C:\flutter\bin\flutter.bat
set PROJECT=C:\Users\home-it\Downloads\scv_ptbg_flutter\scv_ptbg

cd /d %PROJECT%

echo [1/3] Compilando Flutter Web...
call %FLUTTER% build web --release
if errorlevel 1 ( echo ERROR en build web & pause & exit )
echo OK - Web compilado

echo.
echo [2/3] Web listo en build\web
echo       La API ya sirve los archivos automaticamente.
echo.

echo [3/3] Reiniciando API...
taskkill /F /IM python.exe /T >nul 2>&1
timeout /t 2 /nobreak >nul
start "SCV-PTBG API" cmd /k "cd /d %PROJECT% && python Api_scv_ptbg.py"

echo.
echo ================================================
echo   LISTO
echo   Abri: http://192.168.100.241:8001
echo ================================================
echo.
pause
