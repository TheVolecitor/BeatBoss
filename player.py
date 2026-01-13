"""
Audio player using VLC with ffmpeg for local files
Uses temporary file approach for Windows compatibility
Supports bundled VLC portable for easy deployment

Bundling expectation:
- VLC: `BeatBoss/vlc/...` (existing behavior)
- FFmpeg: `../ffmpeg/bin/ffmpeg(.exe)` (new behavior; mirrors "parent directory like vlc", but inside an `ffmpeg` folder)
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path


# Setup bundled VLC path
def _setup_vlc_path():
    """Configure VLC path to use bundled version if available"""
    app_dir = os.path.dirname(os.path.abspath(__file__))
    bundled_vlc = os.path.join(app_dir, "vlc")

    if os.path.exists(bundled_vlc):
        os.environ["PATH"] = bundled_vlc + os.pathsep + os.environ.get("PATH", "")
        print(f"[VLC] Using bundled VLC: {bundled_vlc}")
        return bundled_vlc

    # Linux-specific: PyInstaller can mess up library discovery, so we explicitly look for it
    if sys.platform.startswith("linux"):
        # 1. Check for bundled 'vlc_libs' (Manual bundle)
        # Structure: vlc_libs/lib/libvlc.so and vlc_libs/plugins/...
        bundled_linux = os.path.join(app_dir, "vlc_libs")
        if os.path.exists(bundled_linux):
            lib_path = os.path.join(bundled_linux, "lib", "libvlc.so")
            plugin_path = os.path.join(bundled_linux, "plugins")

            # Try specific versioned name if generic symlink doesn't exist
            if not os.path.exists(lib_path):
                # Search for libvlc.so.5 or similar
                import glob

                libs = glob.glob(os.path.join(bundled_linux, "lib", "libvlc.so.*"))
                if libs:
                    lib_path = libs[0]

            if os.path.exists(lib_path):
                os.environ["PYTHON_VLC_LIB_PATH"] = lib_path
                os.environ["VLC_PLUGIN_PATH"] = plugin_path
                print(f"[VLC] Linux: Using bundled binaries at {lib_path}")
                print(f"[VLC] Linux: Plugins set to {plugin_path}")
                return lib_path

        # 2. Check individual paths (libraries only, system plugins)
        possible_paths = [
            os.path.join(app_dir, "libvlc.so"),  # Bundled in app root
            os.path.join(app_dir, "_internal", "libvlc.so"),  # PyInstaller _internal
            os.path.join(sys.prefix, "lib", "libvlc.so"),  # Venv/System
            "/usr/lib/x86_64-linux-gnu/libvlc.so",  # Debian/Ubuntu/Kali
            "/usr/lib/libvlc.so",  # Arch/Fedora
            "/usr/lib64/libvlc.so",  # OpenSUSE
        ]

        for p in possible_paths:
            if os.path.exists(p):
                os.environ["PYTHON_VLC_LIB_PATH"] = p
                print(f"[VLC] Linux: Found and set libvlc at {p}")
                return p

        # Fallback: Try to find any libvlc.so using ldconfig or find
        try:
            print("[VLC] Searching system using ldconfig...")
            res = subprocess.run(["ldconfig", "-p"], capture_output=True, text=True)
            for line in res.stdout.splitlines():
                if "libvlc.so" in line and "=>" in line:
                    path = line.split("=>")[1].strip()
                    if os.path.exists(path):
                        os.environ["PYTHON_VLC_LIB_PATH"] = path
                        print(f"[VLC] Linux: Found via ldconfig at {path}")
                        return path
        except:
            pass

    print("[VLC] Using system VLC (PATH search)")
    return None


def _setup_ffmpeg_path():
    """
    Prefer a bundled ffmpeg located in an `ffmpeg` folder in the *parent directory*.
    Expected layouts (Windows & common portable bundles):
      - ../ffmpeg/bin/ffmpeg.exe
      - ../ffmpeg/ffmpeg.exe
      - ../ffmpeg/bin/ffmpeg
      - ../ffmpeg/ffmpeg
    Falls back to system ffmpeg (PATH search).
    """
    app_dir = Path(__file__).resolve().parent
    parent_dir = app_dir.parent
    ffmpeg_dir = parent_dir / "ffmpeg"

    candidate_paths = []
    if ffmpeg_dir.exists():
        # common package layout
        candidate_paths.extend(
            [
                ffmpeg_dir / "bin" / ("ffmpeg.exe" if os.name == "nt" else "ffmpeg"),
                ffmpeg_dir / ("ffmpeg.exe" if os.name == "nt" else "ffmpeg"),
                ffmpeg_dir
                / "bin"
                / "ffmpeg",  # allow non-nt even if os.name reports something odd
                ffmpeg_dir / "ffmpeg",
            ]
        )

    for p in candidate_paths:
        if p.exists():
            # put directory on PATH so subprocess can just call "ffmpeg"
            os.environ["PATH"] = str(p.parent) + os.pathsep + os.environ.get("PATH", "")
            print(f"[FFmpeg] Using bundled ffmpeg: {p}")
            return str(p)

    # Fallback: system
    sys_ffmpeg = shutil.which("ffmpeg")
    if sys_ffmpeg:
        print(f"[FFmpeg] Using system ffmpeg: {sys_ffmpeg}")
        return sys_ffmpeg

    print("[FFmpeg] Not found (expected ../ffmpeg/... or on PATH)")
    return None


_setup_vlc_path()
_FFMPEG_PATH = _setup_ffmpeg_path()

import tempfile
import threading
import time

import vlc


class AudioPlayer:
    def __init__(self):
        vlc_args = ["--no-xlib", "--quiet", "--no-video"]
        if sys.platform == "win32":
            vlc_args.append("--aout=directx")

        self.instance = vlc.Instance(*vlc_args)
        if not self.instance:
            print(
                "[Player] CRITICAL: Could not create VLC instance. Is libvlc installed?"
            )
            self.player = None
        else:
            try:
                self.player = self.instance.media_player_new()
            except Exception as e:
                print(f"[Player] Error creating media player: {e}")
                self.player = None
        self.current_track = None
        self.is_playing = False
        self._volume = 80
        self.lock = threading.Lock()
        self.ffmpeg_process = None
        self.temp_file = None

        # Events
        self.on_track_end = None

        # Event Manager
        self.events = None
        if self.player:
            try:
                self.events = self.player.event_manager()
                self.events.event_attach(
                    vlc.EventType.MediaPlayerEndReached, self._on_vlc_end
                )
                self.events.event_attach(
                    vlc.EventType.MediaPlayerEncounteredError, self._on_vlc_error
                )
            except Exception as e:
                print(f"[Player] Error attaching events: {e}")
                self.events = None

        self.running = True
        self.on_error = None

    def _on_vlc_error(self, event):
        print("[VLC] Error event received")
        if self.on_error:
            threading.Thread(target=self.on_error, daemon=True).start()

    def _on_vlc_end(self, event):
        if self.on_track_end:
            threading.Thread(target=self.on_track_end, daemon=True).start()

    def _cleanup_temp(self):
        """Clean up temporary file"""
        if self.temp_file and os.path.exists(self.temp_file):
            try:
                os.unlink(self.temp_file)
            except:
                pass
            self.temp_file = None

    def _stop_ffmpeg(self):
        """Stop any running ffmpeg process"""
        if self.ffmpeg_process:
            try:
                self.ffmpeg_process.terminate()
                self.ffmpeg_process.wait(timeout=2)
            except:
                try:
                    self.ffmpeg_process.kill()
                except:
                    pass
            self.ffmpeg_process = None

    def play_url(self, url, track_info=None):
        with self.lock:
            try:
                is_local = url and not url.startswith(("http://", "https://"))

                # For local files, convert with ffmpeg to temp file
                if is_local:
                    from pathlib import Path

                    file_path = Path(url)
                    if not file_path.exists():
                        print(f"[Player] File not found: {url}")
                        self.is_playing = False
                        return

                    print(f"[FFmpeg→VLC] Converting: {file_path.name}")

                    # Stop any previous process
                    self._stop_ffmpeg()
                    self._cleanup_temp()

                    # Create temporary WAV file
                    self.temp_file = tempfile.mktemp(suffix=".wav")

                    # Convert to WAV using ffmpeg (prefer bundled if found)
                    ffmpeg_exe = _FFMPEG_PATH or "ffmpeg"
                    ffmpeg_cmd = [
                        ffmpeg_exe,
                        "-i",
                        str(file_path.absolute()),
                        "-f",
                        "wav",
                        "-acodec",
                        "pcm_s16le",
                        "-ar",
                        "44100",
                        "-ac",
                        "2",
                        "-y",  # Overwrite
                        self.temp_file,
                    ]

                    try:
                        # Run ffmpeg conversion
                        print(f"[FFmpeg] Converting to WAV...")
                        result = subprocess.run(
                            ffmpeg_cmd,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=30,
                            creationflags=subprocess.CREATE_NO_WINDOW
                            if os.name == "nt"
                            else 0,
                        )

                        if result.returncode == 0 and os.path.exists(self.temp_file):
                            # Play the converted file with VLC
                            print(f"[VLC] Playing converted file")
                            if self.instance and self.player:
                                media = self.instance.media_new(self.temp_file)
                                self.player.set_media(media)
                                self.player.audio_set_volume(self._volume)
                                self.player.play()

                                time.sleep(0.3)

                                self.current_track = track_info
                                self.is_playing = True
                                print("[FFmpeg→VLC] ✓ Playback started")
                            else:
                                print(
                                    f"[Player] Error: VLC not initialized, cannot play {self.temp_file}"
                                )
                            return
                        else:
                            print("[FFmpeg] Conversion failed, trying direct VLC...")

                    except FileNotFoundError:
                        print(
                            "[FFmpeg] ERROR: ffmpeg not found. Install: winget install ffmpeg"
                        )
                        print("[FFmpeg] Falling back to direct VLC...")
                    except Exception as e:
                        print(f"[FFmpeg] Error: {e}")

                    # Fallback: try direct VLC playback
                    self._cleanup_temp()
                    url = str(file_path.absolute())

                # Stop ffmpeg if switching to streaming
                self._stop_ffmpeg()
                self._cleanup_temp()

                # Use VLC for streaming or fallback
                if self.instance and self.player:
                    print(f"[VLC] Loading: {url[:60]}...")
                    media = self.instance.media_new(url)
                    self.player.set_media(media)
                    self.player.audio_set_volume(self._volume)
                    self.player.play()
                else:
                    print("[Player] Error: VLC not initialized")
                    return

                time.sleep(0.3)
                self.current_track = track_info
                self.is_playing = True
                print("[VLC] ✓ Playback started")

            except Exception as e:
                print(f"[Player] Error: {e}")
                import traceback

                traceback.print_exc()
                self.is_playing = False

    def toggle_play_pause(self):
        if self.player:
            if self.player.is_playing():
                self.player.pause()
                self.is_playing = False
            else:
                self.player.play()
                self.is_playing = True
        return self.is_playing

    def pause(self):
        if self.player and self.player.is_playing():
            self.player.pause()
            self.is_playing = False

    def resume(self):
        if self.player and not self.player.is_playing():
            self.player.play()
            self.is_playing = True

    def stop(self):
        with self.lock:
            self._stop_ffmpeg()
            self._cleanup_temp()
            if self.player:
                self.player.stop()
            self.is_playing = False

    def set_volume(self, volume):
        self._volume = int(volume)
        if self.player:
            self.player.audio_set_volume(self._volume)

    def get_time(self):
        try:
            if self.player:
                t = self.player.get_time()
                return max(0, t)
        except:
            pass
        return 0

    def get_length(self):
        try:
            if self.player:
                l = self.player.get_length()
                return max(0, l)
        except:
            pass
        return 0

    def set_position(self, pos):
        if self.player:
            self.player.set_position(pos)

    def seek(self, ms):
        """Seek to specific time in milliseconds"""
        if self.player:
            self.player.set_time(int(ms))
