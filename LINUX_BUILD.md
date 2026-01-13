# Linux Build Guide & Setup

This guide explains how to set up the development environment and package BeatBoss as a standalone executable for Linux.

## 5. (Advanced) Bundling VLC with the App

If you want the app to work **without** asking users to install VLC, you must bundle the libraries manually.

### 1. Gather the Libraries
Run these commands to create a local copy of your system's VLC:

```bash
# Create a local folder for bundling
mkdir -p vlc_bundle/lib
mkdir -p vlc_bundle/plugins

# Copy libraries (paths might vary slightly by distro, these are for Debian/Kali/Ubuntu)
cp /usr/lib/x86_64-linux-gnu/libvlc.so.* vlc_bundle/lib/
cp /usr/lib/x86_64-linux-gnu/libvlccore.so.* vlc_bundle/lib/

# Copy Plugins (Crucial!)
cp -r /usr/lib/x86_64-linux-gnu/vlc/plugins/* vlc_bundle/plugins/
```

### 2. Update `beatboss_linux.spec`
Modify your spec file to include this `vlc_bundle` directory.

```python
# Add this to your datas list
a = Analysis(
    ['main_build.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('assets', 'assets'),
        ('vlc_bundle', 'vlc_bundle') # <--- Bundle the folder
    ],
    hiddenimports=['flet'], # FORCE INCLUDE FLET
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    runtime_hooks=[],
    excludes=['winrt', 'winrt.windows.media'], # Exclude ONLY winrt, keep windows_media.py!
    noarchive=False,
)
```

### 3. Update `player.py` (If not already done)
Ensure your `_setup_vlc_path` checks for `vlc_bundle/lib/libvlc.so`. The current code searches `_internal` and `app_dir`, so you might need to point `PYTHON_VLC_LIB_PATH` to the bundled path inside `main_build.py` or `player.py` if it doesn't auto-detect.

*Warning: Bundled Linux libraries might not work on other distributions (e.g., Ubuntu libraries on Fedora) due to libc version differences.*

## 1. System Requirements

Unlike Windows, we rely on the system's package manager for media libraries.

### Install System Dependencies (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install -y vlc libvlc-dev ffmpeg libmpv-dev libmpv2 python3-pip python3-venv python3-tk
```
*   **vlc / libvlc-dev**: Required for the audio engine.
*   **ffmpeg**: Required for converting local files (WAV/MP3).
*   **libmpv-dev**: Required by Flet for its internal video components.

## 2. Python Environment Setup

Set up your virtual environment and install project dependencies.

```bash
# 1. Create virtual environment
python3 -m venv venv

# 2. Activate it
source venv/bin/activate

# 3. Install requirements
# Note: This will automatically skip Windows-only packages (winrt)
pip install -r requirements.txt
```

### Running the App Locally
```bash
python3 main_build.py
```

---

## 3. Building for Distribution (PyInstaller)

We use PyInstaller to create a standalone binary.

### Create the Linux Spec File (`beatboss_linux.spec`)

Save the following content as `beatboss_linux.spec` in the project root:

```python
# beatboss_linux.spec
# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['main_build.py'],
    pathex=[],
    binaries=[],
    datas=[('assets', 'assets')],
    hiddenimports=['flet'], # FORCE INCLUDE FLET
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    runtime_hooks=[],
    excludes=['winrt', 'winrt.windows.media'], # Exclude ONLY winrt, keep windows_media.py!
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='BeatBoss',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True, # Debug: Set to True to see why it crashes!
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['assets/logo.png'], # Use PNG for Linux
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='BeatBoss',
)
```

### Build the Application
**Critical:** Run PyInstaller via `python -m` to ensure it sees your venv packages!

```bash
python3 -m PyInstaller beatboss_linux.spec
```

### 4. Creating a Native Installer (.deb)

For a professional install experience (like installing Chrome or Steam), we use a `.deb` package. This automatically creates the **Desktop Shortcut** and installs the app to the system.

1.  **Build the app first:**
    ```bash
    ./bundle_linux_vlc.sh
    python3 -m PyInstaller beatboss_linux.spec
    ```

2.  **Run the DEB Builder script:**
    ```bash
    chmod +x build_deb.sh
    ./build_deb.sh
    ```

3.  **Install it:**
    You will get a file like `beatboss_1.2.0_amd64.deb`.
    ```bash
    sudo apt install ./beatboss_1.2.0_amd64.deb
    ```

Once installed, you can find "BeatBoss" in your **System Menu** and pin it to your dock!

### 5. Packaging as AppImage


For a single-file portable executable that works on most Linux distros:

1.  **Download appimagetool**:
    ```bash
    wget https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
    ```

2.  **Create AppDir Structure**:
    ```bash
    mkdir -p BeatBoss.AppDir/usr/bin
    cp -r dist/BeatBoss/* BeatBoss.AppDir/usr/bin/
    # IMPORTANT: Icon must be named exactly 'beatboss.png' to match the desktop file
    cp assets/logo.png BeatBoss.AppDir/beatboss.png
    ```

3.  **Create `BeatBoss.desktop`**:
    Save this in `BeatBoss.AppDir/beatboss.desktop`:
    ```ini
    [Desktop Entry]
    Name=BeatBoss
    Exec=AppRun
    Icon=beatboss
    Type=Application
    Categories=AudioVideo;Audio;Music;
    Comment=BeatBoss Music Player
    Terminal=false
    ```

4.  **Create `AppRun`**:
    Save this in `BeatBoss.AppDir/AppRun`:
    ```bash
    #!/bin/sh
    SELF=$(readlink -f "$0")
    HERE=${SELF%/*}
    export PATH="${HERE}/usr/bin:${PATH}"
    export LD_LIBRARY_PATH="${HERE}/usr/bin:${LD_LIBRARY_PATH}"
    export FLET_VIEW_PATH="${HERE}/usr/bin"
    exec "${HERE}/usr/bin/BeatBoss" "$@"
    ```
    Make it executable:
    ```bash
    chmod +x BeatBoss.AppDir/AppRun
    ```

5.  **Build It**:
    ```bash
    # Verify strict mode is off to avoid minor validation errors
    ARCH=x86_64 ./appimagetool-x86_64.AppImage BeatBoss.AppDir
    ```

