import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'cache_models.dart';

/// Called once a download finished. Returns the final path of the registered
/// cache file, or null when the file was rejected (it then stays at the .part
/// path until the session ends, so a player still reading it is not cut off).
typedef CacheFinalizer = Future<String?> Function(
    CachingSession session, String partPath, int size);

/// Parsed `Range: bytes=...` header. [valid] is false when the range cannot be
/// satisfied for the given resource length.
class ByteRange {
  final int start;
  final int end; // inclusive
  final bool valid;
  const ByteRange(this.start, this.end) : valid = true;
  const ByteRange.invalid()
      : start = 0,
        end = -1,
        valid = false;
}

/// Returns null when [header] is absent or not a single byte range (the
/// caller then serves the whole resource).
ByteRange? parseByteRange(String? header, int total) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$').firstMatch(header);
  if (m == null) return null;
  final a = m.group(1)!;
  final b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  int start;
  int end;
  if (a.isEmpty) {
    final suffix = int.parse(b);
    if (suffix == 0) return const ByteRange.invalid();
    start = math.max(0, total - suffix);
    end = total - 1;
  } else {
    start = int.parse(a);
    end = b.isEmpty ? total - 1 : math.min(int.parse(b), total - 1);
  }
  if (start >= total || start > end) return const ByteRange.invalid();
  return ByteRange(start, end);
}

/// A loopback HTTP server that sits between the player and a remote audio
/// URL. Every session downloads the remote file once, start to finish, at full
/// speed into a `.part` file, and serves the player from that file while it
/// grows. A seek past the downloaded part is answered with a separate range
/// request upstream; the player is moved back onto the file as soon as the
/// main download catches up.
class CachingStreamServer {
  CachingStreamServer({
    this.followWindow = 2 * 1024 * 1024,
    this.minPlay = kMinPlayToCache,
  });

  /// A request this close ahead of the download frontier waits for the
  /// download instead of opening a second upstream connection.
  final int followWindow;
  final Duration minPlay;

  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);
  final Map<String, CachingSession> _sessions = {};
  final math.Random _random = math.Random.secure();

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  /// Starts downloading [url] into [partPath] and returns the session whose
  /// [CachingSession.playbackUrl] the player should open.
  Future<CachingSession> open({
    required String url,
    required Map<String, String> headers,
    required String partPath,
    required CacheFinalizer onFinalize,
  }) async {
    await _ensureServer();
    final id = List.generate(
        16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final session = CachingSession._(
        this, id, Uri.parse(url), headers, partPath, onFinalize);
    _sessions[id] = session;
    session._startDownload();
    return session;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      final session =
          segments.length == 2 && segments[0] == 'c' ? _sessions[segments[1]] : null;
      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await session._serve(request);
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    for (final s in _sessions.values.toList()) {
      s.cancel();
    }
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }
}

class CachingSession implements ProxyCacheHandle {
  CachingSession._(this._server, this.id, this._url, this._headers,
      this.partPath, this._onFinalize);

  static const int _chunk = 128 * 1024;

  final CachingStreamServer _server;
  final String id;
  final Uri _url;
  final Map<String, String> _headers;
  final String partPath;
  final CacheFinalizer _onFinalize;

  RandomAccessFile? _raf;
  String? _finalPath;
  int _written = 0;
  int _total = -1;
  String? _contentType;
  bool _cacheable = false;
  bool _downloadActive = true;
  bool _complete = false;
  bool _registered = false;
  bool _cancelled = false;
  bool _closed = false;
  bool _released = false;
  int _clients = 0;
  HttpClientRequest? _mainRequest;
  final Completer<void> _headersReady = Completer<void>();
  final List<Completer<void>> _waiters = [];
  Future<void> _lock = Future<void>.value();

  /// Duration reported by the player, for the finalizer's sanity check.
  Duration? reportedDuration;

  @override
  String get playbackUrl => 'http://127.0.0.1:${_server._server!.port}/c/$id';

  /// Bytes downloaded so far (for tests and diagnostics).
  int get bytesWritten => _written;

  /// Content-Type of the upstream response, once known.
  String? get contentType => _contentType;

  /// The download is still running or the player is still attached.
  bool get isActive => !_closed && !_cancelled;

  /// Still downloading in the background after the player moved on.
  bool get isDetachedDownload => _released && _downloadActive && !_cancelled;

  bool get isComplete => _complete;

  Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _lock;
    final gate = Completer<void>();
    _lock = gate.future;
    return previous.then((_) => action()).whenComplete(gate.complete);
  }

  void _notify() {
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) w.complete();
    }
  }

  Future<void> _waitProgress() async {
    final c = Completer<void>();
    _waiters.add(c);
    await c.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _waiters.remove(c);
    });
  }

  // ---- main download ----------------------------------------------------

  void _startDownload() {
    _download();
  }

  Future<void> _download() async {
    try {
      final req = await _server._client.getUrl(_url);
      _mainRequest = req;
      _headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final resp = await req.close();

      if (_cancelled) return;
      if (resp.statusCode != 200 || resp.contentLength <= 0) {
        // Unknown length or an error: playback still works through a plain
        // passthrough, but there is nothing to cache.
        _cacheable = false;
        _headersReady.complete();
        final sub = resp.listen((_) {});
        await sub.cancel();
        _downloadActive = false;
        _notify();
        _disposeIfIdle();
        return;
      }

      _total = resp.contentLength;
      _contentType = resp.headers.value(HttpHeaders.contentTypeHeader);
      await File(partPath).parent.create(recursive: true);
      _raf = await File(partPath).open(mode: FileMode.write);
      _cacheable = true;
      _headersReady.complete();

      await for (final chunk in resp) {
        if (_cancelled) return;
        await _append(chunk);
      }
      if (_cancelled) return;

      if (_written == _total) {
        await _finishDownload();
      } else {
        _downloadFailed();
      }
    } catch (_) {
      if (!_headersReady.isCompleted) {
        _cacheable = false;
        _headersReady.complete();
      }
      if (!_cancelled) _downloadFailed();
    }
  }

  Future<void> _append(List<int> chunk) async {
    await _locked(() async {
      final raf = _raf;
      if (raf == null) return;
      await raf.setPosition(_written);
      await raf.writeFrom(chunk);
      _written += chunk.length;
    });
    _notify();
  }

  Future<void> _finishDownload() async {
    await _locked(() async {
      final raf = _raf;
      _raf = null;
      await raf?.flush();
      await raf?.close();
      String? finalPath;
      try {
        finalPath = await _onFinalize(this, partPath, _written);
      } catch (_) {
        finalPath = null;
      }
      _registered = finalPath != null;
      _finalPath = finalPath ?? partPath;
      _complete = true;
    });
    _downloadActive = false;
    _notify();
    _disposeIfIdle();
  }

  void _downloadFailed() {
    _downloadActive = false;
    _notify();
    _disposeIfIdle();
  }

  // ---- serving the player -----------------------------------------------

  Future<Uint8List> _readAt(int pos, int max) {
    return _locked(() async {
      if (_cancelled) return Uint8List(0);
      final n = math.min(max, _written - pos);
      if (n <= 0) return Uint8List(0);
      final raf = _raf;
      if (raf != null) {
        await raf.setPosition(pos);
        return await raf.read(n);
      }
      final path = _finalPath;
      if (path == null) return Uint8List(0);
      final file = await File(path).open();
      try {
        await file.setPosition(pos);
        return await file.read(n);
      } finally {
        await file.close();
      }
    });
  }

  Future<void> _serve(HttpRequest req) async {
    final resp = req.response;
    var clientGone = false;
    resp.done.then((_) {}, onError: (_) {}).whenComplete(() => clientGone = true);
    _clients++;
    try {
      await _headersReady.future.timeout(const Duration(seconds: 30));
      if (_cancelled) {
        resp.statusCode = HttpStatus.serviceUnavailable;
        return;
      }
      if (!_cacheable) {
        await _passthrough(req);
        return;
      }

      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      final range = parseByteRange(rangeHeader, _total);
      if (range != null && !range.valid) {
        resp.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        resp.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_total');
        return;
      }
      final start = range?.start ?? 0;
      final end = range?.end ?? _total - 1;

      resp.statusCode = range != null ? HttpStatus.partialContent : HttpStatus.ok;
      resp.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (_contentType != null) {
        resp.headers.set(HttpHeaders.contentTypeHeader, _contentType!);
      }
      resp.contentLength = end - start + 1;
      if (range != null) {
        resp.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$_total');
      }
      if (req.method == 'HEAD') return;

      var pos = start;
      while (pos <= end && !clientGone && !_cancelled) {
        if (pos < _written) {
          final chunk = await _readAt(pos, math.min(_chunk, end - pos + 1));
          if (chunk.isEmpty) break;
          resp.add(chunk);
          await resp.flush();
          pos += chunk.length;
        } else if (_downloadActive && pos - _written <= _server.followWindow) {
          await _waitProgress();
        } else {
          pos = await _serveDirect(resp, pos, end, () => clientGone);
        }
      }
    } catch (_) {
      // Client went away or the upstream failed; the player reconnects.
    } finally {
      _clients--;
      try {
        await resp.close();
      } catch (_) {}
      _disposeIfIdle();
    }
  }

  /// Streams [pos]..[end] straight from the upstream server (a seek landed
  /// beyond what has been downloaded). Returns the next position to serve;
  /// returns early once the main download has caught up so the caller can
  /// continue from the file.
  Future<int> _serveDirect(
      HttpResponse resp, int pos, int end, bool Function() gone) async {
    try {
      final req = await _server._client.getUrl(_url);
      _headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$pos-$end');
      final up = await req.close();
      if (up.statusCode != HttpStatus.ok &&
          up.statusCode != HttpStatus.partialContent) {
        await up.listen((_) {}).cancel();
        return end + 1;
      }
      // A server that ignores Range answers 200 with the whole body.
      var skip = up.statusCode == HttpStatus.ok ? pos : 0;
      var cur = pos;
      await for (final chunk in up) {
        if (gone() || _cancelled) break;
        var data = chunk;
        if (skip > 0) {
          if (skip >= data.length) {
            skip -= data.length;
            continue;
          }
          data = data.sublist(skip);
          skip = 0;
        }
        final take = math.min(data.length, end - cur + 1);
        resp.add(take == data.length ? data : data.sublist(0, take));
        await resp.flush();
        cur += take;
        if (cur > end) break;
        if (cur < _written) break; // the download caught up: back to the file
      }
      // An empty upstream answer would otherwise make the caller retry forever.
      return cur == pos ? end + 1 : cur;
    } catch (_) {
      return end + 1;
    }
  }

  /// Forwards a request upstream unchanged (used when the file cannot be
  /// cached, e.g. no Content-Length).
  Future<void> _passthrough(HttpRequest req) async {
    final out = req.response;
    final upReq = await _server._client.getUrl(_url);
    _headers.forEach(upReq.headers.set);
    upReq.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) upReq.headers.set(HttpHeaders.rangeHeader, range);
    final up = await upReq.close();
    out.statusCode = up.statusCode;
    for (final name in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final value = up.headers.value(name);
      if (value != null) out.headers.set(name, value);
    }
    await out.addStream(up);
  }

  // ---- lifecycle ----------------------------------------------------------

  @override
  void reportDuration(Duration duration) {
    reportedDuration = duration;
  }

  @override
  void release(Duration played) {
    if (_cancelled || _released) return;
    _released = true;
    if (!_complete && played < _server.minPlay) {
      cancel();
    } else {
      _disposeIfIdle();
    }
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    try {
      _mainRequest?.abort();
    } catch (_) {}
    if (!_headersReady.isCompleted) {
      _cacheable = false;
      _headersReady.complete();
    }
    _notify();
    _dispose();
  }

  /// A session outlives its download: the player may reconnect (a backward
  /// seek after the file is complete) until the handler releases the track.
  void _disposeIfIdle() {
    if (_released && _clients == 0 && !_downloadActive) _dispose();
  }

  Future<void> _dispose() async {
    if (_closed) return;
    _closed = true;
    _server._sessions.remove(id);
    await _locked(() async {
      try {
        await _raf?.close();
      } catch (_) {}
      _raf = null;
      // A registered file belongs to the cache index now; anything else is
      // a partial or rejected download.
      if (!_registered) {
        for (final path in {partPath, if (_finalPath != null) _finalPath!}) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    });
  }
}
