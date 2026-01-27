from googleapiclient.discovery import build
import re

class YouTubeAPI:
    def __init__(self, api_key, log_callback=None):
        self.api_key = api_key
        self.log_callback = log_callback
        self.youtube = None
        self._is_initialized = False
        
    def _ensure_init(self):
        if self._is_initialized:
            return
            
        if self.api_key:
            try:
                self.youtube = build('youtube', 'v3', developerKey=self.api_key)
                self._is_initialized = True
            except Exception as e:
                print(f"[YT_API] Initialization failed: {e}")
        else:
            print("[YT_API] WARNING: No API key provided. Search functionality will be disabled.")
            self._is_initialized = True

    def _log(self, method, url, status, body=None):
        if self.log_callback:
            self.log_callback(method, url, status, body)

    def extract_playlist_id(self, url):
        playlist_id = re.search(r"list=([^&]+)", url)
        if playlist_id:
            return playlist_id.group(1)
        return url # Assume it's already an ID if no match

    def search_yt(self, query, max_results=10):
        """Search YouTube for videos or parse playlist if URL is provided"""
        # Check if it's a playlist URL
        if "list=" in query or "playlist" in query.lower():
            return self._parse_playlist_to_results(query)
        
        # Otherwise do a video search
        self._ensure_init()
        if not self.youtube:
            print("[YT_API] Error: Cannot search, YouTube API not initialized.")
            return []
            
        try:
            request = self.youtube.search().list(
                part="snippet",
                q=query,
                type="video",
                maxResults=max_results,
                videoCategoryId="10"  # Music category
            )
            response = request.execute()
            self._log("YT_API", f"search.list(q={query})", 200, str(response)[:500])
            
            results = []
            for item in response.get("items", []):
                results.append({
                    "video_id": item["id"]["videoId"],
                    "title": item["snippet"]["title"],
                    "channel": item["snippet"]["channelTitle"],
                    "thumbnail": item["snippet"]["thumbnails"]["medium"]["url"]
                })
            return results
        except Exception as e:
            self._log("YT_API", f"search.list(q={query})", 0, str(e))
            return []
    
    def _parse_playlist_to_results(self, playlist_url):
        """Parse playlist and return as search results format"""
        try:
            tracks = self.get_playlist_tracks(playlist_url)
            results = []
            for i, title in enumerate(tracks):
                # Create a pseudo video_id from index for tracking
                results.append({
                    "video_id": f"playlist_{i}",
                    "title": title,
                    "channel": "From Playlist",
                    "thumbnail": "https://via.placeholder.com/120x90?text=Music"  # Placeholder
                })
            return results
        except Exception as e:
            self._log("YT_API", f"playlist parse", 0, str(e))
            return []

    def get_playlist_tracks(self, playlist_url):
        playlist_id = self.extract_playlist_id(playlist_url)
        tracks = []
        next_page_token = None
        page_count = 0
        max_pages = 20  # Safety limit to prevent infinite loops

        if not self.youtube:
            self._ensure_init()
            
        if not self.youtube:
            print("[YT_API] Error: Cannot fetch playlist, YouTube API not initialized.")
            return []

        try:
            while page_count < max_pages:
                request = self.youtube.playlistItems().list(
                    part="snippet",
                    playlistId=playlist_id,
                    maxResults=50,
                    pageToken=next_page_token
                )
                response = request.execute()
                self._log("YT_API", f"playlistItems.list(playlistId={playlist_id})", 200, str(response)[:500])

                items = response.get("items", [])
                if not items:
                    break  # No more items
                
                for item in items:
                    title = item["snippet"]["title"]
                    # Skip deleted/private videos
                    if title != "Deleted video" and title != "Private video":
                        tracks.append(title)

                next_page_token = response.get("nextPageToken")
                if not next_page_token:
                    break  # No more pages
                
                page_count += 1
                
                # For auto-generated playlists (like RDCLAK), limit to first 100 tracks
                if playlist_id.startswith("RD") and len(tracks) >= 100:
                    print(f"[YT_API] Auto-generated playlist detected, limiting to {len(tracks)} tracks")
                    break
                    
        except Exception as e:
            self._log("YT_API", f"playlistItems.list", 0, str(e))
            print(f"[YT_API] Error fetching playlist: {e}")
            # Return what we have so far
        
        print(f"[YT_API] Total tracks fetched: {len(tracks)}")
        return tracks
