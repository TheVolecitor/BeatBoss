import 'dart:async';

/// Native stub for DashService (which is only used on Web).
/// Native platforms (Windows/Android/iOS) bypass this and use DashNativeParser + just_audio
/// directly in audio_handler.dart for DASH playback.
class DashService {
  static void init(String url, String proxyBase) {}
  static void stop() {}
  static void pause() {}
  static void resume() {}
  static void seek(double seconds) {}
  static double getPosition() => 0.0;
  static double getDuration() => 0.0;
  static Future<String> getManifestUri(String url, {String? proxy, String? trackId}) async => url;
}
