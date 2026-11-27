import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A small least-recently-used map. Reading a key makes it the newest entry,
/// and adding past [capacity] drops the oldest one.
class LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  LruCache(this.capacity) : assert(capacity > 0);

  int get length => _map.length;

  bool containsKey(K key) => _map.containsKey(key);

  V? operator [](K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  V? remove(K key) => _map.remove(key);
}

/// Builds a [ColorScheme] from a track's artwork, so the player can take on
/// the colors of the cover. Results are cached (and shared between callers
/// asking for the same cover at the same time).
class ArtworkPaletteService {
  final LruCache<String, Future<ColorScheme?>> _cache = LruCache(30);

  /// The scheme for the image at [url], or null when there is no image or it
  /// can't be loaded. Never throws.
  Future<ColorScheme?> schemeFor(String? url, Brightness brightness) {
    if (url == null || url.isEmpty) return Future.value(null);
    final key = '$url|${brightness.name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final future = _build(url, brightness).then((scheme) {
      // Don't keep failures: the network may be back next time.
      if (scheme == null) _cache.remove(key);
      return scheme;
    });
    _cache[key] = future;
    return future;
  }

  Future<ColorScheme?> _build(String url, Brightness brightness) async {
    try {
      return await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(url, maxWidth: 200),
        brightness: brightness,
      );
    } catch (e) {
      print('ArtworkPaletteService: no palette for $url ($e)');
      return null;
    }
  }
}
