import requests
import json

from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

class DabAPI:
    BASE_URL = "https://dabmusic.xyz/api"

    def __init__(self, log_callback=None):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Origin": "https://dabmusic.xyz",
            "Referer": "https://dabmusic.xyz/",
            "Connection": "keep-alive"
        })
        
        # Configure Retries - reduced for faster failure
        retry_strategy = Retry(
            total=2,  # Reduced from 5 to 2 retries
            backoff_factor=0.5,  # Reduced from 1 to 0.5
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS", "POST", "PUT"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

        self.user = None
        self.log_callback = log_callback

    def _log(self, method, url, status, response_body=None):
        if self.log_callback:
            self.log_callback(method, url, status, response_body)

    def _normalize_track(self, track):
        """Normalize track data from various formats (e.g. Album details, Qobuz) to standard schema"""
        if not track: return track
        
        # Album normalization
        if 'albumTitle' in track and 'album' not in track:
            track['album'] = {
                'title': track['albumTitle'], 
                'cover': track.get('albumCover') or track.get('images', {}).get('large')
            }
            
        # Image normalization
        if 'albumCover' in track and not track.get('image'):
            track['image'] = track['albumCover']
        if not track.get('image') and track.get('images'):
             track['image'] = track['images'].get('large') or track['images'].get('thumbnail')
             
        # Duration normalization (seconds to ms)
        # If duration is small (< 30000), assume seconds. 30000s = 8+ hours, so safe for ms check.
        dur = track.get('duration', 0)
        if isinstance(dur, (int, float)) and dur > 0 and dur < 30000: 
            track['duration'] = int(dur * 1000)
            
        return track

    def login(self, email, password):
        url = f"{self.BASE_URL}/auth/login"
        payload = {"email": email, "password": password}
        response = self.session.post(url, json=payload, timeout=5)
        self._log("POST", url, response.status_code, response.text)
        if response.status_code == 200:
            data = response.json()
            self.user = data.get("user")
            return True, data.get("message")
        return False, response.json().get("message", "Login failed")

    def signup(self, username, email, password):
        url = f"{self.BASE_URL}/auth/register"
        payload = {
            "username": username, 
            "email": email, 
            "password": password,
            "inviteCode": ""
        }
        try:
            response = self.session.post(url, json=payload, timeout=5)
            self._log("POST", url, response.status_code, response.text)
            if response.status_code in [200, 201]:
                return True, response.json().get("message", "Signup successful")
            return False, response.json().get("message", "Signup failed")
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False, "Connection error during signup"

    def get_me(self):
        url = f"{self.BASE_URL}/auth/me"
        response = self.session.get(url, timeout=5)
        self._log("GET", url, response.status_code, response.text)
        if response.status_code == 200:
            self.user = response.json().get("user")
            return self.user
        return None

    def search(self, query, search_type="track", limit=20):
        url = f"{self.BASE_URL}/search"
        params = {"q": query, "type": search_type, "limit": limit}
        response = self.session.get(url, params=params, timeout=5)
        self._log("GET", url, response.status_code, response.text)
        if response.status_code == 200:
            data = response.json()
            if data and 'tracks' in data:
                data['tracks'] = [self._normalize_track(t) for t in data['tracks']]
            return data
        return None
        return None

    def get_album_details(self, album_id):
        url = f"{self.BASE_URL}/album/{album_id}"
        response = self.session.get(url, timeout=5)
        self._log("GET", url, response.status_code, response.text)
        if response.status_code == 200:
            data = response.json()
            if data and 'album' in data:
                # Normalize tracks within the album if present
                if 'tracks' in data['album']:
                    data['album']['tracks'] = [self._normalize_track(t) for t in data['album']['tracks']]
                return data['album']
        return None

    def get_stream_url(self, track_id, quality="27"):
        url = f"{self.BASE_URL}/stream"
        params = {"trackId": track_id, "quality": quality}
        response = self.session.get(url, params=params, timeout=5)
        self._log("GET", url, response.status_code, response.text)
        if response.status_code == 200:
            return response.json().get("url")
        return None

    def get_lyrics(self, artist, title):
        url = f"{self.BASE_URL}/lyrics"
        params = {"artist": artist, "title": title}
        
        # Custom retry logic for lyrics only
        max_retries = 5
        timeout = 15  # Increased timeout for lyrics
        
        import time
        for attempt in range(max_retries):
            try:
                # Use a fresh request to avoid global session timeout/retry limits if needed, 
                # or just use self.session but catch timeout explicitly.
                # Using self.session is better for keep-alive, but we want to override timeout.
                response = self.session.get(url, params=params, timeout=timeout)
                self._log("GET", url, response.status_code, response.text[:200] + "..." if len(response.text) > 200 else response.text)
                
                if response.status_code == 200:
                    return response.json()
                elif response.status_code == 404:
                    # Don't retry if not found
                    return None
                elif response.status_code >= 500:
                    # Server error, retry
                    pass
                else:
                    # Client error other than 404, probably shouldn't retry or maybe rate limit
                    pass
                    
            except Exception as e:
                self._log("ERROR", url, 0, f"Attempt {attempt+1}/{max_retries} failed: {str(e)}")
            
            # Exponential backoff: 0.5, 1, 2, 4, 8...
            if attempt < max_retries - 1:
                time.sleep(0.5 * (2 ** attempt))
                
        return None

    def get_libraries(self):
        url = f"{self.BASE_URL}/libraries"
        response = self.session.get(url, timeout=5)
        self._log("GET", url, response.status_code, response.text)
        if response.status_code == 200:
            return response.json().get("libraries", [])
        return []

    def create_library(self, name, description="", is_public=False):
        url = f"{self.BASE_URL}/libraries"
        payload = {"name": name, "description": description, "isPublic": is_public}
        response = self.session.post(url, json=payload, timeout=5)
        self._log("POST", url, response.status_code, response.text)
        if response.status_code == 201:
            return response.json().get("library")
        return None

    def add_track_to_library(self, library_id, track_data):
        url = f"{self.BASE_URL}/libraries/{library_id}/tracks"
        # track_data should match the Track schema
        payload = {"track": track_data}
        try:
            response = self.session.post(url, json=payload, timeout=5)
            self._log("POST", url, response.status_code, response.text)
            return response.status_code == 201 or response.status_code == 200
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False

    def remove_track_from_library(self, library_id, track_id):
        url = f"{self.BASE_URL}/libraries/{library_id}/tracks/{track_id}"
        try:
            response = self.session.delete(url, timeout=5)
            self._log("DELETE", url, response.status_code, response.text)
            return response.status_code == 200 or response.status_code == 204
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False

    def update_library(self, library_id, name=None, description=None, is_public=None):
        url = f"{self.BASE_URL}/libraries/{library_id}"
        payload = {}
        if name is not None:
            payload["name"] = name
        if description is not None:
            payload["description"] = description
        if is_public is not None:
            payload["isPublic"] = is_public
        
        try:
            response = self.session.patch(url, json=payload, timeout=5)
            self._log("PATCH", url, response.status_code, response.text)
            return response.status_code == 200
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False

    def delete_library(self, library_id):
        url = f"{self.BASE_URL}/libraries/{library_id}"
        try:
            response = self.session.delete(url, timeout=5)
            self._log("DELETE", url, response.status_code, response.text)
            return response.status_code == 200 or response.status_code == 204
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False

    def get_library_tracks(self, library_id, page=1, limit=20):
        # The user's sample shows GET /api/libraries/<uuid> returns 200 OK
        # We try both the base UUID and the /tracks suffix for compatibility
        endpoints = [
            f"{self.BASE_URL}/libraries/{library_id}?page={page}&limit={limit}",
            f"{self.BASE_URL}/libraries/{library_id}/tracks?page={page}&limit={limit}"
        ]
        
        for url in endpoints:
            try:
                response = self.session.get(url, timeout=5)
                self._log("GET", url, response.status_code, response.text)
                if response.status_code == 200:
                    data = response.json()
                    # Try multiple possible keys for tracks
                    tracks = []
                    if isinstance(data, dict):
                        if "library" in data and "tracks" in data["library"]:
                            tracks = data["library"]["tracks"]
                        elif "tracks" in data:
                            tracks = data["tracks"]
                        elif "data" in data and isinstance(data["data"], list):
                            tracks = data["data"]
                    elif isinstance(data, list):
                        tracks = data
                    
                    if tracks:
                        return [self._normalize_track(t) for t in tracks]

            except Exception as e:
                self._log("ERROR", url, 0, str(e))
        return []

    def get_favorites(self):
        url = f"{self.BASE_URL}/favorites"
        try:
            response = self.session.get(url, timeout=5)
            self._log("GET", url, response.status_code, response.text)
            if response.status_code == 200:
                data = response.json()
                favorites = data.get("favorites", [])
                return [self._normalize_track(t) for t in favorites]
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
        return []

    def add_favorite(self, track_data):
        url = f"{self.BASE_URL}/favorites"
        payload = {"track": track_data}
        try:
            response = self.session.post(url, json=payload, timeout=5)
            self._log("POST", url, response.status_code, response.text)
            return response.status_code in [200, 201]
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False

    def remove_favorite(self, track_id):
        url = f"{self.BASE_URL}/favorites"
        params = {"trackId": track_id}
        try:
            response = self.session.delete(url, params=params, timeout=5)
            self._log("DELETE", url, response.status_code, response.text)
            return response.status_code == 200
        except Exception as e:
            self._log("ERROR", url, 0, str(e))
            return False
