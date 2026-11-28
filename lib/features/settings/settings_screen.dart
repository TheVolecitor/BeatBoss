import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/recommendations/recommendation_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/services/listenbrainz_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/stream_cache_service.dart';
import '../../core/theme/app_theme.dart';
import '../addons/addons_screen.dart';
import '../player/player_seekbar.dart';

/// Settings Hub - organized into major stacks that open dedicated pages.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final lastFm = context.watch<LastFmService>();
    final listenBrainz = context.watch<ListenBrainzService>();
    final addons = context.watch<AddonService>();
    final streamCache = context.watch<StreamCacheService>();
    final isDark = settings.isDarkMode;

    final connectedIntegrations = [
      if (lastFm.isAuthenticated) 'Last.fm',
      if (listenBrainz.isAuthenticated) 'ListenBrainz',
    ];
    final integrationSummary = connectedIntegrations.isEmpty
        ? 'Connect Last.fm or ListenBrainz & pick recommendation source'
        : 'Connected: ${connectedIntegrations.join(', ')}';

    final seekLabel = PlayerSeekBar.styles
        .where((s) => s.id == settings.seekbarStyle)
        .map((s) => s.label)
        .firstOrNull ?? 'Normal';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                'Settings',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _SettingsSection(
              title: 'Preferences',
              isDark: isDark,
              children: [
                _SettingsNavRow(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: '${isDark ? 'Dark' : 'Light'} · $seekLabel seekbar',
                  isDark: isDark,
                  onTap: () => _open(context, const _AppearanceSettingsPage()),
                ),
                _SettingsNavRow(
                  icon: Icons.tune_outlined,
                  title: 'General & Playback',
                  subtitle:
                      'Prefetch ${settings.enablePrefetch ? '${settings.prefetchDuration}s' : 'Off'} · Crossfade ${settings.crossfadeDuration}s',
                  isDark: isDark,
                  onTap: () => _open(context, const _GeneralSettingsPage()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Connections & Storage',
              isDark: isDark,
              children: [
                _SettingsNavRow(
                  icon: Icons.hub_outlined,
                  title: 'Integrations & Recommendations',
                  subtitle: integrationSummary,
                  isDark: isDark,
                  onTap: () =>
                      _open(context, const _IntegrationsSettingsPage()),
                ),
                _SettingsNavRow(
                  icon: Icons.extension_outlined,
                  title: 'Addons & Sources',
                  subtitle: '${addons.installedAddons.length} installed',
                  isDark: isDark,
                  onTap: () => _open(context, const AddonsScreen()),
                ),
                _SettingsNavRow(
                  icon: Icons.folder_outlined,
                  title: 'Downloads & Storage',
                  subtitle:
                      '${settings.downloadedCount} downloads${streamCache.isSupported ? ' · ${streamCache.entryCount} cached' : ''}',
                  isDark: isDark,
                  onTap: () => _open(context, const _StorageSettingsPage()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _SettingsNavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        icon,
        color: isDark ? Colors.white70 : Colors.black54,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: isDark ? Colors.white30 : Colors.black26,
      ),
      onTap: onTap,
    );
  }
}

class _SettingsPageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsPageScaffold({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: children,
          ),
        ),
      ),
    );
  }
}

// ========== APPEARANCE SUBPAGE ==========

class _AppearanceSettingsPage extends StatefulWidget {
  const _AppearanceSettingsPage();

  @override
  State<_AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<_AppearanceSettingsPage> {
  int _previewValue = 420;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return _SettingsPageScaffold(
      title: 'Appearance',
      children: [
        _SettingsSection(
          title: 'Theme & Colors',
          isDark: isDark,
          children: [
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark Mode'),
              subtitle: const Text('Switch between dark and light surface'),
              trailing: Switch(
                value: isDark,
                onChanged: (_) => settings.toggleTheme(),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Album-Art Dynamic Colors'),
              subtitle: const Text(
                  'Tint fullscreen player from current track artwork'),
              trailing: Switch(
                value: settings.useDynamicPlayerColors,
                onChanged: (v) => settings.setUseDynamicPlayerColors(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Accent Color'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final preset in AppTheme.accentPresets)
                      GestureDetector(
                        onTap: () =>
                            settings.setAccentColor(preset.color.toARGB32()),
                        child: Tooltip(
                          message: preset.name,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: preset.color,
                              shape: BoxShape.circle,
                              border: settings.accentColorValue ==
                                      preset.color.toARGB32()
                                  ? Border.all(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                      width: 2.5,
                                    )
                                  : null,
                            ),
                            child: settings.accentColorValue ==
                                    preset.color.toARGB32()
                                ? const Icon(Icons.check,
                                    size: 15, color: Colors.black)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'Fullscreen Player & Seekbar',
          isDark: isDark,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seekbar Style',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: PlayerSeekBar(
                      style: settings.seekbarStyle,
                      value: _previewValue,
                      bufferedValue: 740,
                      seed: 'settings_preview',
                      isDark: isDark,
                      isPlaying: true,
                      trackHeight: settings.seekbarHeight,
                      wavyAmplitude: settings.wavyAmplitude,
                      onChanged: (v) => setState(() => _previewValue = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final style in PlayerSeekBar.styles)
                        ChoiceChip(
                          label: Text(style.label),
                          selected: settings.seekbarStyle == style.id,
                          selectedColor: AppTheme.primaryGreen
                              .withValues(alpha: isDark ? 0.22 : 0.18),
                          labelStyle: TextStyle(
                            fontWeight: settings.seekbarStyle == style.id
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: settings.seekbarStyle == style.id
                                ? AppTheme.primaryGreen
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          onSelected: (_) => settings.setSeekbarStyle(style.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.line_weight_rounded),
              title: const Text('Seekbar Thickness'),
              subtitle:
                  Text('${settings.seekbarHeight.toStringAsFixed(1)} px'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.seekbarHeight,
                  min: 2.0,
                  max: 6.0,
                  divisions: 8,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (v) => settings.setSeekbarHeight(v),
                ),
              ),
            ),
            if (settings.seekbarStyle == 'wavy')
              ListTile(
                leading: const Icon(Icons.waves_rounded),
                title: const Text('Wavy Squiggle Height'),
                subtitle:
                    Text('${settings.wavyAmplitude.toStringAsFixed(1)} px'),
                trailing: SizedBox(
                  width: 150,
                  child: Slider(
                    value: settings.wavyAmplitude,
                    min: 1.5,
                    max: 6.0,
                    divisions: 9,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (v) => settings.setWavyAmplitude(v),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.rounded_corner_rounded),
              title: const Text('Cover Art Corners'),
              subtitle: const Text('Roundness of fullscreen album art'),
              trailing: DropdownButton<double>(
                value: const [6.0, 16.0, 26.0]
                        .contains(settings.playerArtRadius)
                    ? settings.playerArtRadius
                    : 16.0,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 6.0, child: Text('Sharp')),
                  DropdownMenuItem(value: 16.0, child: Text('Rounded')),
                  DropdownMenuItem(value: 26.0, child: Text('Soft')),
                ],
                onChanged: (v) {
                  if (v != null) settings.setPlayerArtRadius(v);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Cover Art Drop Shadow'),
              subtitle: const Text('Soft shadow behind fullscreen album art'),
              trailing: Switch(
                value: settings.playerArtShadow,
                onChanged: (v) => settings.setPlayerArtShadow(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('Blurred Artwork Backdrop'),
              subtitle: const Text(
                  'Show blurred cover behind fullscreen gradient'),
              trailing: Switch(
                value: settings.playerShowBgArt,
                onChanged: (v) => settings.setPlayerShowBgArt(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.blur_on_outlined),
              title: const Text('Background Blur'),
              subtitle: Text(
                  '${settings.playerBgBlur.round()} px fullscreen artwork blur'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.playerBgBlur,
                  min: 0,
                  max: 90,
                  divisions: 9,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (v) => settings.setPlayerBgBlur(v),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.opacity_outlined),
              title: const Text('Backdrop Dim'),
              subtitle: Text(
                  '${(settings.playerGradientOpacity * 100).round()}% tint over blurred art'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.playerGradientOpacity,
                  min: 0.35,
                  max: 0.95,
                  divisions: 12,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (v) => settings.setPlayerGradientOpacity(v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'Lists, Cards & Lyrics',
          isDark: isDark,
          children: [
            ListTile(
              leading: const Icon(Icons.text_rotation_none_rounded),
              title: const Text('Marquee Long Titles & Artists'),
              subtitle: const Text(
                  'Scroll overflowing names after a 3s pause'),
              trailing: Switch(
                value: settings.enableMarquee,
                onChanged: (v) => settings.setEnableMarquee(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.density_small_rounded),
              title: const Text('Compact Track Lists'),
              subtitle:
                  const Text('Tighter row spacing in playlists and search'),
              trailing: Switch(
                value: settings.compactTrackList,
                onChanged: (v) => settings.setCompactTrackList(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Show Track Art in Lists'),
              subtitle: const Text('Display album thumbnails beside songs'),
              trailing: Switch(
                value: settings.showTrackArtInLists,
                onChanged: (v) => settings.setShowTrackArtInLists(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: const Text('Show Quality & Source Badges'),
              subtitle:
                  const Text('Display Hi-Res, bitrate and addon tags'),
              trailing: Switch(
                value: settings.showQualityBadges,
                onChanged: (v) => settings.setShowQualityBadges(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.crop_square_rounded),
              title: const Text('Card Corner Radius'),
              subtitle: const Text('Shape of list rows and settings cards'),
              trailing: DropdownButton<double>(
                value: const [4.0, 12.0, 20.0].contains(settings.cardRadius)
                    ? settings.cardRadius
                    : 12.0,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 4.0, child: Text('Sharp')),
                  DropdownMenuItem(value: 12.0, child: Text('Default')),
                  DropdownMenuItem(value: 20.0, child: Text('Soft')),
                ],
                onChanged: (v) {
                  if (v != null) settings.setCardRadius(v);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('Lyrics Text Size'),
              subtitle: Text(
                  '${settings.lyricsFontSize.round()} pt · Active line ${(settings.lyricsFontSize + 8).round()} pt'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.lyricsFontSize,
                  min: 14,
                  max: 28,
                  divisions: 7,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (v) => settings.setLyricsFontSize(v),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.format_align_center_rounded),
              title: const Text('Center-Align Lyrics'),
              subtitle: Text(settings.lyricsCentered
                  ? 'Centered karaoke layout'
                  : 'Left-aligned lyrics layout'),
              trailing: Switch(
                value: settings.lyricsCentered,
                onChanged: (v) => settings.setLyricsCentered(v),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.contrast_outlined),
              title: const Text('Inactive Lyrics Brightness'),
              subtitle: Text(
                  '${(settings.lyricsDimOpacity * 100).round()}% opacity for non-active lines'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: settings.lyricsDimOpacity,
                  min: 0.10,
                  max: 0.55,
                  divisions: 9,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (v) => settings.setLyricsDimOpacity(v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ========== GENERAL & PLAYBACK SUBPAGE ==========

class _GeneralSettingsPage extends StatelessWidget {
  const _GeneralSettingsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return _SettingsPageScaffold(
      title: 'General & Playback',
      children: [
        _SettingsSection(
          title: 'Playback',
          isDark: isDark,
          children: [
            ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('Instant Track Switching (Prefetch)'),
              subtitle: const Text('Load next track before current ends'),
              trailing: Switch(
                value: settings.enablePrefetch,
                onChanged: (val) => settings.setEnablePrefetch(val),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            if (settings.enablePrefetch)
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('Prefetch Duration'),
                subtitle: Text('${settings.prefetchDuration} seconds'),
                trailing: _buildStepper(
                  currentValue: settings.prefetchDuration,
                  step: 5,
                  minValue: 0,
                  isDark: isDark,
                  onChanged: (val) => settings.setPrefetchDuration(val),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Crossfade Duration'),
              subtitle: Text(settings.crossfadeDuration > 0
                  ? '${settings.crossfadeDuration} seconds'
                  : 'Off'),
              trailing: _buildStepper(
                currentValue: settings.crossfadeDuration,
                step: 1,
                minValue: 0,
                isDark: isDark,
                onChanged: (val) => settings.setCrossfadeDuration(val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'About',
          isDark: isDark,
          children: const [
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Version'),
              subtitle: Text('2.0.0 (Flutter)'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepper({
    required int currentValue,
    required int step,
    required int minValue,
    required bool isDark,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          color: isDark ? Colors.white70 : Colors.black87,
          onPressed: currentValue <= minValue
              ? null
              : () => onChanged(currentValue - step),
        ),
        SizedBox(
          width: 35,
          child: Text(
            '$currentValue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          color: isDark ? Colors.white70 : Colors.black87,
          onPressed: () => onChanged(currentValue + step),
        ),
      ],
    );
  }
}

// ========== INTEGRATIONS & RECOMMENDATIONS SUBPAGE ==========

class _IntegrationsSettingsPage extends StatelessWidget {
  const _IntegrationsSettingsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final providers = context.read<RecommendationService>().providers;
    final selected = !settings.recSourceEnabled
        ? SettingsService.recSourceOff
        : (providers.any((p) => p.id == settings.recProviderId)
            ? settings.recProviderId
            : providers.first.id);
    final sourceName = context.read<RecommendationService>().active.displayName;

    return _SettingsPageScaffold(
      title: 'Integrations & Recommendations',
      children: [
        _SettingsSection(
          title: 'Scrobbling & Accounts',
          isDark: isDark,
          children: [
            _LastFmTile(isDark: isDark),
            _ListenBrainzTile(isDark: isDark),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'Recommendations',
          isDark: isDark,
          children: [
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Recommendation source'),
              subtitle: const Text(
                  'Where home shelves, autoplay and radio come from. Off turns them all off.'),
              trailing: DropdownButton<String>(
                value: selected,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in providers)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.displayName),
                    ),
                  const DropdownMenuItem(
                    value: SettingsService.recSourceOff,
                    child: Text('Off'),
                  ),
                ],
                onChanged: (id) {
                  if (id != null) settings.setRecProviderId(id);
                },
              ),
            ),
            ListTile(
              enabled: settings.recSourceEnabled,
              leading: const Icon(Icons.recommend_outlined),
              title: const Text('Personal recommendations'),
              subtitle: Text(
                  'Uses your $sourceName account to fetch mixes and shelves for Home'),
              trailing: Switch(
                value: settings.useLastFmRecommendations,
                onChanged: settings.recSourceEnabled
                    ? (val) => settings.setUseLastFmRecommendations(val)
                    : null,
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              enabled: settings.recSourceEnabled,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Autoplay similar songs'),
              subtitle: Text(
                  "When your queue ends, sends the playing song's title and artist to $sourceName to find similar songs"),
              trailing: Switch(
                value: settings.autoplaySimilar,
                onChanged: settings.recSourceEnabled
                    ? (val) => settings.setAutoplaySimilar(val)
                    : null,
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Addon recommendations'),
              subtitle: const Text(
                  'Show featured tracks, albums and playlists from your addon on Home'),
              trailing: Switch(
                value: settings.useAddonCatalogRecommendations,
                onChanged: (val) =>
                    settings.setUseAddonCatalogRecommendations(val),
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ========== DOWNLOADS & STORAGE SUBPAGE ==========

class _StorageSettingsPage extends StatefulWidget {
  const _StorageSettingsPage();

  @override
  State<_StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<_StorageSettingsPage> {
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatMb(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

  void _clearStreamCache() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
            'This deletes the cached copies of streamed tracks. Your downloaded tracks are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final cache = context.read<StreamCacheService>();
              await cache.clear();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _clearDownloads() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Downloaded Tracks?'),
        content: const Text(
            'This will delete all downloaded tracks from your device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final settings = context.read<SettingsService>();
              await settings.clearCache();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Downloaded tracks cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final downloadManager = context.watch<DownloadManagerService>();
    final streamCache = context.watch<StreamCacheService>();
    final isDark = settings.isDarkMode;

    return _SettingsPageScaffold(
      title: 'Downloads & Storage',
      children: [
        _SettingsSection(
          title: 'Downloads',
          isDark: isDark,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Download Location'),
              subtitle: FutureBuilder<String>(
                future: settings.getDownloadLocation(),
                builder: (context, snapshot) =>
                    Text(snapshot.data ?? 'Loading...'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_done),
              title: const Text('Downloaded Tracks'),
              subtitle: Text('${settings.downloadedCount} tracks'),
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Storage Used'),
              subtitle: FutureBuilder<int>(
                future: settings.getStorageSize(),
                builder: (context, snapshot) =>
                    Text(_formatBytes(snapshot.data ?? 0)),
              ),
            ),
            if (downloadManager.hasActiveDownloads)
              ListTile(
                leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text(
                    '${downloadManager.activeDownloads.length} Active Downloads'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Clear Downloads',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: _clearDownloads,
            ),
          ],
        ),
        if (streamCache.isSupported) ...[
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Local Stream Cache',
            isDark: isDark,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cached),
                title: const Text('Enable local cache'),
                subtitle: const Text(
                    'Keep streamed tracks on this device so they replay faster and offline'),
                value: settings.localCacheEnabled,
                onChanged: (value) => settings.setLocalCacheEnabled(value),
              ),
              if (settings.localCacheEnabled)
                ListTile(
                  leading: const Icon(Icons.data_usage),
                  title: const Text('Cache size limit'),
                  subtitle: const Text(
                      'When full, the least recently played tracks are removed'),
                  trailing: DropdownButton<int>(
                    value: kCacheSizeOptionsMb.contains(settings.localCacheMaxMb)
                        ? settings.localCacheMaxMb
                        : null,
                    hint: Text(_formatMb(settings.localCacheMaxMb)),
                    items: [
                      for (final mb in kCacheSizeOptionsMb)
                        DropdownMenuItem(value: mb, child: Text(_formatMb(mb))),
                    ],
                    onChanged: (mb) {
                      if (mb != null) settings.setLocalCacheMaxMb(mb);
                    },
                  ),
                ),
              if (settings.localCacheEnabled || streamCache.entryCount > 0)
                ListTile(
                  leading: const Icon(Icons.folder_zip_outlined),
                  title: const Text('Cache Used'),
                  subtitle: Text(
                      '${_formatBytes(streamCache.usedBytes)} of ${_formatBytes(streamCache.maxBytes)} · ${streamCache.entryCount} tracks'),
                ),
              if (streamCache.entryCount > 0)
                ListTile(
                  leading:
                      const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: const Text('Clear Cache',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: _clearStreamCache,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: ListTileTheme(
            data: const ListTileThemeData(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 56,
                      endIndent: 16,
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LastFmTile extends StatefulWidget {
  final bool isDark;
  const _LastFmTile({required this.isDark});

  @override
  State<_LastFmTile> createState() => _LastFmTileState();
}

class _LastFmTileState extends State<_LastFmTile> {
  String? _pendingToken;
  bool _isLoading = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start(LastFmService lastFm) async {
    setState(() => _isLoading = true);
    final token = await lastFm.startAuth();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _pendingToken = token;
    });
    if (token == null) {
      _showMessage(
          lastFm.lastAuthError ?? 'Could not start Last.fm authorization');
    }
  }

  Future<void> _finish(LastFmService lastFm) async {
    setState(() => _isLoading = true);
    final success = await lastFm.completeAuth(_pendingToken!);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) _pendingToken = null;
    });
    if (!success) {
      _showMessage('Not authorized yet. Approve access in your browser, '
          'then try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastFm = context.watch<LastFmService>();

    if (lastFm.isAuthenticated) {
      return ListTile(
        leading: const Icon(Icons.radio, color: Colors.blue),
        title: const Text('Last.fm'),
        subtitle: Text('Connected as ${lastFm.username}'),
        trailing: TextButton(
          onPressed: () async => await lastFm.logout(),
          child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
        ),
      );
    }

    return ExpansionTile(
      leading: const Icon(Icons.radio, color: Colors.blue),
      title: const Text('Connect Last.fm'),
      subtitle: const Text('Scrobble your music history'),
      childrenPadding: const EdgeInsets.all(20),
      children: [
        Text(
          _pendingToken == null
              ? 'You will sign in on the Last.fm website. BeatBoss never sees '
                  'your password.'
              : 'Approve access in your browser, then come back and tap '
                  '"I\'ve authorized".',
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () => _pendingToken == null
                    ? _start(lastFm)
                    : _finish(lastFm),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.black,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.black))
                : Text(
                    _pendingToken == null
                        ? 'Connect with Last.fm'
                        : "I've authorized",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        if (_pendingToken != null)
          TextButton(
            onPressed: _isLoading
                ? null
                : () => setState(() => _pendingToken = null),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class _ListenBrainzTile extends StatefulWidget {
  final bool isDark;
  const _ListenBrainzTile({required this.isDark});

  @override
  State<_ListenBrainzTile> createState() => _ListenBrainzTileState();
}

class _ListenBrainzTileState extends State<_ListenBrainzTile> {
  final _tokenCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect(ListenBrainzService lb) async {
    setState(() => _isLoading = true);
    final ok = await lb.connect(_tokenCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      _tokenCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ListenBrainz as ${lb.username}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lb.lastAuthError ?? 'Could not connect ListenBrainz'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lb = context.watch<ListenBrainzService>();

    if (lb.isAuthenticated) {
      return ListTile(
        leading: const Icon(Icons.graphic_eq, color: Color(0xFFEB743B)),
        title: const Text('ListenBrainz'),
        subtitle: Text('Connected as ${lb.username}'),
        trailing: TextButton(
          onPressed: () async => await lb.logout(),
          child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
        ),
      );
    }

    return ExpansionTile(
      leading: const Icon(Icons.graphic_eq, color: Color(0xFFEB743B)),
      title: const Text('Connect ListenBrainz'),
      subtitle: const Text('Open-source scrobbling & recommendations'),
      childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const Text(
          'Paste your User Token from ListenBrainz settings. BeatBoss uses it to submit listens and power recommendations.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'ListenBrainz User Token',
            filled: true,
            fillColor: (widget.isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => _isLoading ? null : _connect(lb),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => lb.openTokenPage(),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Get Token'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _connect(lb),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.black,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text('Connect',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
