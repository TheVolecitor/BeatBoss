# BeatBoss

[**Download Latest Release**](https://github.com/TheVolecitor/BeatBoss/releases)

BeatBoss is a desktop music player built with Python and Flet.
For API documentation, refer to: [DAB API Docs](https://github.com/sixnine-dotdev/dab-api-docs)

## Privacy Notice

**Location Permission**: Windows may show that BeatBoss is requesting location access. This is a side effect of the Flet UI framework (which uses a browser engine internally) and **not** something our app uses or needs. 

- **The app does NOT collect, use, or transmit your location**
- You can safely deny this permission - it won't affect app functionality
- The source code is fully open and contains zero geolocation API calls
- This is a known limitation of Flet-based desktop applications

## Features
*   Streaming from public sources
*   Youtube Playlist Import
*   Local playback and management
*   Dark/Light theme support

## Prerequisites

The application is primarily designed for Windows, but can also be built for Linux.

*   [Windows Setup Guide](#installation) (Default)
*   [Linux Build Guide](LINUX_BUILD.md) (Experimental)

### For End Users (Using Installer)
**No prerequisites needed!** The installer includes everything:
- ✅ VLC Media Player (bundled)
- ✅ FFmpeg (bundled)
- ✅ All required libraries

Just download and install!

### For Developers (Building from Source)

To build the executable and bundle dependencies correctly, follow these steps:

1.  **Python 3.10+**
2.  **VLC Portable (win64)**
    *   Download: [vlc-3.0.21-win64.zip](https://get.videolan.org/vlc/3.0.21/win64/vlc-3.0.21-win64.zip)
    *   Extract and rename the folder to `vlc` in the project root.
    *   Structure should be: `vlc/vlc.exe`, `vlc/plugins/`, etc.
3.  **FFmpeg (Essential for Local Playback)**
    *   Download: [ffmpeg-master-latest-win64-gpl.zip](https://github.com/BtbN/FFmpeg-Builds/releases)
    *   Copy `ffmpeg.exe` and all `.dll` files from the `bin/` folder to ffmpeg folder in the parent directory, the structure can be as follows
      ```bash
      ../ffmpeg/bin/ffmpeg.exe
      ../ffmpeg/ffmpeg.exe
      ```
    *   Required DLLs include: `avcodec-*.dll`, `avformat-*.dll`, `avutil-*.dll`, `swresample-*.dll`, `swscale-*.dll`.

> [!IMPORTANT]
> The bundling script (`beatboss.spec`) looks for these files in the root directory. If they are missing, the EXE will build but local playback will fail.

## Installation

1.  **Clone the repository**
    ```bash
    git clone https://github.com/TheVolecitor/BeatBoss.git
    cd BeatBoss
    ```

2.  **Create a virtual environment**
    ```bash
    python -m venv venv
    .\venv\Scripts\activate
    ```

3.  **Install dependencies**
    ```bash
    pip install -r requirements.txt
    ```

## Configuration

This application needs a YouTube Data API v3 key to import playlist from Youtube Music.

### 1. Add Your API Key (This part is completely optional)

Open `main_build.py` and replace the placeholder with your actual API key on line 18:

```python
YT_API_KEY = "your_actual_api_key_here"
```

### 2. Obtaining a YouTube Data API Key
1.  Go to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Create a new project.
3.  Navigate to **APIs & Services** > **Library**.
4.  Search for "YouTube Data API v3" and enable it.
5.  Go to **Credentials** > **Create Credentials** > **API Key**.
6.  Copy the generated key and paste it into `main_build.py`.

## Running the Application

Once setup is complete, run the player with:

```bash
python main_build.py
```

## Building Executable

To create a standalone executable and installer, you have two options:

### Method 1: Standard Build (Recommended - VLC)
This method uses the stable VLC-based player.
1. **Build the executable**
   ```bash
   pyinstaller beatboss.spec
   ```
2. **Create installer**
   - Open `beatboss_installer.iss` with Inno Setup.
   - Click "Compile".

### Method 2: FFmpeg-Only Build (Experimental)
This method uses `ffplay` directly and does not require VLC. It is **Windows-only** and may be less stable.
1. **Prerequisites**: Ensure `ffmpeg.exe`, `ffplay.exe`, and `ffprobe.exe` are in the project root.
2. **Build the executable**
   ```bash
   pyinstaller beatboss_ffmpeg.spec
   ```
3. **Create installer**
   - Open `beatboss_ffmpeg.iss` with Inno Setup.
   - Click "Compile".

## Legal Disclaimer

This application (BeatBoss) does not host, store, or distribute any music files or copyrighted content. It functions solely as a client-side player that streams content available publicly on the internet. All rights regarding audio content belong to their respective owners.
