import 'dart:collection';
import 'dart:math';

import '../models/models.dart';

/// The playback queue: tracks, the current position, where the autoplay
/// section starts, and the original order while shuffled.
///
/// Pure Dart with no player or platform dependencies so the index bookkeeping
/// can be unit-tested. `AppAudioHandler` owns one and delegates to it.
///
/// The queue is split in two: the user's own tracks first, then, from
/// [autoplayStart] on, tracks that autoplay appended. Tracks the user adds
/// always land before the autoplay section.
class QueueModel {
  List<Track> _tracks = [];
  int _current = -1;
  int? _autoplayStart;

  /// Snapshot of the user section taken when shuffle was switched on. Null
  /// while not shuffled.
  List<Track>? _shuffleOriginal;

  UnmodifiableListView<Track> get tracks => UnmodifiableListView(_tracks);
  int get length => _tracks.length;
  bool get isEmpty => _tracks.isEmpty;
  bool get isNotEmpty => _tracks.isNotEmpty;

  int get currentIndex => _current;
  // ignore: unnecessary_getters_setters
  set currentIndex(int value) => _current = value;

  Track? get current =>
      (_current >= 0 && _current < _tracks.length) ? _tracks[_current] : null;

  /// Index of the first autoplay track, or null when there is none.
  int? get autoplayStart => _autoplayStart;

  bool get isShuffled => _shuffleOriginal != null;
  bool get hasNext => _current + 1 < _tracks.length;

  /// How many tracks come after the current one.
  int get upcomingCount => max(0, _tracks.length - _current - 1);

  /// Starts a new queue. With [shuffled], the track at [index] plays first and
  /// the rest are shuffled.
  void replace(
    List<Track> tracks, {
    int index = 0,
    bool shuffled = false,
    Random? random,
  }) {
    _autoplayStart = null;
    _shuffleOriginal = null;
    if (shuffled && index >= 0 && index < tracks.length) {
      final first = tracks[index];
      final rest = [...tracks]..removeAt(index);
      rest.shuffle(random);
      _shuffleOriginal = List.of(tracks);
      _tracks = [first, ...rest];
      _current = 0;
    } else {
      _tracks = List.of(tracks);
      _current = index;
    }
  }

  void clear() => replace(const [], index: -1);

  /// Removes the autoplay tracks that have not played yet and returns how many
  /// were removed. Autoplay tracks that already played stay as history; they
  /// stop being a separate section.
  int removeUpcomingAutoplay() {
    final start = _autoplayStart;
    if (start == null) return 0;
    final from = max(start, _current + 1);
    final removed = max(0, _tracks.length - from);
    if (removed > 0) _tracks.removeRange(from, _tracks.length);
    _autoplayStart = null;
    return removed;
  }

  /// Keeps only the current track (the "clear queue" operation): everything
  /// before and after it goes. Without a current track the queue is emptied.
  void keepOnlyCurrent() {
    final keep = current;
    if (keep == null) {
      clear();
      return;
    }
    _tracks = [keep];
    _current = 0;
    _autoplayStart = null;
    _shuffleOriginal = null;
  }

  /// Drops everything after the current track (including autoplay tracks).
  void removeUpcoming() {
    if (_current < 0 || _current >= _tracks.length) return;
    _tracks.removeRange(_current + 1, _tracks.length);
    _autoplayStart = null;
  }

  /// Puts [track] right after the current one.
  void insertNext(Track track) => _insert(_current + 1, track);

  /// Puts [track] at the end of the user's tracks, before any autoplay ones.
  void addToEnd(Track track) {
    _insert(max(_autoplayStart ?? _tracks.length, _current + 1), track);
  }

  /// Adds autoplay tracks at the end.
  void appendAutoplay(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _autoplayStart ??= _tracks.length;
    _tracks.addAll(tracks);
  }

  void _insert(int index, Track track) {
    final i = index.clamp(0, _tracks.length);
    _tracks.insert(i, track);
    final start = _autoplayStart;
    // Everything up to and including the new track belongs to the user.
    if (start != null) _autoplayStart = max(start, i) + 1;
  }

  /// Removes the track at [index]. Returns true when it was the current one;
  /// the current index then points at the next track (or past the end), and
  /// the caller decides what to play.
  bool removeAt(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    final wasCurrent = index == _current;
    _tracks.removeAt(index);
    if (index < _current) _current--;
    final start = _autoplayStart;
    if (start != null && index < start) _autoplayStart = start - 1;
    _normalizeAutoplay();
    return wasCurrent;
  }

  /// Moves a track so it ends up at [newIndex] (the position in the final
  /// list, as the handler's callers already pass it).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _tracks.length ||
        newIndex < 0 ||
        newIndex > _tracks.length) {
      return;
    }
    final oldStart = _autoplayStart;
    final movedFromAutoplay = oldStart != null && oldIndex >= oldStart;

    final track = _tracks.removeAt(oldIndex);
    final target = min(newIndex, _tracks.length);
    _tracks.insert(target, track);

    if (_current == oldIndex) {
      _current = target;
    } else if (oldIndex < _current && target >= _current) {
      _current--;
    } else if (oldIndex > _current && target <= _current) {
      _current++;
    }

    if (oldStart != null) {
      var start = oldStart;
      if (oldIndex < start) start--; // left the user section
      // Entered the user section. Dropping an autoplay track exactly on the
      // boundary keeps it in the autoplay section.
      if (target < start || (target == start && !movedFromAutoplay)) start++;
      _autoplayStart = start;
      _normalizeAutoplay();
    }
  }

  /// Shuffles the user's upcoming tracks (the ones after the current track).
  /// Played tracks and autoplay tracks keep their place.
  void shuffleUpcoming([Random? random]) {
    if (_shuffleOriginal != null) return;
    final end = _autoplayStart ?? _tracks.length;
    _shuffleOriginal = _tracks.sublist(0, end);
    final from = _current + 1;
    if (from < end) {
      final upcoming = _tracks.sublist(from, end)..shuffle(random);
      _tracks.replaceRange(from, end, upcoming);
    }
  }

  /// Restores the order from before shuffling. Tracks removed since are
  /// dropped; tracks queued since go right after the current track. Autoplay
  /// tracks stay at the end.
  void unshuffle() {
    final original = _shuffleOriginal;
    if (original == null) return;
    _shuffleOriginal = null;

    final end = _autoplayStart ?? _tracks.length;
    final region = _tracks.sublist(0, end);
    final autoplayTail = _tracks.sublist(end);
    final currentTrack = current;

    // Match by identity, counting occurrences so a track queued twice survives.
    final remaining = HashMap<Track, int>.identity();
    for (final t in region) {
      remaining[t] = (remaining[t] ?? 0) + 1;
    }
    final restored = <Track>[];
    for (final t in original) {
      final n = remaining[t] ?? 0;
      if (n > 0) {
        restored.add(t);
        remaining[t] = n - 1;
      }
    }
    final added = <Track>[];
    for (final t in region) {
      final n = remaining[t] ?? 0;
      if (n > 0) {
        added.add(t);
        remaining[t] = n - 1;
      }
    }
    if (added.isNotEmpty) {
      final at = currentTrack == null
          ? 0
          : restored.indexWhere((t) => identical(t, currentTrack)) + 1;
      restored.insertAll(at.clamp(0, restored.length), added);
    }

    _tracks = [...restored, ...autoplayTail];
    _autoplayStart = autoplayTail.isEmpty ? null : restored.length;
    if (currentTrack != null) {
      _current = _tracks.indexWhere((t) => identical(t, currentTrack));
    }
  }

  void _normalizeAutoplay() {
    final start = _autoplayStart;
    if (start != null && start >= _tracks.length) _autoplayStart = null;
  }
}
