@echo off
rem Abre la herramienta para colocar los equipos en el plano.
rem Doble clic desde el Explorador de Windows.
rem
rem Se usa un .bat y no el comando suelto porque asi la ventana corre en la
rem sesion de escritorio del usuario. Lanzada desde otro sitio el programa
rem arranca pero no tiene donde dibujarse, y parece que no hizo nada.

cd /d "%~dp0"
title Ubicar equipos en el plano - SCV-PTBG

echo.
echo   Abriendo el plano...
echo.

python ubicar_equipos.py
if errorlevel 1 goto error
goto fin

:error
echo.
echo   ============================================================
echo    No se pudo abrir. El error esta justo arriba.
echo    Copie ese texto y pasemelo.
echo   ============================================================
echo.
pause
exit /b 1

:fin
