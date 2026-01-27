import os
import requests
import threading
from pathlib import Path
from typing import Optional, Callable
import re


class DownloadManager:
    """Manage track downloads and local file operations"""
    
    def __init__(self, settings, log_callback: Optional[Callable] = None):
        self.settings = settings
        self.log_callback = log_callback
        self.active_downloads = {}  # {track_id: progress}
    
    def _sanitize_filename(self, filename: str) -> str:
        """Sanitize filename for safe file system storage"""
        # Remove invalid characters
        filename = re.sub(r'[<>:"/\\|?*]', '', filename)
        # Limit length
        if len(filename) > 200:
            filename = filename[:200]
        return filename
    
    def _get_file_path(self, track_id: int, title: str, artist: str) -> Path:
        """Generate file path for a track"""
        download_dir = Path(self.settings.get_download_location())
        download_dir.mkdir(parents=True, exist_ok=True)
        
        # Create filename: {track_id}_{artist} - {title}.mp3
        safe_title = self._sanitize_filename(title)
        safe_artist = self._sanitize_filename(artist)
        filename = f"{track_id}_{safe_artist} - {safe_title}.mp3"
        
        return download_dir / filename
    
    def is_downloaded(self, track_id: int) -> bool:
        """Check if track is downloaded"""
        return self.settings.is_track_downloaded(track_id)
    
    def get_local_path(self, track_id: int) -> Optional[str]:
        """Get local path for downloaded track"""
        return self.settings.get_track_path(track_id)
    
    def download_track(self, track_id: int, stream_url: str, title: str, artist: str, 
                      progress_callback: Optional[Callable] = None,
                      completion_callback: Optional[Callable] = None):
        """Download a track to local storage"""
        
        def _download():
            try:
                # Get file path
                file_path = self._get_file_path(track_id, title, artist)
                
                if self.log_callback:
                    self.log_callback("DOWNLOAD", f"Downloading: {title}", "INFO")
                
                # Download file
                response = requests.get(stream_url, stream=True, timeout=30)
                response.raise_for_status()
                
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0
                
                with open(file_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            
                            # Update progress
                            if progress_callback and total_size > 0:
                                progress = (downloaded / total_size) * 100
                                progress_callback(track_id, progress)
                
                # Register in settings
                self.settings.add_downloaded_track(track_id, str(file_path), title, artist)
                
                if self.log_callback:
                    self.log_callback("DOWNLOAD", f"Completed: {title}", "SUCCESS")
                
                # Call completion callback
                if completion_callback:
                    completion_callback(track_id, True, str(file_path))
                
                # Remove from active downloads
                if track_id in self.active_downloads:
                    del self.active_downloads[track_id]
                    
            except Exception as e:
                error_msg = f"Download failed: {str(e)}"
                print(f"[Download Error] {error_msg}")
                
                if self.log_callback:
                    self.log_callback("DOWNLOAD", error_msg, "ERROR")
                
                if completion_callback:
                    completion_callback(track_id, False, str(e))
                
                # Remove from active downloads
                if track_id in self.active_downloads:
                    del self.active_downloads[track_id]
        
        # Mark as active download
        self.active_downloads[track_id] = 0
        
        # Start download in background thread
        thread = threading.Thread(target=_download, daemon=True)
        thread.start()
    
    def delete_track(self, track_id: int) -> bool:
        """Delete a downloaded track"""
        try:
            file_path = self.settings.get_track_path(track_id)
            if file_path and Path(file_path).exists():
                Path(file_path).unlink()
                self.settings.remove_downloaded_track(track_id)
                
                if self.log_callback:
                    self.log_callback("DOWNLOAD", f"Deleted track {track_id}", "INFO")
                
                return True
            return False
        except Exception as e:
            print(f"Error deleting track: {e}")
            return False
    
    def get_download_progress(self, track_id: int) -> Optional[float]:
        """Get download progress for a track (0-100)"""
        return self.active_downloads.get(track_id)
    
    def is_downloading(self, track_id: int) -> bool:
        """Check if track is currently being downloaded"""
        return track_id in self.active_downloads
