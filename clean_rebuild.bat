@echo off
echo [1/4] Killing background BeatBoss processes...
taskkill /F /IM BeatBoss.exe /T 2>nul
taskkill /F /IM python.exe /T 2>nul

echo [2/4] Removing old build/dist folders...
if exist build (
    rmdir /s /q build
)
if exist dist (
    rmdir /s /q dist
)

echo [3/4] Rebuilding with PyInstaller...
pyinstaller beatboss.spec --noconfirm

echo [4/4] Done!
pause
