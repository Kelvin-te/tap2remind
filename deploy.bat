@echo off
echo Building Tap2Remind for Android...
echo.

REM Check if Flutter is available
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter not found in PATH!
    echo Please install Flutter from https://flutter.dev/docs/get-started/install/windows
    echo and add it to your PATH.
    pause
    exit /b 1
)

REM Get dependencies
echo Getting dependencies...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to get dependencies
    pause
    exit /b 1
)

REM Build APK
echo Building release APK...
flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to build APK
    pause
    exit /b 1
)

echo.
echo SUCCESS! APK built successfully.
echo Location: build\app\outputs\flutter-apk\app-release.apk
echo.
echo You can now install this APK on any Android device.
pause
