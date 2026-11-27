import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/stream_cache_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/services/listenbrainz_service.dart';
import '../../core/recommendations/recommendation_service.dart';
import '../addons/addons_screen.dart';

/// Settings Screen - theme toggle, download management, cache clearing
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _category = 'All';
  static const _categories = ['All', 'Sources', 'Playback', 'Storage', 'General'];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadSettingsInfo() async {
    // Info is now handled via context.watch or FutureBuilder
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final downloadManager = context.watch<DownloadManagerService>();
    final streamCache = context.watch<StreamCacheService>();
    final isDark = settings.isDarkMode;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimationLimiter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: AnimationConfiguration.toStaggeredList(
                duration: const Duration(milliseconds: 375),
                childAnimationBuilder: (widget) => SlideAnimation(
                  verticalOffset: 50.0,
                  child: widget,
                ),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final cat in _categories)
                          ChoiceChip(
                            label: Text(cat),
                            selected: _category == cat,
                            selectedColor: AppTheme.primaryGreen
                                .withValues(alpha: isDark ? 0.25 : 0.2),
                            labelStyle: TextStyle(
                              fontWeight: _category == cat
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _category == cat
                                  ? AppTheme.primaryGreen
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            side: BorderSide(
                              color: _category == cat
                                  ? AppTheme.primaryGreen
                                  : (isDark ? Colors.white12 : Colors.black12),
                            ),
                            onSelected: (_) => setState(() => _category = cat),
                          ),
                      ],
                    ),
                  ),

                  // Addons Section
                  if (_category == 'All' || _category == 'Sources') ...[
                    _SettingsSection(
                      title: 'Addons & Sources',
                      isDark: isDark,
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.extension_rounded,
                                color: AppTheme.primaryGreen, size: 20),
                          ),
                          title: const Text('Manage Addons',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Install, reorder priority, configure settings, or toggle extensions'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const Scaffold(
                                        body: SafeArea(child: AddonsScreen()))));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Appearance Section
                  if (_category == 'All' || _category == 'General') ...[
                    _SettingsSection(
                      title: 'Appearance',
                      isDark: isDark,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.dark_mode_outlined),
                          title: const Text('Dark Mode'),
                          trailing: Switch(
                            value: isDark,
                            onChanged: (val) => settings.toggleTheme(),
                            activeThumbColor: AppTheme.primaryGreen,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.palette_outlined),
                          title: const Text('Accent Color'),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                for (final preset in AppTheme.accentPresets)
                                  GestureDetector(
                                    onTap: () => settings
                                        .setAccentColor(preset.color.toARGB32()),
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
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black,
                                                  width: 2.5,
                                                )
                                              : null,
                                        ),
                                        child: settings.accentColorValue ==
                                                preset.color.toARGB32()
                                            ? const Icon(Icons.check,
                                                size: 16, color: Colors.black)
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.linear_scale_rounded),
                          title: const Text('Fullscreen Seekbar Style'),
                          subtitle: const Text('Style used in fullscreen player'),
                          trailing: DropdownButton<String>(
                            value: const [
                              'normal',
                              'sleek',
                              'waveform',
                              'heartbeat',
                            ].contains(settings.seekbarStyle)
                                ? settings.seekbarStyle
                                : 'normal',
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                  value: 'normal', child: Text('Normal')),
                              DropdownMenuItem(
                                  value: 'sleek', child: Text('Sleek')),
                              DropdownMenuItem(
                                  value: 'waveform', child: Text('Waveform')),
                              DropdownMenuItem(
                                  value: 'heartbeat', child: Text('Heartbeat')),
                            ],
                            onChanged: (v) {
                              if (v != null) settings.setSeekbarStyle(v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Downloads Section
                  if (_category == 'All' || _category == 'Storage') ...[
                    _SettingsSection(
                      title: 'Downloads & Storage',
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
                        leading:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('Clear Downloads',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600)),
                        onTap: _clearCache,
                      ),
                      if (streamCache.isSupported) ...[
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
                            leading: const Icon(Icons.delete_sweep_outlined,
                                color: Colors.red),
                            title: const Text('Clear Cache',
                                style: TextStyle(
                                    color: Colors.red, fontWeight: FontWeight.w600)),
                            onTap: _clearStreamCache,
                          ),
                      ],
                    ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Integrations (Last.fm & ListenBrainz)
                  if (_category == 'All' || _category == 'Sources') ...[
                    _SettingsSection(
                      title: 'Integrations',
                      isDark: isDark,
                      children: [
                        _LastFmTile(isDark: isDark),
                        _ListenBrainzTile(isDark: isDark),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Recommendations: the source comes first, everything that
                  // needs it sits below and is disabled when it is off.
                  if (_category == 'All' || _category == 'Sources') ...[
                    _SettingsSection(
                      title: 'Recommendations',
                    isDark: isDark,
                    children: [
                      Builder(builder: (context) {
                        final providers =
                            context.read<RecommendationService>().providers;
                        final selected = !settings.recSourceEnabled
                            ? SettingsService.recSourceOff
                            : (providers.any((p) => p.id == settings.recProviderId)
                                ? settings.recProviderId
                                : providers.first.id);
                        return ListTile(
                          leading: const Icon(Icons.hub_outlined),
                          title: const Text('Recommendation source'),
                          subtitle: const Text(
                              'Where home shelves, autoplay and radio come from. Titles and artists of songs you play are sent to it to find similar music. Off turns them all off.'),
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
                        );
                      }),
                      ListTile(
                        enabled: settings.recSourceEnabled,
                        leading: const Icon(Icons.recommend_outlined),
                        title: const Text('Personal recommendations'),
                        subtitle: const Text(
                            'Uses your Last.fm username to fetch recommendations for the home screen'),
                        trailing: Switch(
                          value: settings.useLastFmRecommendations,
                          onChanged: settings.recSourceEnabled
                              ? (val) => settings.setUseLastFmRecommendations(val)
                              : null,
                          activeThumbColor: AppTheme.primaryGreen,
                        ),
                      ),
                      Builder(builder: (context) {
                        final sourceName =
                            context.read<RecommendationService>().active.displayName;
                        return ListTile(
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
                        );
                      }),
                      ListTile(
                        leading: const Icon(Icons.extension_outlined),
                        title: const Text('Addon recommendations'),
                        subtitle: const Text(
                            'Show the featured tracks, albums and playlists from your addon on the home screen'),
                        trailing: Switch(
                          value: settings.useAddonCatalogRecommendations,
                          onChanged: (val) =>
                              settings.setUseAddonCatalogRecommendations(val),
                          activeThumbColor: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Playback Section
                  if (_category == 'All' || _category == 'Playback') ...[
                    _SettingsSection(
                      title: 'Playback',
                    isDark: isDark,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bolt),
                        title: const Text('Instant Track Switching (Prefetch)'),
                        subtitle:
                            const Text('Load next track before current ends'),
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
                          subtitle:
                              Text('${settings.prefetchDuration} seconds'),
                          trailing: _buildStepper(
                            currentValue: settings.prefetchDuration,
                            step: 5,
                            minValue: 0,
                            isDark: isDark,
                            onChanged: (val) =>
                                settings.setPrefetchDuration(val),
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
                          onChanged: (val) =>
                              settings.setCrossfadeDuration(val),
                        ),
                      ),
                    ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // About
                  if (_category == 'All' || _category == 'General')
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

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
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

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Downloaded Tracks?'),
        content: const Text(
            'This will delete all downloaded tracks from your device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final settings = context.read<SettingsService>();
              await settings.clearCache();
              if (mounted) {
                Navigator.pop(context);
                _loadSettingsInfo();
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
  /// Token from a started auth flow; non-null while waiting for the user to
  /// approve access in the browser.
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
            const SizedBox(width: 12),
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
                            strokeWidth: 2, color: Colors.black),
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
