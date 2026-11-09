import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:beatboss/core/models/models.dart';
import 'package:beatboss/core/services/settings_service.dart';
import 'package:beatboss/core/services/stream_cache/caching_stream_server.dart';
// The io implementation directly: these tests need its injectable directory
// and server, which the web stub behind stream_cache_service.dart lacks.
import 'package:beatboss/core/services/stream_cache/stream_cache_service_io.dart';
import 'package:beatboss/core/utils/hive/hive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remote audio server with Range support. [chunkDelay] slows it down so a
/// test can act while the download is still running.
class FakeUpstream {
  FakeUpstream(this.data,
      {this.chunkSize = 64 * 1024, this.chunkDelay = Duration.zero});

  final Uint8List data;
  final int chunkSize;
  final Duration chunkDelay;
  late HttpServer _server;
  final List<String?> rangeHeaders = [];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  String get url => 'http://127.0.0.1:${_server.port}/track.flac';

  Future<void> _handle(HttpRequest req) async {
    final header = req.headers.value('range');
    rangeHeaders.add(header);
    final range = parseByteRange(header, data.length);
    final start = range?.start ?? 0;
    final end = range?.end ?? data.length - 1;
    final resp = req.response;
    resp.statusCode = range != null ? 206 : 200;
    resp.headers.set('content-type', 'audio/flac');
    resp.headers.set('accept-ranges', 'bytes');
    resp.contentLength = end - start + 1;
    if (range != null) {
      resp.headers.set('content-range', 'bytes $start-$end/${data.length}');
    }
    try {
      for (var p = start; p <= end; p += chunkSize) {
        final e = math.min(p + chunkSize - 1, end);
        resp.add(data.sublist(p, e + 1));
        await resp.flush();
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
      await resp.close();
    } catch (_) {}
  }
}

Uint8List makeData(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + (i >> 8)) & 0xFF));

Future<Uint8List> fetch(String url, {String? range}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    if (range != null) req.headers.set('range', range);
    final resp = await req.close();
    final out = BytesBuilder();
    await for (final chunk in resp) {
      out.add(chunk);
    }
    return out.toBytes();
  } finally {
    client.close(force: true);
  }
}

Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for condition');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Track track(String id, {String addon = 'tidal', int? duration}) => Track(
      id: id,
      title: 'Title $id',
      artist: 'Artist',
      addonId: addon,
      addonTrackId: id,
      duration: duration,
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stream_cache_test_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('parseByteRange', () {
    test('parses closed, open and suffix ranges', () {
      expect(parseByteRange('bytes=0-99', 1000)!.end, 99);
      expect(parseByteRange('bytes=500-', 1000)!.start, 500);
      expect(parseByteRange('bytes=500-', 1000)!.end, 999);
      final suffix = parseByteRange('bytes=-100', 1000)!;
      expect([suffix.start, suffix.end], [900, 999]);
    });

    test('clamps the end and rejects unsatisfiable ranges', () {
      expect(parseByteRange('bytes=900-5000', 1000)!.end, 999);
      expect(parseByteRange('bytes=1000-', 1000)!.valid, isFalse);
      expect(parseByteRange('bytes=50-10', 1000)!.valid, isFalse);
    });

    test('returns null when there is no usable range', () {
      expect(parseByteRange(null, 1000), isNull);
      expect(parseByteRange('items=0-1', 1000), isNull);
    });
  });

  group('CachingStreamServer', () {
    late CachingStreamServer server;
    late FakeUpstream upstream;

    tearDown(() async {
      await server.close();
      await upstream.stop();
    });

    Future<CachingSession> openSession(
      Uint8List data, {
      Duration chunkDelay = Duration.zero,
      Completer<String?>? finalized,
      bool accept = true,
      CachingStreamServer? customServer,
    }) async {
      upstream = FakeUpstream(data, chunkDelay: chunkDelay);
      await upstream.start();
      server = customServer ?? CachingStreamServer();
      return server.open(
        url: upstream.url,
        headers: const {},
        partPath: '${tmp.path}/track.part',
        onFinalize: (s, part, size) async {
          String? result;
          if (accept) {
            result = '${tmp.path}/track.flac';
            await File(part).rename(result);
          }
          finalized?.complete(result);
          return result;
        },
      );
    }

    test('downloads once and the player gets the same bytes', () async {
      final data = makeData(1500000);
      final finalized = Completer<String?>();
      final session = await openSession(data, finalized: finalized);

      final played = await fetch(session.playbackUrl);
      expect(played, data);

      final path = await finalized.future.timeout(const Duration(seconds: 10));
      expect(File(path!).readAsBytesSync(), data);
      // One upstream request: no second download for the cache.
      expect(upstream.rangeHeaders, [null]);
    });

    test('serves byte ranges, also after the file is complete', () async {
      final data = makeData(800000);
      final finalized = Completer<String?>();
      final session = await openSession(data, finalized: finalized);
      await fetch(session.playbackUrl);
      await finalized.future;

      final part = await fetch(session.playbackUrl, range: 'bytes=1000-4999');
      expect(part, data.sublist(1000, 5000));
      final tail = await fetch(session.playbackUrl, range: 'bytes=-100');
      expect(tail, data.sublist(data.length - 100));
    });

    test('a seek far past the downloaded part is served and the cache still completes',
        () async {
      final data = makeData(1500000);
      final finalized = Completer<String?>();
      final session = await openSession(data,
          chunkDelay: const Duration(milliseconds: 15),
          finalized: finalized,
          customServer: CachingStreamServer(followWindow: 64 * 1024));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      final seeked = await fetch(session.playbackUrl, range: 'bytes=1200000-');
      expect(seeked, data.sublist(1200000));

      // The seek used its own upstream range request...
      expect(upstream.rangeHeaders.whereType<String>(), isNotEmpty);
      // ...and the main download kept going until the file was complete.
      final path = await finalized.future.timeout(const Duration(seconds: 15));
      expect(File(path!).readAsBytesSync(), data);
    });

    test('a seek just ahead of the download waits for it instead of a second request',
        () async {
      final data = makeData(1500000);
      final finalized = Completer<String?>();
      final session = await openSession(data,
          chunkDelay: const Duration(milliseconds: 10), finalized: finalized);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      final seeked = await fetch(session.playbackUrl, range: 'bytes=600000-');
      expect(seeked, data.sublist(600000));

      expect(upstream.rangeHeaders, [null]);
      await finalized.future.timeout(const Duration(seconds: 15));
    });

    test('the player can reconnect until the track is released', () async {
      final data = makeData(500000);
      final finalized = Completer<String?>();
      final session = await openSession(data, finalized: finalized);
      await fetch(session.playbackUrl);
      await finalized.future;

      // Still served after the download is done and the first connection ended.
      expect(await fetch(session.playbackUrl, range: 'bytes=10-19'),
          data.sublist(10, 20));

      session.release(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Once released, the session is gone (the cached file itself stays).
      expect(await fetch(session.playbackUrl), isEmpty);
      expect(File('${tmp.path}/track.flac').existsSync(), isTrue);
    });

    test('skipping before the minimum play time deletes the partial file',
        () async {
      final finalized = Completer<String?>();
      final session = await openSession(makeData(3000000),
          chunkDelay: const Duration(milliseconds: 30), finalized: finalized);
      final part = File('${tmp.path}/track.part');
      await waitFor(() => part.existsSync() && session.bytesWritten > 0);

      session.release(const Duration(seconds: 3));

      await waitFor(() => !part.existsSync());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(finalized.isCompleted, isFalse);
      expect(File('${tmp.path}/track.flac').existsSync(), isFalse);
    });

    test('after the minimum play time the download finishes in the background',
        () async {
      final data = makeData(1000000);
      final finalized = Completer<String?>();
      final session = await openSession(data,
          chunkDelay: const Duration(milliseconds: 10), finalized: finalized);
      await waitFor(() => session.bytesWritten > 0);

      session.release(const Duration(seconds: 20)); // player moved on

      final path = await finalized.future.timeout(const Duration(seconds: 10));
      expect(File(path!).readAsBytesSync(), data);
    });

    test('a rejected file is removed once the player is done with it', () async {
      final data = makeData(600000);
      final finalized = Completer<String?>();
      final session =
          await openSession(data, finalized: finalized, accept: false);

      expect(await fetch(session.playbackUrl), data);
      expect(await finalized.future, isNull);
      // The rejected file stays readable while the player may still use it.
      expect(File('${tmp.path}/track.part').existsSync(), isTrue);

      session.release(const Duration(minutes: 1));
      await waitFor(() => !File('${tmp.path}/track.part').existsSync());
      expect(File('${tmp.path}/track.flac').existsSync(), isFalse);
    });
  });

  group('StreamCacheService', () {
    late SettingsService settings;
    late Directory cacheDir;
    late StreamCacheService cache;
    late FakeUpstream upstream;
    late CachingStreamServer server;

    setUp(() async {
      Hive.init('${tmp.path}/hive');
      settings = SettingsService();
      await settings.init();
      await settings.setLocalCacheEnabled(true);
      await settings.setLocalCacheMaxMb(2);
      cacheDir = Directory('${tmp.path}/cache');
      server = CachingStreamServer();
      cache = StreamCacheService(
          settingsService: settings, cacheDirectory: cacheDir, server: server);
      await cache.init();
      upstream = FakeUpstream(makeData(1000000));
      await upstream.start();
    });

    tearDown(() async {
      await server.close();
      await upstream.stop();
      await Hive.close();
    });

    /// Streams [t] through the cache like the player would, then waits until
    /// the finished file is registered.
    Future<void> cacheTrack(Track t) async {
      final handle = await cache.open(t, upstream.url);
      expect(handle, isNotNull);
      expect((await fetch(handle!.playbackUrl)).length, 1000000);
      await waitFor(() => cache.entryCount > 0 && cache.lookup(t) != null);
      cache.clearPlaying();
    }

    test('keys on addon and track id, not on title and artist', () {
      expect(StreamCacheService.keyFor(track('42')), 'tidal:42');
      expect(StreamCacheService.keyFor(track('42', addon: 'other')), 'other:42');
    });

    test('a streamed track is cached and then served from the file', () async {
      final t = track('42');
      expect(cache.lookup(t), isNull);
      await cacheTrack(t);

      final path = cache.lookup(t)!;
      expect(path.endsWith('tidal_42.flac'), isTrue);
      expect(File(path).readAsBytesSync(), makeData(1000000));
      expect(cache.usedBytes, 1000000);
      // A different track id is a miss even with identical title and artist.
      expect(cache.lookup(track('43')), isNull);
    });

    test('evicts the least recently played file, not the oldest written',
        () async {
      final a = track('a');
      final b = track('b');
      final c = track('c');
      await cacheTrack(a);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cacheTrack(b);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cache.lookup(a), isNotNull); // a is played again: b is now LRU
      cache.clearPlaying();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await cacheTrack(c); // 3 MB written, 2 MB limit

      expect(cache.lookup(b), isNull);
      expect(cache.lookup(a), isNotNull);
      expect(cache.lookup(c), isNotNull);
      expect(cache.usedBytes, lessThanOrEqualTo(cache.maxBytes));
    });

    test('a file larger than the limit is not cached', () async {
      await settings.setLocalCacheMaxMb(1); // 1 MiB limit, 1.2 MB track
      await upstream.stop();
      upstream = FakeUpstream(makeData(1200000));
      await upstream.start();

      final t = track('big');
      final handle = await cache.open(t, upstream.url);
      await fetch(handle!.playbackUrl);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cache.lookup(t), isNull);
      expect(cache.entryCount, 0);
    });

    test('a track with the wrong duration is rejected', () async {
      final t = track('dur', duration: 200);
      final handle = await cache.open(t, upstream.url);
      handle!.reportDuration(const Duration(seconds: 30)); // a 30 s preview
      await fetch(handle.playbackUrl);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cache.lookup(t), isNull);
    });

    test('does nothing while the cache is disabled', () async {
      await settings.setLocalCacheEnabled(false);
      expect(await cache.open(track('x'), upstream.url), isNull);
      expect(cache.lookup(track('x')), isNull);
    });

    test('promote moves the cached file into the downloads folder', () async {
      final t = track('42');
      await cacheTrack(t);

      final dest = await cache.promote(t,
          destDir: '${tmp.path}/downloads', safeName: 'Artist - Title 42');

      expect(dest, isNotNull);
      expect(File(dest!).readAsBytesSync(), makeData(1000000));
      expect(dest.endsWith('Artist - Title 42.flac'), isTrue);
      expect(cache.lookup(t), isNull);
      expect(cache.entryCount, 0);
      expect(await cache.promote(t, destDir: '${tmp.path}/downloads', safeName: 'x'),
          isNull);
    });

    test('invalidate and clear remove files', () async {
      final a = track('a');
      final b = track('b');
      await cacheTrack(a);
      await cacheTrack(b);

      final aPath = cache.lookup(a)!;
      cache.clearPlaying();
      cache.invalidate(a);
      expect(File(aPath).existsSync(), isFalse);
      expect(cache.lookup(a), isNull);

      await cache.clear();
      expect(cache.entryCount, 0);
      expect(cacheDir.listSync(), isEmpty);
    });

    test('init drops partial downloads, orphans and entries without a file',
        () async {
      final t = track('keep');
      await cacheTrack(t);
      final keepPath = cache.lookup(t)!;
      cache.clearPlaying();
      await cache.clear();
      await cacheTrack(t);

      File('${cacheDir.path}/left_over.part').writeAsStringSync('partial');
      File('${cacheDir.path}/orphan.flac').writeAsStringSync('orphan');

      final restarted = StreamCacheService(
          settingsService: settings, cacheDirectory: cacheDir, server: server);
      await restarted.init();

      expect(File('${cacheDir.path}/left_over.part').existsSync(), isFalse);
      expect(File('${cacheDir.path}/orphan.flac').existsSync(), isFalse);
      expect(File(keepPath).existsSync(), isTrue);
      expect(restarted.lookup(t), isNotNull);

      // A cached file that disappeared is dropped from the index.
      File(keepPath).deleteSync();
      restarted.clearPlaying();
      expect(restarted.lookup(t), isNull);
      expect(restarted.entryCount, 0);
    });
  });
}
