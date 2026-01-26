@echo off
echo ========================================
echo   BeatBoss Flet Rebuild Utility
echo ========================================

echo [1/3] Cleaning old build files...
if exist build rd /s /q build
if exist dist rd /s /q dist

echo.
echo [2/3] Building for Windows...
flet build windows --main main_flet.py --product "BeatBoss" --assets assets

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Build FAILED. Please check the errors above.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [3/3] Build SUCCESSFUL!
echo Output located in: dist\windows
echo.
pause
