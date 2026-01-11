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

1.  **Python 3.10+**
2.  **VLC Media Player** (Required for audio playback engine)
    *   Ensure the architecture matches your Python install (x64 recommended).
3.  **FFmpeg** (Required for format conversion)
    *   Download from [ffmpeg.org](https://ffmpeg.org/download.html).
    *   Extract `ffmpeg.exe` and `ffprobe.exe` and place them in the project root folder.

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

This application requires a YouTube Data API v3 key to function.

### 1. Add Your API Key

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

To create a standalone executable and installer:

1. **Build the executable**
   ```bash
   .\clean_rebuild.bat
   ```
   This will create `BeatBoss.exe` in the `dist` folder.

2. **Create installer (optional)**
   - Install [Inno Setup](https://jrsoftware.org/isdl.php)
   - Open `beatboss_installer.iss` with Inno Setup Compiler
   - Click "Compile" to generate the installer in the `Output` folder

## Legal Disclaimer

This application (BeatBoss) does not host, store, or distribute any music files or copyrighted content. It functions solely as a client-side player that streams content available publicly on the internet. All rights regarding audio content belong to their respective owners.
