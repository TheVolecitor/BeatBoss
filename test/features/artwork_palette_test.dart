import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import 'package:beatboss/core/services/artwork_palette_service.dart';

void main() {
  group('LruCache', () {
    test('drops the oldest entry past capacity', () {
      final c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      c['c'] = 3;
      expect(c.containsKey('a'), isFalse);
      expect(c['b'], 2);
      expect(c['c'], 3);
      expect(c.length, 2);
    });

    test('reading an entry keeps it from being dropped', () {
      final c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      expect(c['a'], 1); // a is now the newest
      c['c'] = 3; // drops b
      expect(c.containsKey('b'), isFalse);
      expect(c['a'], 1);
    });

    test('overwriting a key does not grow the cache', () {
      final c = LruCache<String, int>(2);
      c['a'] = 1;
      c['a'] = 2;
      expect(c.length, 1);
      expect(c['a'], 2);
    });
  });

  group('ArtworkPaletteService', () {
    test('returns null without loading when there is no image', () async {
      final service = ArtworkPaletteService();
      expect(await service.schemeFor(null, Brightness.dark), isNull);
      expect(await service.schemeFor('', Brightness.dark), isNull);
    });
  });
}
