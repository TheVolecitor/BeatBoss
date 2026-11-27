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
  List<int> _ids = [];
  int _nextId = 0;
  int _current = -1;
  int? _autoplayStart;

  /// Snapshot of the user section taken when shuffle was switched on. Null
  /// while not shuffled.
  List<Track>? _shuffleOriginal;
  List<int>? _shuffleOriginalIds;

  UnmodifiableListView<Track> get tracks => UnmodifiableListView(_tracks);
  UnmodifiableListView<int> get ids => UnmodifiableListView(_ids);
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
    _shuffleOriginalIds = null;
    final newIds = List<int>.generate(tracks.length, (_) => _nextId++);
    if (shuffled && index >= 0 && index < tracks.length) {
      final first = tracks[index];
      final firstId = newIds[index];
      final restIndices = [
        for (var i = 0; i < tracks.length; i++)
          if (i != index) i,
      ]..shuffle(random);
      _shuffleOriginal = List.of(tracks);
      _shuffleOriginalIds = newIds;
      _tracks = [first, for (final i in restIndices) tracks[i]];
      _ids = [firstId, for (final i in restIndices) newIds[i]];
      _current = 0;
    } else {
      _tracks = List.of(tracks);
      _ids = newIds;
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
    if (removed > 0) {
      _tracks.removeRange(from, _tracks.length);
      _ids.removeRange(from, _ids.length);
    }
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
    _ids = [_ids[_current]];
    _current = 0;
    _autoplayStart = null;
    _shuffleOriginal = null;
    _shuffleOriginalIds = null;
  }

  /// Drops everything after the current track (including autoplay tracks).
  void removeUpcoming() {
    if (_current < 0 || _current >= _tracks.length) return;
    _tracks.removeRange(_current + 1, _tracks.length);
    _ids.removeRange(_current + 1, _ids.length);
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
    _ids.addAll(List<int>.generate(tracks.length, (_) => _nextId++));
  }

  void _insert(int index, Track track) {
    final i = index.clamp(0, _tracks.length);
    _tracks.insert(i, track);
    _ids.insert(i, _nextId++);
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
    _ids.removeAt(index);
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
    final id = _ids.removeAt(oldIndex);
    final target = min(newIndex, _tracks.length);
    _tracks.insert(target, track);
    _ids.insert(target, id);

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
    _shuffleOriginalIds = _ids.sublist(0, end);
    final from = _current + 1;
    if (from < end) {
      final indices = List<int>.generate(end - from, (i) => from + i)
        ..shuffle(random);
      _tracks.replaceRange(from, end, [for (final i in indices) _tracks[i]]);
      _ids.replaceRange(from, end, [for (final i in indices) _ids[i]]);
    }
  }

  /// Restores the order from before shuffling. Tracks removed since are
  /// dropped; tracks queued since go right after the current track. Autoplay
  /// tracks stay at the end.
  void unshuffle() {
    final original = _shuffleOriginal;
    final originalIds = _shuffleOriginalIds;
    if (original == null || originalIds == null) return;
    _shuffleOriginal = null;
    _shuffleOriginalIds = null;

    final end = _autoplayStart ?? _tracks.length;
    final region = _tracks.sublist(0, end);
    final regionIds = _ids.sublist(0, end);
    final autoplayTail = _tracks.sublist(end);
    final autoplayTailIds = _ids.sublist(end);
    final currentId =
        (_current >= 0 && _current < _ids.length) ? _ids[_current] : null;

    final presentIds = regionIds.toSet();
    final restored = <Track>[];
    final restoredIds = <int>[];
    final seenIds = <int>{};
    for (var i = 0; i < originalIds.length; i++) {
      final id = originalIds[i];
      if (presentIds.contains(id) && seenIds.add(id)) {
        restored.add(original[i]);
        restoredIds.add(id);
      }
    }
    final added = <Track>[];
    final addedIds = <int>[];
    for (var i = 0; i < regionIds.length; i++) {
      final id = regionIds[i];
      if (!seenIds.contains(id)) {
        added.add(region[i]);
        addedIds.add(id);
      }
    }
    if (added.isNotEmpty) {
      final at = currentId == null ? 0 : restoredIds.indexOf(currentId) + 1;
      final insertAt = at.clamp(0, restored.length);
      restored.insertAll(insertAt, added);
      restoredIds.insertAll(insertAt, addedIds);
    }

    _tracks = [...restored, ...autoplayTail];
    _ids = [...restoredIds, ...autoplayTailIds];
    _autoplayStart = autoplayTail.isEmpty ? null : restored.length;
    if (currentId != null) {
      _current = _ids.indexOf(currentId);
    }
  }

  void _normalizeAutoplay() {
    final start = _autoplayStart;
    if (start != null && start >= _tracks.length) _autoplayStart = null;
  }
}
