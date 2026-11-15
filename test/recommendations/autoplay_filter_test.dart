import 'package:beatboss/core/recommendations/autoplay_controller.dart';
import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:beatboss/core/recommendations/track_matching.dart';
import 'package:flutter_test/flutter_test.dart';

RecTrack rec(String title, String artist) =>
    RecTrack(title: title, artist: artist);

List<String> titles(List<RecTrack> l) => l.map((e) => e.title).toList();

void main() {
  group('filterCandidates', () {
    test('drops songs that are already queued or recently played', () {
      final exclude = {matchKey('Artist A', 'Song 1')};
      final result = filterCandidates(
        [rec('Song 1', 'Artist A'), rec('Song 2', 'Artist B')],
        exclude,
      );

      expect(titles(result), ['Song 2']);
    });

    test('treats a decorated title as the same song', () {
      final exclude = {matchKey('Artist A', 'Song 1')};
      final result = filterCandidates(
        [
          rec('Song 1 (Remastered 2011)', 'Artist A'),
          rec('Song 1 - 2011 Remaster', 'Artist A'),
          rec('Song 1 feat. Someone', 'Artist A'),
        ],
        exclude,
      );

      expect(result, isEmpty);
    });

    test('keeps at most two songs per artist, in order', () {
      final result = filterCandidates([
        rec('A1', 'Same'),
        rec('A2', 'Same'),
        rec('A3', 'Same'),
        rec('B1', 'Other'),
        rec('A4', 'Same'),
      ], {});

      expect(titles(result), ['A1', 'A2', 'B1']);
    });

    test('the per-artist cap is configurable', () {
      final result = filterCandidates(
        [rec('A1', 'Same'), rec('A2', 'Same'), rec('A3', 'Same')],
        {},
        perArtist: 1,
      );

      expect(titles(result), ['A1']);
    });

    test('removes duplicates within the candidates', () {
      final result = filterCandidates([
        rec('Song', 'Artist'),
        rec('song', 'ARTIST'),
        rec('Song (Live)', 'Artist'),
      ], {});

      expect(result, hasLength(1));
    });

    test('an empty input gives an empty result', () {
      expect(filterCandidates([], {'x|y'}), isEmpty);
    });
  });

  group('matchKey', () {
    test('ignores case, brackets and feat. suffixes', () {
      expect(matchKey('ARTIST', 'Song (Live)'), matchKey('artist', 'song'));
      expect(matchKey('Artist', 'Song feat. X'), matchKey('Artist', 'Song'));
    });

    test('different songs get different keys', () {
      expect(matchKey('Artist', 'One'), isNot(matchKey('Artist', 'Two')));
      expect(matchKey('A', 'Song'), isNot(matchKey('B', 'Song')));
    });
  });
}
