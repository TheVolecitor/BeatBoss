# BeatBoss

BeatBoss is a high-performance, cross-platform music player client designed for audiophiles. Built with Flutter, it delivers a native, responsive experience on both Windows and Android.

## Features

- **Cross-Platform**: Seamless experience on Windows and Android.
- **High-Quality Playback**: 
  - Windows: Direct MPV integration via `media_kit` for bit-perfect playback.
  - Android: Native `ExoPlayer` backend via `just_audio`.
- **Local Downloads**: Download tracks for offline listening with high-quality metadata.
- **Last.fm Integration**: 
  - Full scrobbling support.
  - Secure API signing (defaults to a private Cloudflare worker, but can be configured for personal use).
- **Modern UI**:
  - Dark/Light mode support.
  - Adaptive layouts (Responsive Dashboard on Desktop, Bottom Navigation on Mobile).
  - "Snappable" player pane and lyrics sheet.
- **Smart Queue**: Drag-and-drop reordering, history tracking mode.

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Latest Stable)
- [Git](https://git-scm.com/)
- **Windows**: Visual Studio 2022 with C++ Desktop Development workload.
- **Android**: Android Studio with SDK Command-line Tools.

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/DAB-py.git
   cd DAB-py
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the Application**

   *Windows:*
   ```bash
   flutter run -d windows
   ```

   *Android:*
   ```bash
   flutter run -d android
   ```

## Building for Production

### Windows (.exe)
```bash
flutter build windows
```
The output can be found in `build/windows/runner/Release/`.

### Android (.apk)
```bash
flutter build apk --release
```
The output `app-release.apk` will be in `build/app/outputs/flutter-apk/`.

## Configuration

### API Keys & Security
This project is open-source and **does not include private API keys**.
- **Spotify/YouTube**: Metadata is fetched via public web scraping; no API keys required.
- **Last.fm**: Requires a valid API Key and Shared Secret. These can be configured in the Settings UI or by deploying your own signing worker.

## License
MIT License. See `LICENSE` file for details.
