"""
Audio player using VLC with ffmpeg for local files
Uses temporary file approach for Windows compatibility
"""

import vlc
import time
import threading
import subprocess
import tempfile
import os

class AudioPlayer:
    def __init__(self):
        self.instance = vlc.Instance("--no-xlib", "--quiet", "--no-video", "--aout=directx")
        self.player = self.instance.media_player_new()
        self.current_track = None
        self.is_playing = False
        self._volume = 80
        self.lock = threading.Lock()
        self.ffmpeg_process = None
        self.temp_file = None
        
        # Events
        self.on_track_end = None
        
        # Event Manager
        self.events = self.player.event_manager()
        self.events.event_attach(vlc.EventType.MediaPlayerEndReached, self._on_vlc_end)
        self.events.event_attach(vlc.EventType.MediaPlayerEncounteredError, self._on_vlc_error)
        
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
                is_local = url and not url.startswith(('http://', 'https://'))
                
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
                    self.temp_file = tempfile.mktemp(suffix='.wav')
                    
                    # Convert to WAV using ffmpeg
                    ffmpeg_cmd = [
                        'ffmpeg',
                        '-i', str(file_path.absolute()),
                        '-f', 'wav',
                        '-acodec', 'pcm_s16le',
                        '-ar', '44100',
                        '-ac', '2',
                        '-y',  # Overwrite
                        self.temp_file
                    ]
                    
                    try:
                        # Run ffmpeg conversion
                        print(f"[FFmpeg] Converting to WAV...")
                        result = subprocess.run(
                            ffmpeg_cmd,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=30,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
                        )
                        
                        if result.returncode == 0 and os.path.exists(self.temp_file):
                            # Play the converted file with VLC
                            print(f"[VLC] Playing converted file")
                            media = self.instance.media_new(self.temp_file)
                            self.player.set_media(media)
                            self.player.audio_set_volume(self._volume)
                            self.player.play()
                            
                            time.sleep(0.3)
                            
                            self.current_track = track_info
                            self.is_playing = True
                            print("[FFmpeg→VLC] ✓ Playback started")
                            return
                        else:
                            print("[FFmpeg] Conversion failed, trying direct VLC...")
                        
                    except FileNotFoundError:
                        print("[FFmpeg] ERROR: ffmpeg not found. Install: winget install ffmpeg")
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
                print(f"[VLC] Loading: {url[:60]}...")
                media = self.instance.media_new(url)
                self.player.set_media(media)
                self.player.audio_set_volume(self._volume)
                self.player.play()
                
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
