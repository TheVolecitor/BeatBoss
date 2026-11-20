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

final _versionLabel = RegExp(
  r'^(radio edit|edit|remix|mix|extended|acoustic|version|deluxe|instrumental|mono|stereo|live|clean|explicit|dub|session|demo|bonus|re recorded|orchestral)(\b|\s|$)',
  caseSensitive: false,
);

final _artistSeparators = RegExp(
  r'\s*(?:,|&|\/|;|\bfeat\.?|\bft\.?|\band\b|\bwith\b|\bx\b|\bvs\.?)\s*',
  caseSensitive: false,
);

/// 1.0 for equal. 0.8 when the shorter title is a prefix followed by a recognized
/// version label (e.g. "Song" vs "Song (Radio Edit)" or "Song Radio Edit").
double _titleSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
  final shorter = a.length <= b.length ? a : b;
  final longer = identical(shorter, a) ? b : a;
  if (longer.startsWith('$shorter ')) {
    final remainder = longer.substring(shorter.length + 1).trim();
    if (_versionLabel.hasMatch(remainder)) return 0.8;
  }
  return 0.0;
}

/// 1.0 for equal. 0.8 when complete artist tokens match across lists
/// (e.g. "Queen" matching "Queen, David Bowie"). Character substrings do not match.
double _artistSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
  final artistsA = a
      .split(_artistSeparators)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final artistsB = b
      .split(_artistSeparators)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  for (final partA in artistsA) {
    for (final partB in artistsB) {
      if (partA == partB) return 0.8;
    }
  }
  return 0.0;
}

/// Scores how well a candidate (an addon search hit) matches [rec]:
/// 0.6 x title similarity + 0.4 x artist similarity.
double scoreMatch(RecTrack rec, String candidateTitle, String candidateArtist) {
  final title = _titleSimilarity(
      normalizeForMatch(rec.title), normalizeForMatch(candidateTitle));
  final artist = _artistSimilarity(
      normalizeForMatch(rec.artist), normalizeForMatch(candidateArtist));
  return 0.6 * title + 0.4 * artist;
}
