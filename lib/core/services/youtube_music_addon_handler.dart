import 'package:darttubefix/darttubefix.dart';

import '../models/addon_models.dart';
import 'settings_service.dart';
import 'user_addon_handler.dart';

/// Built-in YouTube Music addon powered by `darttubefix`.
/// Provides search and direct audio stream resolution, with user-configurable
/// Eclipse-style settings (audio quality & codec preference).
class YouTubeMusicAddonHandler extends UserAddonHandler {
  static const String addonId = 'com.beatboss.ytmusic';

  final SettingsService _settings;

  YouTubeMusicAddonHandler({required SettingsService settingsService})
      : _settings = settingsService;

  @override
  AddonManifest get manifest => AddonManifest(
        id: addonId,
        name: 'YouTube Music',
        version: '1.0.0',
        description:
            'Built-in YouTube Music search and audio playback via darttubefix.',
        icon: 'assets/yt_music_icon.png',
        resources: const [
          AddonResource.search,
          AddonResource.stream,
          AddonResource.settings,
        ],
        types: const ['track'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        installedAt: DateTime.now(),
        isBuiltIn: true,
        settings: const [
          AddonSettingField(
            key: 'audioQuality',
            type: 'select',
            label: 'Audio quality',
            help: 'Choose between highest available bitrate or balanced data usage.',
            defaultValue: 'best',
            options: [
              AddonSettingOption(value: 'best', label: 'Best available'),
              AddonSettingOption(value: 'medium', label: 'Balanced (128kbps)'),
            ],
          ),
          AddonSettingField(
            key: 'preferOpus',
            type: 'toggle',
            label: 'Prefer Opus (WebM)',
            help: 'Uses Opus audio when available instead of AAC/M4A.',
            defaultValue: false,
          ),
        ],
      );

  int? _parseDurationSeconds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
    if (parts.length == 3) {
      return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
    }
    return null;
  }

  @override
  Future<AddonSearchResult?> search(String query) async {
    try {
      final search = Search(query);
      await search.fetch();
      final videos = search.videos;
      final tracks = <AddonTrack>[];
      for (final yt in videos.take(20)) {
        final id = yt.videoId;
        if (id.isEmpty) continue;
        tracks.add(AddonTrack(
          id: id,
          title: yt.title.isNotEmpty ? yt.title : 'Unknown Title',
          artist: yt.author.isNotEmpty ? yt.author : 'YouTube Music',
          duration: _parseDurationSeconds(yt.duration),
          artworkURL: yt.thumbnail.isNotEmpty
              ? yt.thumbnail
              : 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          addonId: addonId,
        ));
      }
      return AddonSearchResult(tracks: tracks);
    } catch (e) {
      print('[YouTubeMusicAddon] Search error: $e');
      return null;
    }
  }

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId) async {
    final stored = _settings.getAddonSettings(addonId);
    final preferOpus =
        stored['preferOpus'] == true || stored['preferOpus']?.toString() == 'true';
    final qualityPref = stored['audioQuality']?.toString() ?? 'best';

    // Try clients known to yield direct non-SABR audio-only streams.
    for (final client in const ['ANDROID_VR', 'IOS', 'VISION_OS', 'WEB_MUSIC']) {
      try {
        final yt = YouTube(
          'https://music.youtube.com/watch?v=$trackId',
          client: client,
        );
        final streams = await yt.streams;
        final audioQuery = streams.audioOnly;
        if (audioQuery.fmtStreams.isEmpty) continue;

        Stream? selected;
        if (preferOpus) {
          final opusList = audioQuery.filter(subtype: 'webm').orderBy('abr').fmtStreams;
          if (opusList.isNotEmpty) selected = opusList.last;
        }
        if (selected == null) {
          final mp4List = audioQuery.filter(subtype: 'mp4').orderBy('abr').fmtStreams;
          if (mp4List.isNotEmpty) selected = mp4List.last;
        }
        if (qualityPref == 'medium' && audioQuery.fmtStreams.isNotEmpty) {
          final sorted = List<Stream>.from(audioQuery.fmtStreams)
            ..sort((a, b) => (a.bitrate ?? 0).compareTo(b.bitrate ?? 0));
          selected = sorted.firstWhere(
            (s) => (s.bitrate ?? 0) >= 96000,
            orElse: () => sorted.last,
          );
        }
        selected ??= audioQuery.orderBy('abr').last;
        if (selected == null || selected.url.isEmpty || selected.includesVideoTrack) {
          continue;
        }

        final isOpus = selected.mimeType.contains('webm') ||
            selected.mimeType.contains('opus');
        return AddonStreamResult(
          url: selected.url,
          format: isOpus ? 'opus' : 'm4a',
          quality: selected.abr ?? (isOpus ? 'Opus' : 'AAC'),
          codec: isOpus ? 'opus' : 'aac',
          container: isOpus ? 'ogg' : 'mp4',
          manifest: 'none',
        );
      } catch (e) {
        print('[YouTubeMusicAddon] Client $client failed for $trackId: $e');
      }
    }
    return null;
  }
}
