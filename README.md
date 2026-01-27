# BeatBoss

[Download Latest Release](https://github.com/TheVolecitor/BeatBoss/releases)

BeatBoss is a modern, cross-platform music player built with Python and Flet.
Designed for a premium experience on Desktop (Windows/Linux) and Mobile (Android).

## Project Structure
```
📁 .
├── 📁 src              # Source code and assets
│   ├── 📁 assets       # Icons and media
│   └── main.py         # Entry point
├── pyproject.toml      # Project configuration
└── README.md
```

## Features
- Streaming: Stream from public music sources.
- Lyrics: Real-time lyrics integration.
- Local Playback: Play downloaded tracks seamlessly.
- Mobile Optimized: Clean 3-row player layout with collapse/expand support.
- State Sync: Shuffle, Repeat, and Playback state synced across all platforms.
- Dark/Light Mode: Sleek, glassmorphism-inspired UI.

## Prerequisites

### For End Users
Download and run the latest installer for your platform. No external dependencies required.

### For Developers
1. Python 3.10+
2. Flutter SDK (Required for building standalone apps)
3. Dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Installation and Development

1. Clone the repository:
   ```bash
   git clone https://github.com/TheVolecitor/BeatBoss.git
   cd BeatBoss
   ```

2. Run in Debug Mode:
   Since the project is now configured with `pyproject.toml`, you can simply run:
   ```bash
   flet run
   ```
   (Alternatively: `flet run src/main.py`)

## ⚙️ Configuration (Optional but Recommended)
> [!IMPORTANT]
> **To enable YouTube Music features, you must provide your own API Key.**

Before building, edit `src/main.py` and replace the placeholder key:

```python
# src/main.py
YT_API_KEY = "youtube api key here"
```
*Get a key from the [Google Cloud Console](https://console.cloud.google.com/).*

## Building the Application

BeatBoss uses the Flet build system. Configuration is handled in `pyproject.toml`.

### 1. Build for Windows
Creates a standalone executable in `dist/windows`:
```bash
flet build windows
```

### 2. Build for Android (APK)
Creates a mobile-ready APK in `dist/apk`:
```bash
flet build apk
```

### 3. Build for Linux
Creates a standalone binary in `dist/linux`:
```bash
flet build linux
```

> [!TIP]
> Use the provided `flet_rebuild.bat` on Windows to clean and rebuild the desktop version with a single click.

## Legal Disclaimer

BeatBoss does not host, store, or distribute copyrighted content. It functions as a client-side player for publicly available streams. All rights belong to the respective content owners.
