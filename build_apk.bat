@echo off
title SCV-PTBG — Build APK Android
color 0B

echo.
echo ================================================
echo   SCV-PTBG — Compilando APK Android
echo ================================================
echo.

set FLUTTER=C:\flutter\bin\flutter.bat
set PROJECT=C:\Users\home-it\Downloads\scv_ptbg_flutter\scv_ptbg

cd /d %PROJECT%

echo Compilando APK...
call %FLUTTER% build apk --release
if errorlevel 1 ( echo ERROR en build APK & pause & exit )

echo.
echo ================================================
echo   APK generado en:
echo   build\app\outputs\flutter-apk\app-release.apk
echo ================================================
echo.

explorer build\app\outputs\flutter-apk\
pause
