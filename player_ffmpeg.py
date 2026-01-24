
import os
import shutil
import subprocess
import sys
import threading
import time
import re
from pathlib import Path

def _setup_ffmpeg_path():
    """
    Prefer a bundled ffmpeg located in an `ffmpeg` folder in the *parent directory*.
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
                ffmpeg_dir / "bin" / ("ffplay.exe" if os.name == "nt" else "ffplay"),
                ffmpeg_dir / ("ffplay.exe" if os.name == "nt" else "ffplay"),
                ffmpeg_dir / "bin" / "ffplay",
                ffmpeg_dir / "ffplay",
            ]
        )

    for p in candidate_paths:
        if p.exists():
            # put directory on PATH so subprocess can just call "ffmpeg"
            os.environ["PATH"] = str(p.parent) + os.pathsep + os.environ.get("PATH", "")
            print(f"[FFmpeg] Using bundled ffplay: {p}")
            return str(p)

    # Fallback: system
    sys_ffplay = shutil.which("ffplay")
    if sys_ffplay:
        print(f"[FFmpeg] Using system ffplay: {sys_ffplay}")
        return sys_ffplay

    print("[FFmpeg] ffplay Not found")
    return None

_FFPLAY_PATH = _setup_ffmpeg_path()

class AudioPlayer:
    def __init__(self):
        self.process = None
        self.current_track = None
        self.current_url = None # Store for seeking/resuming
        self.is_playing = False
        self._volume = 80 # 0-100
        self.lock = threading.Lock()
        
        # Playback events
        self.on_track_end = None
        self.on_error = None
        
        # State tracking
        self.current_time = 0
        self.duration = 0 # ms
        self.monitor_thread = None
        self.running = True
        self._internal_stop = False # Flag to distinguish manual stop from track end

    def play_url(self, url, track_info=None, start_pos=0, preserve_state=False):
        with self.lock:
            self.stop_internal(preserve_state=preserve_state) 
            
            if not _FFPLAY_PATH:
                print("[Player] Error: ffplay not found")
                # if self.on_error: self.on_error() # Prevent spamming error on extensive logic
                return

            self.current_track = track_info
            self.current_url = url
            self._internal_stop = False
            
            # Construct start time for seek
            start_seconds = start_pos / 1000.0
            
            cmd = [
                _FFPLAY_PATH,
                "-nodisp",
                "-autoexit",
                "-hide_banner",
                "-loglevel", "info", 
                "-volume", str(self._volume),
                "-ss", str(start_seconds),
                url
            ]
            
            try:
                print(f"[Player][{threading.get_ident()}] Starting ffplay: ... Pos: {start_seconds}s")
                
                startupinfo = None
                if os.name == 'nt':
                    startupinfo = subprocess.STARTUPINFO()
                    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                
                # Use binary mode for stderr to read byte-by-byte safely
                self.process = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    startupinfo=startupinfo,
                    bufsize=0 # Unbuffered
                )
                  
                self.is_playing = True
                
                # Ideally set current_time to start_pos immediately
                self.current_time = start_pos
                
                # Start monitor thread
                self.monitor_thread = threading.Thread(target=self._monitor_process, daemon=True)
                self.monitor_thread.start()
                
            except Exception as e:
                print(f"[Player] Execution error: {e}")
                self.is_playing = False
                if self.on_error: self.on_error()

    def _monitor_process(self):
        """Monitor stderr for time and completion (Byte-by-Byte to handle \\r)"""
        proc = self.process
        
        # Regex for time parsing: "1.14 A-V:"
        # We accumulate characters until we see \r or \n
        time_pattern = re.compile(r"(\d+\.\d+)\s+A-V:")
        dur_pattern = re.compile(r"Duration:\s+(\d{2}):(\d{2}):(\d{2}\.\d+)")
        
        line_buffer = bytearray()
        
        try:
            while self.running and proc.poll() is None:
                # Read 1 byte
                char = proc.stderr.read(1)
                if not char:
                    # EOF or Process died
                    break
                    
                if char in b'\r\n':
                    # Process the line
                    try:
                        line_str = line_buffer.decode('utf-8', errors='ignore')
                    except:
                        line_str = ""
                    
                    line_buffer.clear()
                    
                    if not line_str: continue
                    # DEBUG: Print what we see
                    # print(f"[Debug] FFline: {repr(line_str)}")

                    # IGNORE 'nan' timestamps (common during seek)
                    if "nan" in line_str.lower():
                        continue

                    # Parse Duration once
                    if self.duration == 0:
                        dur_match = dur_pattern.search(line_str)
                        if dur_match:
                            h, m, s = dur_match.groups()
                            self.duration = (int(h)*3600 + int(m)*60 + float(s)) * 1000
                            print(f"[Player] Duration found: {self.duration}ms")
                    
                    # Parse Time
                    # Try multiple patterns
                    # 1. Standard A-V (mem check)
                    # 2. Audio only M-A
                    # 3. Just the first float if line looks like status (contains 'aq=' or 'size=')
                    
                    found_sec = None
                    
                    # Pattern 1 & 2: Anchor based
                    anchor_match = re.search(r"([0-9\.]+)\s+(?:A-V:|M-A:|fd=)", line_str)
                    if anchor_match:
                        found_sec = float(anchor_match.group(1))
                    
                    # Pattern 3: Fallback heuristic (First float if line denotes progress)
                    if found_sec is None and ("aq=" in line_str or "size=" in line_str or "bitrate=" in line_str):
                         simple_match = re.search(r"^\s*([0-9\.]+)", line_str)
                         if simple_match:
                             found_sec = float(simple_match.group(1))

                    if found_sec is not None:
                        self.current_time = found_sec * 1000
                        # print(f"[Debug] Time updated: {self.current_time}")
                    else:
                        pass
                else:
                    line_buffer.extend(char)
                
            # Process ended
            print(f"[Player][monitor] Process ended. RC: {proc.returncode}")
            
            # Wait for strict finish
            proc.wait()
            self.is_playing = False
            
            # If stopped manually (Pause or Stop), don't trigger next track
            if not self._internal_stop and proc.returncode == 0:
                if self.on_track_end: self.on_track_end()
                
        except Exception as e:
            print(f"[Player][monitor] Error: {e}")

    def pause(self):
        """Emulate pause by stopping and remembering position"""
        if self.is_playing:
            print(f"[Player] Pausing at {self.current_time}ms")
            self.stop_internal(preserve_state=True)
            self.is_playing = False
        
    def resume(self):
        """Emulate resume by restarting at remembered position"""
        if not self.is_playing and self.current_url:
            print(f"[Player] Resuming at {self.current_time}ms")
            self.play_url(self.current_url, self.current_track, start_pos=self.current_time, preserve_state=True)

    def stop(self):
        self.stop_internal(preserve_state=False)

    def stop_internal(self, preserve_state=False):
        """
        Internal stop.
        preserve_state=True: keep current_time and duration, suppress on_track_end
        """
        self._internal_stop = True # Suppress on_track_end
        
        if self.process:
            # print(f"[Player] Stopping PID {self.process.pid}")
            try:
                self.process.terminate()
                try:
                    self.process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            except:
                pass
            self.process = None
        
        self.is_playing = False
        
        if not preserve_state:
            # Full stop resets time
            self.current_time = 0
            self.duration = 0 # Reset duration so we parse it again for next track
        else:
            # Keep current_time and duration (e.g. for pause or seek)
            pass

    def toggle_play_pause(self):
        if self.is_playing:
            self.pause()
        else:
            self.resume()
        return self.is_playing

    def set_volume(self, volume):
        self._volume = int(volume)
        # Note: Volume only updates on next Play/Resume/Seek because ffplay doesn't support runtime volume via stdin

    def get_time(self):
        return self.current_time

    def get_length(self):
        return self.duration or 300000 

    def set_position(self, pos):
        if self.duration > 0:
            ms = pos * self.duration
            self.seek(ms)

    def seek(self, ms):
        if self.current_url:
            # print(f"[Player] Seeking to {ms}ms")
            self._internal_stop = True # Suppress events during seek restart
            # Restart at new pos
            # Pass preserve_state=True so stop_internal doesn't clear duration/time
            self.play_url(self.current_url, self.current_track, start_pos=ms, preserve_state=True)
            
    def close(self):
        """Cleanup resources"""
        self.stop_internal(preserve_state=False)

    def _send_command(self, char):
        pass
