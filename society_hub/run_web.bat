@echo off
REM Runs SocietyHub with Flutter in Chrome (flutter run -d chrome).
REM Log: run_log.txt   Stop: close this window.
cd /d "%~dp0"
echo Starting SocietyHub with Flutter in Chrome... (first start takes 1-3 minutes)
echo Log: run_log.txt - close this window to stop.
call flutter pub get > run_log.txt 2>&1
call flutter run -d chrome >> run_log.txt 2>&1
echo ==== STOPPED ==== >> run_log.txt
echo Stopped - see run_log.txt
pause
