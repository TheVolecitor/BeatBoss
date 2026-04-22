# Addon Development Guide

This guide explains how to develop addons for the application. Addons are external HTTP servers that provide search results, metadata, lyrics, and synchronization services.

## Manifest Configuration

Every addon must provide a `manifest.json` at its base URL.

```json
{
  "id": "com.example.addon",
  "name": "Example Music Provider",
  "version": "1.0.0",
  "description": "Provides access to example music streams.",
  "author": "Developer Name",
  "logo": "https://example.com/logo.png",
  "types": ["music"],
  "resources": ["search", "lyrics", "catalog", "library"]
}
```

### Resource Types
- search: Enables the search bar to query this provider.
- lyrics: Allows the app to fetch lyrics for the current track.
- catalog: Provides detailed information for artists, albums, and playlists.
- library: Enables cloud synchronization of libraries and favorites.

## Search API

Endpoint: `GET /search`

Query Parameters:
- q: The search query string.
- limit (optional): Maximum number of results to return.

Response Format:
```json
{
  "tracks": [
    {
      "id": "unique_track_id",
      "title": "Song Title",
      "artist": "Artist Name",
      "album": "Album Name",
      "duration": 240,
      "image": "https://example.com/cover.jpg",
      "streamUrl": "https://server.com/stream.mp3",
      "isHiRes": true
    }
  ]
}
```

## Catalog API

Endpoints for retrieving structured metadata.

- `GET /album/:id`
- `GET /artist/:id`
- `GET /playlist/:id`

## Lyrics API

Endpoint: `GET /lyrics`

Query Parameters:
- artist: Name of the artist.
- track: Title of the track.

Response: Plain text string containing the lyrics (LRC format supported).

## Library Sync API

Optional endpoints for enabling cross-device synchronization.

- `GET /libraries`: Returns a list of user libraries.
- `POST /libraries/:id/sync`: Synchronizes a list of tracks to a library.
- `POST /libraries/:id/remove`: Removes a specific track from a library.
- `POST /libraries/:id/update`: Renames a library.
- `DELETE /libraries/:id`: Deletes a library.

Note: Library ID $1$ is reserved for the Favourites system and cannot be renamed or deleted.
