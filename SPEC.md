# BeatBoss - Technical Specification

## Project Overview

| Property | Value |
|----------|-------|
| **Name** | BeatBoss |
| **Version** | 1.4.0 |
| **Framework** | Flet (Python + Flutter) |
| **Platforms** | Windows, Android, Linux, Web |
| **Author** | TheVolecitor |
| **License** | MIT |

---

## System Requirements

### Runtime Requirements

| Platform | Minimum Requirements |
|----------|---------------------|
| Windows | Windows 10/11 64-bit, 4GB RAM |
| Android | Android 7.0+ (API 24), ARM64/x86_64 |
| Linux | Ubuntu 20.04+, Debian 11+, 4GB RAM |
| Web | Modern browser (Chrome 90+, Firefox 88+, Edge 90+) |

### Build Requirements

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.10+ | Runtime |
| Flet | 0.80.4 | UI Framework |
| Flutter | 3.38+ | Build toolchain |
| Visual Studio | 2022+ | Windows compilation |
| Android SDK | 33+ | Android builds |
| Inno Setup | 6.x | Windows installer |

---

## Application Architecture

```
beatboss/
├── src/
│   ├── main.py              # Application entry point
│   ├── main_flet.py         # Flet UI implementation
│   ├── player.py            # Audio playback engine
│   ├── player_flet.py       # Flet-integrated player controls
│   └── assets/              # Icons, images
│       ├── icon.ico         # Windows icon
│       ├── icon_android.png # Android adaptive icon
│       └── ...
├── pyproject.toml           # Project configuration
├── build_*.bat              # Platform build scripts
└── installer/
    └── beatboss_setup.iss   # Inno Setup script
```

---

## Dependencies

### Python Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flet | >=0.25.0 | Cross-platform UI |
| flet_audio | >=0.1.0 | Audio playback |
| requests | latest | HTTP client |
| urllib3 | latest | URL handling |
| google-api-python-client | latest | YouTube API |
| pynput | latest | Global hotkeys |
| colorama | latest | Console colors |
| python-dotenv | latest | Environment variables |
| winrt-Windows-Media | latest | Windows media controls |
| winrt-Windows-Storage-Streams | latest | Windows storage |
| winrt-Windows-Foundation | latest | Windows foundation |

### Flutter Dependency Overrides

| Package | Version | Reason |
|---------|---------|--------|
| file_picker | 8.1.4 | Compatibility with Flet 0.80.4 |

---

## Build Outputs

### Windows Build
- **Location**: `build/flutter/build/windows/x64/runner/Release/`
- **Executable**: `beatboss.exe`
- **Size**: ~50MB (includes Python runtime)
- **Dependencies**: All DLLs bundled

### Windows Installer
- **Location**: `installer/BeatBoss_Setup_1.4.0.exe`
- **Format**: Inno Setup
- **Features**: Start menu, desktop shortcut, uninstaller

### Android Build
- **Location**: `dist/apk/`
- **Format**: APK
- **Target**: API 24+ (Android 7.0+)

### Linux Build
- **Location**: `dist/linux/`
- **Format**: Executable bundle

### Web Build
- **Location**: `dist/web/`
- **Format**: Static files (HTML/JS/CSS)

---

## Features

### Core Features
- [x] Music playback (MP3, WAV, FLAC, OGG)
- [x] YouTube audio streaming
- [x] Playlist management
- [x] Global media hotkeys
- [x] Windows media integration
- [x] Dark/Light theme

### Platform-Specific
- [x] Windows: Taskbar media controls
- [x] Android: Background playback
- [x] Web: Progressive web app

---

## API Keys Required

| Service | Environment Variable | Purpose |
|---------|---------------------|---------|
| YouTube Data API v3 | `YOUTUBE_API_KEY` | Search and metadata |

---

## Build Commands

```bash
# Windows
.\build_beatboss.bat

# Android
.\build_android.bat

# Linux
.\build_linux.bat

# Web
.\build_web.bat

# Windows Installer
.\build_installer.bat
```

---

## Known Issues

1. **Flutter path with spaces**: Flet cannot use Flutter SDK from paths containing spaces. Solution: Use `C:\Project\Flutter\` instead.

2. **file_picker v10.x incompatibility**: Flet 0.80.4 uses deprecated `FilePicker.platform` API. Solution: Pin `file_picker: 8.1.4` in `pyproject.toml`.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.4.0 | 2026-01-27 | Multi-platform build scripts, Inno Setup installer |
| 1.3.0 | 2026-01-20 | YouTube integration |
| 1.2.0 | 2026-01-15 | Flet UI redesign |
| 1.1.0 | 2026-01-10 | Audio player core |
| 1.0.0 | 2026-01-01 | Initial release |

---

*Generated: 2026-01-27*
