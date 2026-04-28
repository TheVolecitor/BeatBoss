import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dash_service_stub.dart'
    if (dart.library.js_interop) 'dash_service_web.dart' as impl;

/// A cross-platform wrapper for DASH operations.
class DashService {
  static void init(String url, String proxyBase) {
    impl.DashService.init(url, proxyBase);
  }

  static void stop() {
    impl.DashService.stop();
  }

  static void pause() {
    // Logic handled by the specific implementation if needed
  }

  static void resume() {
    // Logic handled by the specific implementation if needed
  }

  static void seek(double seconds) {
    impl.DashService.seek(seconds);
  }

  static double getPosition() {
    return impl.DashService.getPosition();
  }

  static double getDuration() {
    return impl.DashService.getDuration();
  }

  /// Helper to convert raw XML or proxied URLs for the DASH engine
  static Future<String> getManifestUri(String url, {String? proxy, String? trackId}) async {
    return impl.DashService.getManifestUri(url, proxy: proxy, trackId: trackId);
  }
}
