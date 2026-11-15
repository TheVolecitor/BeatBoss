import 'package:beatboss/core/recommendations/track_matching.dart';
import 'package:flutter_test/flutter_test.dart';

// The names below are the ones Last.fm rejected when an addon returned them.
void main() {
  group('primaryArtist', () {
    test('strips "- Topic" and VEVO channel suffixes', () {
      expect(primaryArtist('Radiohead - Topic'), 'Radiohead');
      expect(primaryArtist('RadioheadVEVO'), 'Radiohead');
    });

    test('takes the first artist of a credit', () {
      expect(primaryArtist('Radiohead, Thom Yorke'), 'Radiohead');
      expect(primaryArtist('Daft Punk feat. Pharrell Williams'), 'Daft Punk');
      expect(primaryArtist('A; B'), 'A');
      expect(primaryArtist('Artist x Other'), 'Artist');
    });

    test('leaves single artists alone', () {
      expect(primaryArtist('Radiohead'), 'Radiohead');
      expect(primaryArtist('Malcolm X'), 'Malcolm X');
      expect(primaryArtist('  Daft Punk '), 'Daft Punk');
    });
  });

  group('cleanTitleForLookup', () {
    test('removes brackets and "- Official Video" style suffixes', () {
      expect(cleanTitleForLookup('Creep (Official Video)'), 'Creep');
      expect(cleanTitleForLookup('Creep (Remastered 2009)'), 'Creep');
      expect(cleanTitleForLookup('bad guy (Official Music Video)'), 'bad guy');
      expect(cleanTitleForLookup('Creep [HD]'), 'Creep');
      expect(cleanTitleForLookup('Song - Official Audio'), 'Song');
      expect(cleanTitleForLookup('Song - 2011 Remaster'), 'Song');
    });

    test('removes feat. parts', () {
      expect(cleanTitleForLookup('Get Lucky (feat. Pharrell Williams)'),
          'Get Lucky');
      expect(cleanTitleForLookup('Get Lucky feat. Pharrell Williams'),
          'Get Lucky');
    });

    test('removes a leading artist name', () {
      expect(cleanTitleForLookup('Radiohead - Creep', ['Radiohead']), 'Creep');
      expect(
          cleanTitleForLookup('radiohead: Creep (Official Video)', ['Radiohead']),
          'Creep');
    });

    test('leaves clean titles alone', () {
      expect(cleanTitleForLookup("Don't Stop Believin'"), "Don't Stop Believin'");
      expect(cleanTitleForLookup('Creep'), 'Creep');
    });

    test('never returns an empty title', () {
      expect(cleanTitleForLookup('(Official Video)'), '(Official Video)');
    });
  });

  group('lookupVariants', () {
    test('a clean name gives a single variant, so one request', () {
      final v = lookupVariants('Radiohead', 'Creep');

      expect(v, hasLength(1));
      expect(v.single.artist, 'Radiohead');
      expect(v.single.title, 'Creep');
    });

    test('the original comes first, then the cleaned ones', () {
      final v = lookupVariants('RadioheadVEVO', 'Radiohead - Creep (Official Video)');

      expect(v.first.artist, 'RadioheadVEVO');
      expect(v.first.title, 'Radiohead - Creep (Official Video)');
      expect(v.map((e) => '${e.artist}|${e.title}'),
          contains('Radiohead|Creep'));
    });

    test('has no duplicates', () {
      final v = lookupVariants('Radiohead', 'Creep (Live)');
      final keys = v.map((e) => '${e.artist}|${e.title}').toList();

      expect(keys.toSet().length, keys.length);
      expect(keys, contains('Radiohead|Creep'));
    });
  });

  test('artistVariants tries the original credit, then the first artist', () {
    expect(artistVariants('Radiohead, Thom Yorke'),
        ['Radiohead, Thom Yorke', 'Radiohead']);
    expect(artistVariants('Radiohead'), ['Radiohead']);
  });
}
