# BeatBoss

[**Download Latest Release**](https://github.com/TheVolecitor/BeatBoss/releases)

BeatBoss is a desktop music player built with Python and Flet.
For API documentation, refer to: [DAB API Docs](https://github.com/sixnine-dotdev/dab-api-docs)

## Features
*   Streaming from public sources
*   Local playback and management
*   Auto-scrolling lyrics
*   Dark/Light theme support

## Prerequisites

Before running the application, ensure you have the following installed:

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

### 1. Formatting the Environment File
Create a file named `.env` in the root directory and add your API key:

```ini
YT_API_KEY=your_api_key_here
```

### 2. Obtaining a YouTube Data API Key
1.  Go to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Create a new project.
3.  Navigate to **APIs & Services** > **Library**.
4.  Search for "YouTube Data API v3" and enable it.
5.  Go to **Credentials** > **Create Credentials** > **API Key**.
6.  Copy the generated key and paste it into your `.env` file.

## Running the Application

Once setup is complete, run the player with:

```bash
python main_flet.py
```

## Legal Disclaimer

This application (BeatBoss) does not host, store, or distribute any music files or copyrighted content. It functions solely as a client-side player that streams content available publicly on the internet. All rights regarding audio content belong to their respective owners.
