@echo off
cd /d "%~dp0"
py -3 -m pip install -r requirements_tablet_uploader.txt
py -3 abrir_subidor_seguro.py
pause
