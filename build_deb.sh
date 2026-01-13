#!/bin/bash

# BeatBoss DEB Package Builder
# Creates a .deb installer that sets up shortcuts automatically.

APP_NAME="beatboss"
VERSION="1.2.0"
ARCH="amd64"
OUTPUT_DIR="deb_build"
SOURCE_BIN="dist/BeatBoss"

if [ ! -d "$SOURCE_BIN" ]; then
    echo "❌ Error: Build folder '$SOURCE_BIN' not found!"
    echo "   Run: python3 -m PyInstaller beatboss_linux.spec"
    exit 1
fi

echo "🏗️  Preparing DEB directory structure..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/DEBIAN"
mkdir -p "$OUTPUT_DIR/opt/$APP_NAME"
mkdir -p "$OUTPUT_DIR/usr/bin"
mkdir -p "$OUTPUT_DIR/usr/share/applications"
mkdir -p "$OUTPUT_DIR/usr/share/icons/hicolor/512x512/apps"

echo "📦 Copying application files..."
cp -r "$SOURCE_BIN"/* "$OUTPUT_DIR/opt/$APP_NAME/"

echo "🔗 Creating executable symlink..."
# Create a wrapper script in /usr/bin provided by the package
cat > "$OUTPUT_DIR/usr/bin/$APP_NAME" <<EOF
#!/bin/sh
exec /opt/$APP_NAME/BeatBoss "\$@"
EOF
chmod +x "$OUTPUT_DIR/usr/bin/$APP_NAME"

echo "🎨 Installing icon..."
cp assets/logo.png "$OUTPUT_DIR/usr/share/icons/hicolor/512x512/apps/$APP_NAME.png"

echo "📝 Creating Desktop Shortcut..."
cat > "$OUTPUT_DIR/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=BeatBoss
Comment=Modern Desktop Music Player
Exec=/usr/bin/$APP_NAME
Icon=$APP_NAME
Type=Application
Terminal=false
Categories=AudioVideo;Audio;Music;Player;
StartupWMClass=BeatBoss
EOF

echo "📄 Creating Control file..."
cat > "$OUTPUT_DIR/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: BeatBoss Team <support@beatboss.app>
Description: A modern, lightweight music player.
 Built with Python, Flet, and VLC.
EOF

echo "🔨 Building .deb package..."
dpkg-deb --build "$OUTPUT_DIR" "${APP_NAME}_${VERSION}_${ARCH}.deb"

echo "✅ Success! Installer created: ${APP_NAME}_${VERSION}_${ARCH}.deb"
echo "   Install with: sudo apt install ./ ${APP_NAME}_${VERSION}_${ARCH}.deb"
