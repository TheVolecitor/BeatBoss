import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'rec_models.dart';
import 'track_resolver.dart';

/// One entry of a [ResolvedShelf] that should be on screen: its recommended
/// title/artist, and the playable [track] once the addon search finished.
typedef ShelfItem = ({int index, RecTrack rec, Track? track});

/// A [RecShelf] plus the playable tracks found for it so far. Tracks are
/// resolved a few at a time and listeners are told after each one, so cards
/// can fill in progressively. Entries the addon has no match for drop out.
class ResolvedShelf extends ChangeNotifier {
  final TrackResolver _resolver;

  /// Only the first [limit] entries are resolved (all when null). Keeps the
  /// home screen from running dozens of searches per shelf.
  final int? limit;

  RecShelf? _shelf;
  List<RecTrack> _recs = [];
  List<Track?> _tracks = [];
  List<bool> _done = [];
  final List<StreamSubscription<(int, Track?)>> _subs = [];
  bool _disposed = false;

  ResolvedShelf(this._resolver, {this.limit});

  RecShelf? get shelf => _shelf;
  String get title => _shelf?.title ?? '';
  String? get subtitle => _shelf?.subtitle;
  bool get hasData => _recs.isNotEmpty;

  int get _resolvable => limit == null
      ? _recs.length
      : (_recs.length < limit! ? _recs.length : limit!);

  /// Entries to show: resolved ones and those still being searched.
  List<ShelfItem> get items => [
        for (var i = 0; i < _resolvable; i++)
          if (!(_done[i] && _tracks[i] == null))
            (index: i, rec: _recs[i], track: _tracks[i]),
      ];

  /// Playable tracks found so far, in shelf order.
  List<Track> get playable => _tracks.whereType<Track>().toList();

  /// Searches are still running.
  bool get isResolving {
    for (var i = 0; i < _resolvable; i++) {
      if (!_done[i]) return true;
    }
    return false;
  }

  /// Cover images of the first [count] playable tracks (falling back to the
  /// recommendation's own image), for a collage.
  List<String?> covers(int count) {
    final result = <String?>[];
    for (final item in items) {
      final url = item.track?.albumCover ?? item.rec.imageUrl;
      if (url != null && url.isNotEmpty) result.add(url);
      if (result.length == count) break;
    }
    return result;
  }

  /// Shows [shelf] and starts resolving it. Does nothing when the same shelf
  /// (same id and fetch time) is already shown, unless [force] is set.
  void setShelf(RecShelf? shelf, {bool force = false}) {
    if (!force &&
        shelf?.id == _shelf?.id &&
        shelf?.fetchedAt == _shelf?.fetchedAt) {
      return;
    }
    _cancel();
    _shelf = shelf;
    _recs = shelf?.kind == ShelfKind.tracks ? List.of(shelf!.tracks) : [];
    _tracks = List<Track?>.filled(_recs.length, null, growable: true);
    _done = List<bool>.filled(_recs.length, false, growable: true);
    _resolveRange(0, _resolvable);
    _notify();
  }

  /// Adds more recommendations to the end (the mix screen's "Load more").
  void append(List<RecTrack> more) {
    final known = _recs.map((r) => r.key).toSet();
    final fresh = more.where((r) => known.add(r.key)).toList();
    if (fresh.isEmpty) return;
    final start = _recs.length;
    _recs.addAll(fresh);
    _tracks.addAll(List<Track?>.filled(fresh.length, null));
    _done.addAll(List<bool>.filled(fresh.length, false));
    _resolveRange(start, _recs.length);
    _notify();
  }

  /// Playable tracks, waiting until at least [min] have been found or the
  /// searches are over (or [timeout] passes), so Play works right after the
  /// first cards appear.
  Future<List<Track>> playableWhenReady(
      {int min = 8, Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!_disposed &&
        playable.length < min &&
        isResolving &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return playable;
  }

  void _resolveRange(int start, int end) {
    if (end <= start) return;
    final sub =
        _resolver.resolveMany(_recs.sublist(start, end)).listen((event) {
      final (i, track) = event;
      final index = start + i;
      if (_disposed || index >= _tracks.length) return;
      _tracks[index] = track;
      _done[index] = true;
      _notify();
    });
    _subs.add(sub);
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}
