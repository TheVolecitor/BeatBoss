import 'dart:convert';

import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RecTrack.key ignores case and surrounding whitespace', () {
    const a = RecTrack(title: ' Song ', artist: 'ARTIST');
    const b = RecTrack(title: 'song', artist: 'artist ');

    expect(a.key, b.key);
  });

  test('RecShelf survives a JSON round trip', () {
    final shelf = RecShelf(
      id: 'station_recommended',
      title: 'Recommended for you',
      subtitle: 'sub',
      tracks: const [
        RecTrack(
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          imageUrl: 'https://img/x.png',
          match: 0.8,
        ),
      ],
      artists: const [RecArtist(name: 'Band', match: 0.4)],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    final copy = RecShelf.fromJson(
      jsonDecode(jsonEncode(shelf.toJson())) as Map<String, dynamic>,
    );

    expect(copy.id, shelf.id);
    expect(copy.title, shelf.title);
    expect(copy.subtitle, 'sub');
    expect(copy.kind, ShelfKind.tracks);
    expect(copy.fetchedAt, shelf.fetchedAt);
    expect(copy.tracks.single.title, 'Song');
    expect(copy.tracks.single.album, 'Album');
    expect(copy.tracks.single.match, 0.8);
    expect(copy.artists.single.name, 'Band');
  });

  test('RecShelf.fromJson tolerates missing fields', () {
    final shelf = RecShelf.fromJson({'id': 'x'});

    expect(shelf.tracks, isEmpty);
    expect(shelf.artists, isEmpty);
    expect(shelf.isEmpty, isTrue);
    expect(shelf.kind, ShelfKind.tracks);
  });
}
