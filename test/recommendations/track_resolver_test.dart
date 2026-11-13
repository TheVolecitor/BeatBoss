import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:beatboss/core/recommendations/track_matching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rec = RecTrack(title: 'Song', artist: 'Artist');

  group('normalizeForMatch', () {
    test('strips brackets, feat. suffixes and remaster suffixes', () {
      expect(normalizeForMatch('Song (Remastered 2011)'), 'song');
      expect(normalizeForMatch('Song [Live]'), 'song');
      expect(normalizeForMatch('Song feat. Someone'), 'song');
      expect(normalizeForMatch('Song - 2011 Remaster'), 'song');
      expect(normalizeForMatch('  Hello,   World! '), 'hello world');
    });
  });

  group('scoreMatch', () {
    test('a decorated title with the same artist passes the threshold', () {
      expect(scoreMatch(rec, 'Song (Remastered 2011)', 'Artist'),
          greaterThanOrEqualTo(kMatchThreshold));
      expect(scoreMatch(rec, 'Song - 2011 Remaster', 'Artist'),
          greaterThanOrEqualTo(kMatchThreshold));
    });

    test('an artist list that contains the artist still matches', () {
      expect(scoreMatch(rec, 'Song', 'Artist, Other Artist'),
          greaterThanOrEqualTo(kMatchThreshold));
    });

    test('the same title by a different artist is rejected', () {
      expect(scoreMatch(rec, 'Song', 'Someone Else'), lessThan(kMatchThreshold));
    });

    test('a different title by the same artist is rejected', () {
      expect(scoreMatch(rec, 'Another Song Entirely', 'Artist'),
          lessThan(kMatchThreshold));
      expect(scoreMatch(const RecTrack(title: 'Home', artist: 'Artist'),
              'Take Me Home', 'Artist'),
          lessThan(kMatchThreshold));
    });

    test('a title with a trailing version label still matches', () {
      expect(scoreMatch(rec, 'Song Radio Edit', 'Artist'),
          greaterThanOrEqualTo(kMatchThreshold));
    });

    test('empty candidate fields score zero', () {
      expect(scoreMatch(rec, '', ''), 0.0);
    });
  });
}
