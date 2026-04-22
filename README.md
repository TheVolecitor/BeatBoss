# BeatBoss

BeatBoss is a high performance cross platform music player client designed for audiophiles. Built with Flutter, it delivers a native, responsive experience on both Windows and Android.

Note: This project has been migrated from Flet (Python) to Flutter to resolve stability issues and ensure a robust, native performance across platforms.

## Features

- Cross Platform: Seamless experience on Windows, Linux and Android.
- High Quality Playback: Support for various stream formats and high resolution audio.
- Local Downloads: Download tracks for offline listening with high quality metadata.
- Last.fm Integration: Full scrobbling support and secure API signing.
- Modern UI: Dark and Light mode support with adaptive layouts.
- Smart Queue: Drag and drop reordering and history tracking.
- Addon System: Extensible architecture for search, lyrics, and cloud synchronization.

## Getting Started

### Prerequisites

- Flutter SDK (Latest Stable)
- Git
- Windows: Visual Studio 2022 with C++ Desktop Development workload.
- Android: Android Studio with SDK Command line Tools.

### Installation

1. Copy the repository:
   ```bash
   git clone https://github.com/TheVolecitor/BeatBoss.git
   cd BeatBoss
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the application:

   Windows:
   ```bash
   flutter run -d windows
   ```

   Android:
   ```bash
   flutter run -d android
   ```

## Building for Production

### Windows (.exe)
```bash
flutter build windows
```
The output can be found in build/windows/runner/Release/.

### Android (.apk)
```bash
flutter build apk --release
```
The output app-release.apk will be in build/app/outputs/flutter-apk/.

## Addon Development

The application supports a flexible addon system for extending its functionality. You can develop your own addons to provide new search sources, lyrics providers, or custom library synchronization servers.

For detailed information on how to build and integrate your own addons, please refer to the [Addon Development Guide](ADDONS.md).

## Configuration

### API Keys and Security
This project is open source and does not include private API keys.
- Spotify and YouTube: Metadata is fetched via public web scraping. No API keys are required.
- Last.fm: Requires a valid API Key and Shared Secret. These can be configured in the Settings UI.

## License
MIT License. See LICENSE file for details.

## Disclaimer
BeatBoss is solely a client side audio player that streams or locally plays audio from the user's own library. All rights belong to their respective owners.
