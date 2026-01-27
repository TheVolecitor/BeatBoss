@echo off
echo ==============================================
echo   BeatBoss Windows Build (PyInstaller)
echo ==============================================

echo [1/2] Cleaning previous builds...
rmdir /s /q build dist

echo [2/2] Running PyInstaller...
pyinstaller beatboss.spec --clean --noconfirm

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build Failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ==============================================
echo   Build Success! 
echo   Executable is in: dist/BeatBoss/BeatBoss.exe
echo ==============================================
pause
