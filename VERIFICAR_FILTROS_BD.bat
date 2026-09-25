@echo off
cd /d "%~dp0"
py -3 verificar_filtros_bd.py --pedir-clave --salida output\validacion_filtros_bd.json
pause
