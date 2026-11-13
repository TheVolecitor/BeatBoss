import 'rec_models.dart';

/// Minimum [scoreMatch] for an addon search hit to count as the recommended
/// track. A matching title with a different artist scores exactly 0.6, so the
/// threshold sits just above that: the artist has to match at least partly.
const double kMatchThreshold = 0.7;

final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _remasterSuffix = RegExp(r'\s[-–]\s.*remaster.*$');
final _featSuffix = RegExp(r'\b(feat|ft)\.?\s.*$');
final _punctuation = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final _spaces = RegExp(r'\s+');

/// Lower-cases and strips decoration so "Song (Remastered 2011)" and
/// "Song feat. X" compare equal to "Song".
String normalizeForMatch(String s) {
  var r = s.toLowerCase();
  r = r.replaceAll(_brackets, ' ');
  r = r.replaceAll(_remasterSuffix, '');
  r = r.replaceAll(_featSuffix, '');
  r = r.replaceAll(_punctuation, ' ');
  return r.replaceAll(_spaces, ' ').trim();
}

/// 1.0 for equal. 0.8 when the shorter string is a word-boundary prefix of
/// the longer one ("song" vs "song radio edit", "artist" vs "artist other").
/// 0.4 when it only appears elsewhere inside it ("song" vs "another song"),
/// which is usually a different track. Otherwise 0.0.
double _similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
  final shorter = a.length <= b.length ? a : b;
  final longer = identical(shorter, a) ? b : a;
  if (longer.startsWith('$shorter ')) return 0.8;
  if (longer.contains(shorter)) return 0.4;
  return 0.0;
}

/// Scores how well a candidate (an addon search hit) matches [rec]:
/// 0.6 x title similarity + 0.4 x artist similarity.
double scoreMatch(RecTrack rec, String candidateTitle, String candidateArtist) {
  final title =
      _similarity(normalizeForMatch(rec.title), normalizeForMatch(candidateTitle));
  final artist = _similarity(
      normalizeForMatch(rec.artist), normalizeForMatch(candidateArtist));
  return 0.6 * title + 0.4 * artist;
}
