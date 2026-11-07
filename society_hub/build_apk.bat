@echo off
REM Builds a release APK for SocietyHub.
REM Output: build\app\outputs\flutter-apk\app-release.apk
REM Full log: build_log.txt
cd /d "%~dp0"
if not exist ".env" (
  echo ERROR: .env is missing. Copy .env.example to .env and fill in Supabase values.
  pause
  exit /b 1
)
echo Building... full log in build_log.txt
REM Stop build helpers left over from earlier runs (they hold lots of memory).
pushd android
call gradlew.bat --stop >nul 2>&1
popd
echo ==== flutter doctor ==== > build_log.txt
call flutter doctor -v >> build_log.txt 2>&1
echo ==== flutter clean ==== >> build_log.txt
call flutter clean >> build_log.txt 2>&1
echo ==== flutter pub get ==== >> build_log.txt
call flutter pub get >> build_log.txt 2>&1 || goto :fail
echo ==== flutter build apk ==== >> build_log.txt
call flutter build apk --release --obfuscate --split-debug-info=build\debug-info >> build_log.txt 2>&1 || goto :fail
echo ==== BUILD OK ==== >> build_log.txt
echo.
echo Done: build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0
:fail
echo ==== BUILD FAILED ==== >> build_log.txt
echo BUILD FAILED - see build_log.txt
pause
exit /b 1
