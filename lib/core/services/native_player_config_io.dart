import 'package:media_kit/media_kit.dart';

void configureNativePlayer(Player player) async {
  try {
    final dynamic nativePlayer = player.platform;
    await nativePlayer.setProperty('cache', 'yes');
    await nativePlayer.setProperty('cache-on-disk', 'no');
    await nativePlayer.setProperty('demuxer-max-bytes', '20MiB');
    await nativePlayer.setProperty('demuxer-max-back-bytes', '4MiB');
    await nativePlayer.setProperty('idle', 'yes');
    await nativePlayer.setProperty('ao', 'wasapi');
    await nativePlayer.setProperty('network-timeout', '30');
    print('[AudioHandler] Native player properties configured (RAM cache, idle, WASAPI).');
  } catch (e) {
    print('[AudioHandler] Failed to set native properties: $e');
  }
}
