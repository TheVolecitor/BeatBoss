@echo off
echo ==============================================
echo   BeatBoss AppImage Build
echo ==============================================
echo This script must be run on Linux (e.g. Ubuntu, Fedora) or WSL.
echo Windows cannot build Linux applications directly.

echo.
echo *** LINUX INSTRUCTIONS ***
echo 1. Install dependencies:
echo    sudo apt install python3 python3-pip binutils appimagetool
echo.
echo 2. Run PyInstaller:
echo    pyinstaller beatboss_linux.spec --clean
echo.
echo 3. Package AppImage:
echo    mkdir -p dist/AppDir/usr/bin
echo    cp -r dist/BeatBoss/* dist/AppDir/usr/bin/
echo    appimagetool dist/AppDir
echo.
pause
