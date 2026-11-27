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

  /// When false (used on Home shelves), entries are NOT eagerly searched in
  /// the addon; instead cover art is fetched from CAA/Deezer via MBID/ISRC
  /// and tracks are resolved on-demand only when tapped/played.
  final bool eagerResolve;

  /// Optional hook to pre-warm resolved cover URLs on boot (e.g. into
  /// CachedNetworkImage) so below-the-fold cards don't wait for scroll.
  final void Function(String url)? onCoverResolved;

  RecShelf? _shelf;
  List<RecTrack> _recs = [];
  List<Track?> _tracks = [];
  List<bool> _done = [];
  final List<StreamSubscription<(int, Track?)>> _subs = [];
  int _coverGen = 0;
  bool _disposed = false;

  ResolvedShelf(
    this._resolver, {
    this.limit,
    this.eagerResolve = true,
    this.onCoverResolved,
  });

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
    if (!eagerResolve) return false;
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
    final previousByKey = <String, RecTrack>{
      for (final r in _recs) r.key: r,
    };
    _cancel();
    _coverGen++;
    _shelf = shelf;
    _recs = shelf?.kind == ShelfKind.tracks
        ? [
            for (final r in shelf!.tracks)
              if (previousByKey[r.key] case final prev?)
                r.copyWith(
                  imageUrl: (r.imageUrl == null || r.imageUrl!.isEmpty)
                      ? prev.imageUrl
                      : r.imageUrl,
                  isrc: (r.isrc == null || r.isrc!.isEmpty)
                      ? prev.isrc
                      : r.isrc,
                )
              else
                r,
          ]
        : [];
    _tracks = List<Track?>.filled(_recs.length, null, growable: true);
    _done = List<bool>.filled(_recs.length, false, growable: true);
    if (eagerResolve) {
      _resolveRange(0, _resolvable);
    } else {
      _resolveCovers(0, _resolvable);
    }
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
    if (eagerResolve) {
      _resolveRange(start, _recs.length);
    } else {
      _resolveCovers(start, _recs.length);
    }
    _notify();
  }

  /// Resolves a single entry on-demand (used when tapping a lazy shelf card).
  Future<Track?> resolveAt(int index) async {
    if (_disposed || index < 0 || index >= _recs.length) return null;
    if (_done[index]) return _tracks[index];
    final track = await _resolver.resolve(_recs[index]);
    if (_disposed || index >= _tracks.length) return track;
    _tracks[index] = track;
    _done[index] = true;
    _notify();
    return track;
  }

  /// Playable tracks, waiting until at least [min] have been found or the
  /// searches are over (or [timeout] passes), so Play works right after the
  /// first cards appear.
  Future<List<Track>> playableWhenReady(
      {int min = 8, Duration timeout = const Duration(seconds: 10)}) async {
    if (!eagerResolve) {
      final target = _resolvable < min ? _resolvable : min;
      for (var i = 0; i < target && !_disposed; i++) {
        await resolveAt(i);
      }
      return playable;
    }
    final deadline = DateTime.now().add(timeout);
    while (!_disposed &&
        playable.length < min &&
        isResolving &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return playable;
  }

  Future<void> _resolveCovers(int start, int end) async {
    final gen = _coverGen;
    if (_disposed || end <= start) return;

    // 0. Restore any 6-hour cached cover art / ISRC from disk and pre-warm
    //    any covers already present on the shelf.
    var cacheChanged = false;
    final cacheChecked = <int>{};
    for (var i = start; i < end && i < _recs.length; i++) {
      final rec = _recs[i];
      if (rec.imageUrl != null && rec.imageUrl!.isNotEmpty) {
        onCoverResolved?.call(rec.imageUrl!);
        continue;
      }
      final cached = _resolver.getCachedCover(rec.key);
      if (cached != null) {
        cacheChecked.add(i);
        final img = cached.imageUrl;
        final isrc = cached.isrc;
        if ((img != null && img.isNotEmpty) ||
            (isrc != null && isrc.isNotEmpty)) {
          _recs[i] = rec.copyWith(
            imageUrl: (img != null && img.isNotEmpty) ? img : rec.imageUrl,
            isrc: (isrc != null && isrc.isNotEmpty) ? isrc : rec.isrc,
          );
          cacheChanged = true;
          if (img != null && img.isNotEmpty) onCoverResolved?.call(img);
        }
      }
    }
    if (cacheChanged) _notify();

    // 1. Bulk-lookup ISRCs and CAA cover metadata via ListenBrainz
    //    /1/metadata/recording/ (30 MBIDs per 1.5s).
    final mbids = <String>[
      for (var i = start; i < end && i < _recs.length; i++)
        if (!cacheChecked.contains(i) &&
            (_recs[i].isrc == null || _recs[i].isrc!.isEmpty) &&
            _recs[i].mbid != null &&
            _recs[i].mbid!.isNotEmpty)
          _recs[i].mbid!,
    ];
    if (mbids.isNotEmpty) {
      final bulk = await _resolver.lookupMbidsBulk(mbids);
      if (_disposed || gen != _coverGen) return;
      var changed = false;
      for (var i = start; i < end && i < _recs.length; i++) {
        final mbid = _recs[i].mbid;
        if (mbid != null && bulk.containsKey(mbid)) {
          final info = bulk[mbid]!;
          final newIsrc = (info.isrc != null && info.isrc!.isNotEmpty)
              ? info.isrc
              : _recs[i].isrc;
          final newCover = (_recs[i].imageUrl == null || _recs[i].imageUrl!.isEmpty)
              ? info.coverUrl
              : _recs[i].imageUrl;
          if (newIsrc != _recs[i].isrc || newCover != _recs[i].imageUrl) {
            _recs[i] = _recs[i].copyWith(isrc: newIsrc, imageUrl: newCover);
            changed = true;
          }
          if (newCover != null && newCover.isNotEmpty) {
            onCoverResolved?.call(newCover);
            unawaited(_resolver.cacheCover(_recs[i].key,
                imageUrl: newCover, isrc: newIsrc));
          }
        }
      }
      if (changed) _notify();
    }

    // 2. Resolve cover art via Deezer (by ISRC only) for any items that have
    //    an ISRC but still lack cover art.
    final needDeezer = <int>[
      for (var i = start; i < end && i < _recs.length; i++)
        if (!cacheChecked.contains(i) &&
            (_recs[i].imageUrl == null || _recs[i].imageUrl!.isEmpty) &&
            _recs[i].isrc != null &&
            _recs[i].isrc!.isNotEmpty)
          i,
    ];
    const concurrency = 3;
    for (var offset = 0; offset < needDeezer.length; offset += concurrency) {
      if (_disposed || gen != _coverGen) return;
      final batch = needDeezer.skip(offset).take(concurrency).toList();
      await Future.wait(batch.map((i) async {
        final rec = _recs[i];
        final cover = await _resolver.resolveDeezerCover(isrc: rec.isrc);
        if (_disposed || gen != _coverGen || i >= _recs.length) return;
        if (cover != null && cover.isNotEmpty) {
          _recs[i] = _recs[i].copyWith(imageUrl: cover);
          onCoverResolved?.call(cover);
          unawaited(_resolver.cacheCover(rec.key,
              imageUrl: cover, isrc: rec.isrc));
        }
      }));
      if (!_disposed && gen == _coverGen) _notify();
    }

    // 3. For any remaining tracks still missing cover art, fall back to
    //    addon search and cache the result for 6 hours.
    final remaining = <int>[
      for (var i = start; i < end && i < _recs.length; i++)
        if (!cacheChecked.contains(i) &&
            (_recs[i].imageUrl == null || _recs[i].imageUrl!.isEmpty))
          i,
    ];
    const addonConcurrency = 4;
    for (var offset = 0;
        offset < remaining.length;
        offset += addonConcurrency) {
      if (_disposed || gen != _coverGen) return;
      final batch = remaining.skip(offset).take(addonConcurrency).toList();
      await Future.wait(batch.map((i) async {
        final rec = _recs[i];
        final track = await _resolver.resolve(rec);
        if (_disposed || gen != _coverGen || i >= _recs.length) return;
        if (track != null) {
          _tracks[i] = track;
          _done[i] = true;
          final cover = track.albumCover;
          final isrc = track.isrc ?? rec.isrc;
          if ((cover != null && cover.isNotEmpty) ||
              (isrc != null && isrc.isNotEmpty)) {
            _recs[i] = _recs[i].copyWith(
              imageUrl: (cover != null && cover.isNotEmpty)
                  ? cover
                  : _recs[i].imageUrl,
              isrc: isrc,
            );
          }
          if (cover != null && cover.isNotEmpty) {
            onCoverResolved?.call(cover);
          }
          unawaited(_resolver.cacheCover(rec.key, imageUrl: cover, isrc: isrc));
        } else {
          unawaited(_resolver.cacheCover(rec.key));
        }
      }));
      if (!_disposed && gen == _coverGen) _notify();
    }
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
