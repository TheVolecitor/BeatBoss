#!/bin/bash

# BeatBoss AppImage Builder
# Creates a portable .AppImage file that works on most Linux distros.

APP_NAME="BeatBoss"
BUILD_DIR="AppDir_Build"
SOURCE_BIN="dist/BeatBoss"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

if [ ! -d "$SOURCE_BIN" ]; then
    echo "❌ Error: Build folder '$SOURCE_BIN' not found!"
    echo "   Run: python3 -m PyInstaller beatboss_linux.spec"
    exit 1
fi

echo "🏗️  Preparing AppDir..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin"

cp -r "$SOURCE_BIN"/* "$BUILD_DIR/usr/bin/"
cp assets/logo.png "$BUILD_DIR/beatboss.png"

# CRITICAL FIX: Find the 'flet' binary.
# 1. Search in the build directory (if bundled)
echo "🔍 Searching for flet binary..."
FLET_BIN=$(find "$BUILD_DIR/usr/bin" -type f -name "flet" | head -n 1)

# 2. Fallback: Check system/venv PATH (since PyInstaller often skips it)
if [ -z "$FLET_BIN" ]; then
    echo "⚠️  Not found in build. Checking system PATH..."
    SYS_FLET=$(which flet)
    if [ -n "$SYS_FLET" ]; then
        echo "✅ Found system flet at: $SYS_FLET"
        FLET_BIN="$SYS_FLET"
    fi
fi

if [ -n "$FLET_BIN" ]; then
    # Only copy if it's not already in the destination
    if [ "$FLET_BIN" != "$BUILD_DIR/usr/bin/flet" ]; then
        echo "📦 Copying flet binary to AppImage..."
        cp "$FLET_BIN" "$BUILD_DIR/usr/bin/flet"
        chmod +x "$BUILD_DIR/usr/bin/flet"
    fi
    echo "✅ Flet binary ready at usr/bin/flet"
else
    echo "❌ ERROR: Could not find 'flet' binary! The AppImage will crash."
    echo "   Please ensure 'flet' is installed in your venv: pip install flet"
fi

# Download AppImageTool if missing
if [ ! -f "appimagetool-x86_64.AppImage" ]; then
    echo "⬇️  Downloading appimagetool..."
    wget -q "$TOOL_URL" -O appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
fi

# Create AppRun
echo "🔗 Creating AppRun..."
cat > "$BUILD_DIR/AppRun" <<EOF
#!/bin/sh
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/bin:\${LD_LIBRARY_PATH}"
# Note: We do NOT set FLET_VIEW_PATH, letting Flet find its own binary relative to the executable.
exec "\${HERE}/usr/bin/BeatBoss" "\$@"
EOF
chmod +x "$BUILD_DIR/AppRun"

# Create Desktop Entry
echo "📝 Creating Desktop File..."
cat > "$BUILD_DIR/beatboss.desktop" <<EOF
[Desktop Entry]
Name=BeatBoss
Exec=AppRun
Icon=beatboss
Type=Application
Categories=AudioVideo;Audio;Music;
Comment=Modern Music Player
Terminal=false
StartupWMClass=BeatBoss
EOF

# Build
echo "🔨 Building AppImage..."
# Use ARCH=x86_64 to avoid detection errors
ARCH=x86_64 ./appimagetool-x86_64.AppImage "$BUILD_DIR"

echo "✅ Success! BeatBoss-x86_64.AppImage created."
