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

// ---- Names for looking a song up in a recommendation source ----
//
// Addons often return decorated names ("Creep (Official Video)", an artist
// called "Radiohead - Topic" or "RadioheadVEVO"). Last.fm only knows the clean
// ones, so lookups try cleaned-up variants too.

final _titleDashSuffix = RegExp(
  r'\s*[-–—|]\s*(?:\d{4}\s+)?(official|lyrics?|audio|video|remaster(ed)?|live|hd|4k|mv|visuali[sz]er|music video)\b.*$',
  caseSensitive: false,
);
final _titleFeat =
    RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
final _artistTopic = RegExp(r'\s*[-–—]\s*topic$', caseSensitive: false);
final _artistVevo = RegExp(r'\s*vevo$', caseSensitive: false);
final _artistSplit = RegExp(
  r'\s*(?:,|;|&)\s*|\s+(?:feat\.?|ft\.?|featuring|x|with)\s+',
  caseSensitive: false,
);

/// [title] without brackets, "- Official Video" style suffixes, "feat." parts
/// and a leading "Artist - " (for any of [artists]). Falls back to [title]
/// when nothing is left.
String cleanTitleForLookup(String title, [List<String> artists = const []]) {
  var t = title.replaceAll(_brackets, ' ');
  t = t.replaceAll(_titleDashSuffix, '');
  t = t.replaceAll(_titleFeat, '');
  for (final artist in artists) {
    if (artist.trim().isEmpty) continue;
    t = t.replaceFirst(
      RegExp('^\\s*${RegExp.escape(artist.trim())}\\s*[-–—:]\\s*',
          caseSensitive: false),
      '',
    );
  }
  t = t.replaceAll(_spaces, ' ').trim();
  return t.isEmpty ? title.trim() : t;
}

/// The first artist of a credit like "A, B", "A & B" or "A feat. B", without
/// "- Topic" or "VEVO" channel suffixes.
String primaryArtist(String artist) {
  final a =
      artist.replaceAll(_artistTopic, '').replaceAll(_artistVevo, '').trim();
  final first = a.split(_artistSplit).first.trim();
  return first.isEmpty ? artist.trim() : first;
}

/// Artist names to try for an artist-level lookup, original first.
List<String> artistVariants(String artist) {
  final result = <String>[];
  for (final a in [artist.trim(), primaryArtist(artist)]) {
    if (a.isNotEmpty && !result.contains(a)) result.add(a);
  }
  return result;
}

/// (artist, title) pairs to try for a song lookup, the original first. A clean
/// name gives exactly one pair, so well-named songs cost a single request.
List<({String artist, String title})> lookupVariants(
    String artist, String title) {
  final primary = primaryArtist(artist);
  final cleaned = cleanTitleForLookup(title, [artist, primary]);
  final seen = <String>{};
  final result = <({String artist, String title})>[];
  for (final a in artistVariants(artist)) {
    for (final t in [title.trim(), cleaned]) {
      if (t.isNotEmpty && seen.add('$a|$t')) {
        result.add((artist: a, title: t));
      }
    }
  }
  return result;
}

/// Identity of a song for "have I already got this one" checks. Unlike
/// `RecTrack.key` it ignores decoration, so "Song (Remastered)" and "Song"
/// count as the same song.
String matchKey(String artist, String title) =>
    '${normalizeForMatch(artist)}|${normalizeForMatch(title)}';

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
