@echo off
echo ==============================================
echo   BeatBoss Debian Build (.deb)
echo ==============================================

echo This script must be run on Linux (e.g. Ubuntu, Debian) or WSL.
echo Windows requires 'fpm' or 'dpkg' tools which are native to Linux.

echo.
echo *** LINUX INSTRUCTIONS ***
echo 1. Install dependencies:
echo    sudo apt install python3-pip binutils ruby ruby-dev rubygems build-essential
echo    sudo gem install --no-document fpm
echo.
echo 2. Run PyInstaller:
echo    pyinstaller beatboss_linux.spec --clean
echo.
echo 3. Build .deb with FPM:
echo    mkdir -p dist/package/usr/bin
echo    cp -r dist/BeatBoss/* dist/package/usr/bin/
echo    fpm -s dir -t deb -n "beatboss" -v "1.4.0" -C dist/package .

echo.
pause
