@echo off
cd /d "%~dp0"
py -3 -m pip install -r requirements_tablet_uploader.txt
start "SCV-PTBG USB Status" /min py -3 tablet_uploader.py --status-daemon
py -3 tablet_uploader.py
pause
