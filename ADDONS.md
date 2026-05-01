# Addon Development Guide

This guide explains how to develop addons for the application. Addons are external HTTP servers that follow the Eclipse Music spec that allow developers to extend the application's capabilities by providing search results, metadata, lyrics, and synchronization services.

---

## 1. Manifest Configuration

Every addon must provide a `manifest.json` at its base URL.

```json
{
  "id": "com.example.addon",
  "name": "Example Music Provider",
  "version": "1.0.0",
  "description": "Provides access to example music streams.",
  "author": "Developer Name",
  "icon": "https://example.com/logo.png",
  "contentType": "music",
  "types": ["track", "album", "artist", "playlist"],
  "resources": ["search", "stream", "catalog", "lyrics", "library"]
}
```

### Manifest Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | String | Unique identifier (e.g., reverse domain notation). |
| `name` | String | Display name of the addon. |
| `version` | String | SemVer version string. |
| `description`| String | (Optional) Short description of the addon. |
| `icon` | String | (Optional) URL to a square icon image. |
| `contentType`| String | `music`, `audiobook`, or `podcast`. Defaults to `music`. |
| `types` | Array | (Optional) Supported types: `track`, `album`, `artist`, `playlist`. |
| `resources` | Array | (Optional) Capabilities: `search`, `stream`, `catalog`, `lyrics`, `library`. |

> [!NOTE]
> `types` and `resources` are optional. An addon only needs to implement what it provides. For example, a "stream-only" addon does not need to provide lyrics or catalog data; the application will automatically use other installed addons or built-in services (like the default lyrics provider) as fallbacks.

---

## 2. Search API

**Endpoint**: `GET /search`

**Query Parameters**:
- `q`: The search query string.
- `limit`: (Optional) Maximum number of results to return.

**Response Format**:
The response should contain arrays for the requested types.

```json
{
  "tracks": [
    {
      "id": "track_101",
      "title": "Starlight Harmony",
      "artist": "Echo Voyager",
      "album": "Celestial Echoes",
      "duration": 240,
      "artworkURL": "https://example.com/images/star.jpg",
      "streamURL": "https://example.com/streams/audio_file.mp3",
      "format": "mp3"
    }
  ],
  "albums": [
    {
      "id": "album_201",
      "name": "The Plan",
      "image": "https://example.com/images/plan_cover.jpg",
      "year": "2018"
    },
    {
      "id": "album_202",
      "name": "Retrograde Reality",
      "image": "https://example.com/images/retro_cover.jpg",
      "year": "1993"
    }
  ],
  "artists": [
    {
      "id": "artist_301",
      "name": "The Sound Architects",
      "image": "https://example.com/images/architects.jpg"
    },
    {
      "id": "artist_302",
      "name": "Digital Dreamers",
      "image": "https://example.com/images/dreamers.jpg"
    }
  ],
  "playlists": []
}
```

### Track Object Fields
- `id`: Unique track ID within the addon.
- `title`: Track title.
- `artist`: Artist name.
- `album`: (Optional) Album title.
- `duration`: (Optional) Duration in seconds.
- `artworkURL`: (Optional) URL to cover art. (Aliases: `image`, `cover`, `albumCover`).
- `streamURL`: (Optional) Direct playable URL. If provided, the app skips the `/stream/:id` call.
- `format`: (Optional) `mp3`, `flac`, `aac`, etc.

---

## 3. Stream API

If a track does not provide a `streamURL` in the search results, the app will call this endpoint to resolve a playable link.

**Endpoint**: `GET /stream/:id`

**Response Format**:
```json
{
  "url": "https://server.com/stream.mp3",
  "format": "mp3",
  "quality": "320kbps",
  "expiresAt": 1672531200
}
```

---

## 4. Catalog API

Provides detailed metadata for specific entities.

- `GET /album/:id`
- `GET /artist/:id`
- `GET /playlist/:id`

### Example: Album Response
```json
{
  "id": "album_456",
  "title": "Greatest Hits",
  "artist": "Famous Artist",
  "artworkURL": "https://example.com/album.jpg",
  "tracks": [
    { "id": "t1", "title": "Song 1", "artist": "Famous Artist" },
    { "id": "t2", "title": "Song 2", "artist": "Famous Artist" }
  ]
}
```

---

## 5. Lyrics API

**Endpoint**: `GET /lyrics`

**Query Parameters**:
- `artist`: Artist name.
- `title`: Track title.

**Response**:
Can be a plain text string (LRC format recommended) or a JSON object:
```json
{
  "lyrics": "[00:10.00] Line 1\n[00:15.00] Line 2..."
}
```

---

## 6. Library Sync API (BeatBoss Specific)

Enables cross-device synchronization of user libraries.

### Endpoints

| Method | Path | Description |
| :--- | :--- | :--- |
| `GET` | `/libraries` | Returns a list of user libraries. |
| `POST` | `/libraries` | Create a new library. Payload: `{"name": "..."}`. |
| `GET` | `/libraries/:id` | Returns a list of tracks in the library. |
| `POST` | `/libraries/:id/sync` | Batch add tracks. Payload: `{"tracks": [...]}`. |
| `POST` | `/libraries/:id/remove`| Remove a track. Payload: `{"trackId": "..."}`. |
| `POST` | `/libraries/:id/update`| Rename a library. Payload: `{"name": "..."}`. |
| `DELETE`| `/libraries/:id` | Delete a library. |

### Reserved Library IDs
- **ID `1`**: Reserved for the **Favourites** system. It cannot be renamed or deleted. The app automatically syncs liked songs to this library if an addon with `library` resource is installed.

---

## 7. Implementation Notes

- **CORS**: Ensure your server supports Cross-Origin Resource Sharing if the addon is accessed from a web-based version of the app.
- **Errors**: Return appropriate HTTP status codes (404 for not found, 500 for server errors).
- **Security**: The app currently does not send authentication headers to addons. If your addon requires auth, consider using a token in the Base URL (e.g., `https://addon.com/token/manifest.json`).

