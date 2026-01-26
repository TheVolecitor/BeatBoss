# BeatBoss

[**Download Latest Release**](https://github.com/TheVolecitor/BeatBoss/releases)

BeatBoss is a modern, cross-platform music player built with Python and Flet.
Designed for a premium experience on both Desktop (Windows/Linux) and Mobile (Android).

## Features
*   ✨ **Streaming**: Stream from public music sources.
*   📜 **Lyrics**: Real-time lyrics integration.
*   📂 **Local Playback**: Play your downloaded tracks seamlessly.
*   📱 **Mobile Optimized**: Clean 3-row player layout with collapse/expand support.
*   🔄 **Sync**: Shuffle, Repeat, and Playback state synced across all platforms.
*   🎨 **Dark Mode**: Sleek, glassmorphism-inspired UI.

## Prerequisites

### For End Users
Just download and run the latest installer! No external setup required.

### For Developers
1. **Python 3.10+**
2. **Flutter SDK** (Required for building standalone apps)
3. **Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Installation & Development

1.  **Clone the repository**
    ```bash
    git clone https://github.com/TheVolecitor/BeatBoss.git
    cd BeatBoss
    ```

2.  **Run in Debug Mode**
    ```bash
    python main_build.py
    ```

## Building the Application

BeatBoss uses the `flet build` system for easy packaging.

### 1. Build for Windows
This creates a standalone executable in `dist/windows`.
```bash
flet build windows --main main_build.py --product "BeatBoss" --assets assets
```

### 2. Build for Android (APK)
This creates a mobile-ready APK in `dist/apk`.
```bash
flet build apk --main main_build.py --product "BeatBoss" --org "com.volecitor" --assets assets
```

> [!TIP]
> Use the provided `flet_rebuild.bat` on Windows to clean and rebuild with a single click.

## Legal Disclaimer

BeatBoss does not host, store, or distribute copyrighted content. It functions as a client-side player for publicly available streams. All rights belong to the respective content owners.
