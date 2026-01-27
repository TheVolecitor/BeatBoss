"""
Windows System Media Transport Controls (SMTC) Integration
Uses BackgroundMediaPlayer for desktop app compatibility
"""

import sys
import threading

# Windows-specific imports - LAZY LOADED to improve startup time
# if sys.platform == 'win32': ... (Moved to inside class)


class WindowsMediaControls:
    """Integrate with Windows System Media Transport Controls for desktop apps"""
    
    def __init__(self, on_play_pause=None, on_next=None, on_prev=None):
        self.on_play_pause = on_play_pause
        self.on_next = on_next
        self.on_prev = on_prev
        self.smtc = None
        self.display_updater = None
        self.media_player = None
        self.enabled = False
        
        if sys.platform != 'win32':
            print("[SMTC] Not on Windows, skipping")
            return

        # Initialize in a separate thread to not block UI
        try:
            self._initialize_smtc()
        except Exception as e:
            print(f"[SMTC] Failed to initialize: {e}")
            import traceback
            traceback.print_exc()
    
    def _initialize_smtc(self):
        """Initialize Windows SMTC using BackgroundMediaPlayer"""
        try:
            # Lazy import to prevent blocking startup
            global SystemMediaTransportControlsButton, MediaPlaybackStatus, RandomAccessStreamReference, Uri
            from winrt.windows.media.playback import MediaPlayer
            from winrt.windows.media import SystemMediaTransportControls, MediaPlaybackStatus, SystemMediaTransportControlsButton
            from winrt.windows.storage.streams import RandomAccessStreamReference
            from winrt.windows.foundation import Uri
            
            print("[SMTC] Windows Runtime modules loaded successfully")
            
            # Create a MediaPlayer instance for SMTC
            self.media_player = MediaPlayer()
            
            # Get SMTC from the media player
            self.smtc = self.media_player.system_media_transport_controls
            
            # Enable buttons
            self.smtc.is_enabled = True
            self.smtc.is_play_enabled = True
            self.smtc.is_pause_enabled = True
            self.smtc.is_next_enabled = True
            self.smtc.is_previous_enabled = True
            
            # Set up event handlers
            self.smtc.add_button_pressed(self._on_button_pressed)
            
            # Get display updater for metadata
            self.display_updater = self.smtc.display_updater
            
            self.enabled = True
            print("[SMTC] Windows media controls initialized successfully")
            
        except Exception as e:
            print(f"[SMTC] Initialization error: {e}")
            import traceback
            traceback.print_exc()
            self.enabled = False
    
    def _on_button_pressed(self, sender, args):
        """Handle media button presses from Windows"""
        button = args.button
        
        try:
            if button == SystemMediaTransportControlsButton.PLAY:
                print("[SMTC] Play button pressed")
                if self.on_play_pause:
                    threading.Thread(target=self.on_play_pause, daemon=True).start()
            elif button == SystemMediaTransportControlsButton.PAUSE:
                print("[SMTC] Pause button pressed")
                if self.on_play_pause:
                    threading.Thread(target=self.on_play_pause, daemon=True).start()
            elif button == SystemMediaTransportControlsButton.NEXT:
                print("[SMTC] Next button pressed")
                if self.on_next:
                    threading.Thread(target=self.on_next, daemon=True).start()
            elif button == SystemMediaTransportControlsButton.PREVIOUS:
                print("[SMTC] Previous button pressed")
                if self.on_prev:
                    threading.Thread(target=self.on_prev, daemon=True).start()
        except Exception as e:
            print(f"[SMTC] Button handler error: {e}")
    
    def update_metadata(self, title, artist, album=None, thumbnail_url=None):
        """Update the media metadata shown in Windows"""
        if not self.enabled or not self.display_updater:
            return
        
        try:
            # Clear previous data
            self.display_updater.clear_all()
            
            # Set type to music
            self.display_updater.type = 1  # MediaPlaybackType.Music
            
            # Update music properties
            music_props = self.display_updater.music_properties
            music_props.title = title or "Unknown Title"
            music_props.artist = artist or "Unknown Artist"
            if album:
                music_props.album_title = album
            
            # Update thumbnail if provided
            if thumbnail_url and thumbnail_url.startswith('http'):
                try:
                    thumbnail = RandomAccessStreamReference.create_from_uri(Uri(thumbnail_url))
                    self.display_updater.thumbnail = thumbnail
                except Exception as e:
                    print(f"[SMTC] Thumbnail error: {e}")
            
            # Apply the update
            self.display_updater.update()
            print(f"[SMTC] Updated metadata: {title} - {artist}")
            
        except Exception as e:
            print(f"[SMTC] Metadata update error: {e}")
            import traceback
            traceback.print_exc()
    
    def set_playback_status(self, is_playing):
        """Update playback status in Windows"""
        if not self.enabled or not self.smtc:
            return
        
        try:
            if is_playing:
                self.smtc.playback_status = MediaPlaybackStatus.PLAYING
            else:
                self.smtc.playback_status = MediaPlaybackStatus.PAUSED
            print(f"[SMTC] Playback status: {'Playing' if is_playing else 'Paused'}")
        except Exception as e:
            print(f"[SMTC] Status update error: {e}")
    
    def clear(self):
        """Clear the media information"""
        if not self.enabled or not self.display_updater:
            return
        
        try:
            self.display_updater.clear_all()
            if self.smtc:
                self.smtc.playback_status = MediaPlaybackStatus.STOPPED
        except Exception as e:
            print(f"[SMTC] Clear error: {e}")
