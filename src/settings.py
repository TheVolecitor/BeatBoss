import json
import os
from pathlib import Path
from typing import Dict, Any, Optional


class Settings:
    """Manage application settings with JSON persistence"""
    
    def __init__(self):
        self.settings_dir = self._get_settings_dir()
        self.settings_file = self.settings_dir / "settings.json"
        self.downloads_dir = None
        self.settings = self._load_settings()
        
    def _get_settings_dir(self) -> Path:
        """Get the settings directory (portable for .exe)"""
        if os.name == 'nt':  # Windows
            # Use APPDATA for portability
            appdata = os.getenv('APPDATA')
            if appdata:
                settings_path = Path(appdata) / "BeatBoss"
            else:
                settings_path = Path.home() / ".syncplayer"
        else:  # Linux/Mac
            settings_path = Path.home() / ".syncplayer"
        
        # Create directory if it doesn't exist
        settings_path.mkdir(parents=True, exist_ok=True)
        return settings_path
    
    def _get_default_download_location(self) -> str:
        """Get default download location"""
        music_dir = Path.home() / "Music" / "SyncPlayer"
        return str(music_dir)
    
    def _load_settings(self) -> Dict[str, Any]:
        """Load settings from JSON file or create defaults"""
        if self.settings_file.exists():
            try:
                with open(self.settings_file, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                    # Validate and set download directory
                    self._ensure_download_dir(settings.get('download_location'))
                    return settings
            except Exception as e:
                print(f"Error loading settings: {e}")
                return self._create_default_settings()
        else:
            return self._create_default_settings()
    
    def _create_default_settings(self) -> Dict[str, Any]:
        """Create default settings"""
        default_settings = {
            "theme": "dark",
            "download_location": self._get_default_download_location(),
            "downloaded_tracks": {}  # {track_id: {"path": str, "title": str, "artist": str}}
        }
        self._ensure_download_dir(default_settings['download_location'])
        
        # Manually save since self.settings isn't set yet, prevents AttributeError
        try:
            with open(self.settings_file, 'w', encoding='utf-8') as f:
                json.dump(default_settings, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error saving default settings: {e}")
            
        return default_settings
    
    def _ensure_download_dir(self, download_path: Optional[str]):
        """Ensure download directory exists"""
        if download_path:
            self.downloads_dir = Path(download_path)
            self.downloads_dir.mkdir(parents=True, exist_ok=True)
    
    def save(self):
        """Save settings to JSON file"""
        try:
            with open(self.settings_file, 'w', encoding='utf-8') as f:
                json.dump(self.settings, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error saving settings: {e}")
    
    def get(self, key: str, default: Any = None) -> Any:
        """Get a setting value"""
        return self.settings.get(key, default)
    
    def set(self, key: str, value: Any):
        """Set a setting value and save"""
        self.settings[key] = value
        
        # Update download directory if location changed
        if key == "download_location":
            self._ensure_download_dir(value)
        
        self.save()
    
    def get_theme(self) -> str:
        """Get current theme"""
        return self.settings.get("theme", "dark")
    
    def set_theme(self, theme: str):
        """Set theme (dark/light)"""
        if theme in ["dark", "light"]:
            self.set("theme", theme)
    
    def get_download_location(self) -> str:
        """Get download location"""
        return self.settings.get("download_location", self._get_default_download_location())
    
    def set_download_location(self, path: str):
        """Set download location"""
        self.set("download_location", path)
    
    def is_track_downloaded(self, track_id: int) -> bool:
        """Check if a track is downloaded"""
        downloaded = self.settings.get("downloaded_tracks", {})
        return str(track_id) in downloaded
    
    def get_track_path(self, track_id: int) -> Optional[str]:
        """Get local path for a downloaded track"""
        downloaded = self.settings.get("downloaded_tracks", {})
        track_data = downloaded.get(str(track_id))
        if track_data and isinstance(track_data, dict):
            path = track_data.get("path")
            # Verify file still exists
            if path and Path(path).exists():
                return path
        return None
    
    def add_downloaded_track(self, track_id: int, file_path: str, title: str, artist: str):
        """Register a downloaded track"""
        downloaded = self.settings.get("downloaded_tracks", {})
        downloaded[str(track_id)] = {
            "path": file_path,
            "title": title,
            "artist": artist
        }
        self.set("downloaded_tracks", downloaded)
    
    def remove_downloaded_track(self, track_id: int):
        """Remove a downloaded track from registry"""
        downloaded = self.settings.get("downloaded_tracks", {})
        if str(track_id) in downloaded:
            del downloaded[str(track_id)]
            self.set("downloaded_tracks", downloaded)
    
    def get_downloaded_count(self) -> int:
        """Get number of downloaded tracks"""
        return len(self.settings.get("downloaded_tracks", {}))
    
    def get_storage_size(self) -> int:
        """Get total size of downloaded tracks in bytes"""
        total_size = 0
        downloaded = self.settings.get("downloaded_tracks", {})
        for track_data in downloaded.values():
            if isinstance(track_data, dict):
                path = track_data.get("path")
                if path and Path(path).exists():
                    total_size += Path(path).stat().st_size
        return total_size
    
    def clear_cache(self):
        """Clear all downloaded tracks"""
        downloaded = self.settings.get("downloaded_tracks", {})
        for track_data in downloaded.values():
            if isinstance(track_data, dict):
                path = track_data.get("path")
                if path and Path(path).exists():
                    try:
                        Path(path).unlink()
                    except Exception as e:
                        print(f"Error deleting file: {e}")
        
        self.set("downloaded_tracks", {})

    def get_auth_credentials(self) -> Optional[Dict[str, str]]:
        """Get persisted authentication credentials"""
        return self.settings.get("auth")

    def set_auth_credentials(self, email: str, password: str):
        """Persist authentication credentials"""
        self.set("auth", {"email": email, "password": password})
        
    def clear_auth_credentials(self):
        """Clear persisted authentication credentials"""
        if "auth" in self.settings:
            del self.settings["auth"]
            self.save()
    
    def get_recent_searches(self) -> list:
        """Get recent searches (last 5)"""
        return self.settings.get("recent_searches", [])
    
    def set_recent_searches(self, searches: list):
        """Save recent searches (max 5)"""
        self.set("recent_searches", searches[:5])
    
    def get_play_history(self) -> list:
        """Get play history (last 5)"""
        return self.settings.get("play_history", [])
    
    def set_play_history(self, history: list):
        """Save play history (max 5)"""
        self.set("play_history", history[:5])
