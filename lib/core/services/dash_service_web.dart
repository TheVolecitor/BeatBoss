import 'dart:js_interop';
import 'dart:convert';

@JS('dash_init')
external void _initDash(JSString url, JSString proxyBase);

@JS('dash_stop')
external void _stopDash();

@JS('dash_pause')
external void _pauseDash();

@JS('dash_resume')
external void _resumeDash();

@JS('dash_seek')
external void _seekDash(JSNumber time);

@JS('dash_pos')
external JSNumber _getDashPosition();

@JS('dash_dur')
external JSNumber _getDashDuration();

class DashService {
  static void init(String url, String proxyBase) => _initDash(url.toJS, proxyBase.toJS);
  static void stop() => _stopDash();
  static void pause() => _pauseDash();
  static void resume() => _resumeDash();
  static void seek(double time) => _seekDash(time.toJS);
  static double getPosition() => _getDashPosition().toDartDouble;
  static double getDuration() => _getDashDuration().toDartDouble;

  static Future<String> getManifestUri(String url, {String? proxy, String? trackId}) async {
    if (url.startsWith('http')) {
      final p = proxy ?? 'https://webdownloadproxy.thevolecitor.workers.dev/?url=';
      return '$p${Uri.encodeComponent(url)}';
    } else {
      return 'data:application/dash+xml;base64,${base64Encode(utf8.encode(url))}';
    }
  }
}
