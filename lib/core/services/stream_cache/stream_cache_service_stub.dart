import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../settings_service.dart';
import 'cache_models.dart';

/// Web stub: the browser has its own HTTP cache and no local filesystem, so
/// the local stream cache is unavailable and every call is a no-op.
class StreamCacheService extends ChangeNotifier {
  StreamCacheService({required SettingsService settingsService});

  bool get isSupported => false;
  bool get isEnabled => false;
  int get maxBytes => 0;
  int get usedBytes => 0;
  int get entryCount => 0;

  static String keyFor(Track track) =>
      '${track.addonId ?? 'none'}:${track.addonTrackId ?? track.id}';

  Future<void> init() async {}

  String? lookup(Track track) => null;

  void invalidate(Track track) {}

  void clearPlaying() {}

  Future<ProxyCacheHandle?> open(
    Track track,
    String url, {
    String? format,
    String? quality,
    Map<String, String>? headers,
  }) async =>
      null;

  CacheByteSink? openDashSink(Track track, {String? quality}) => null;

  Future<String?> promote(
    Track track, {
    required String destDir,
    required String safeName,
  }) async =>
      null;

  Future<void> clear() async {}
}
