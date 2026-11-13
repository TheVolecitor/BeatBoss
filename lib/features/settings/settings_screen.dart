import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/stream_cache_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/recommendations/recommendation_service.dart';
import '../addons/addons_screen.dart';

/// Settings Screen - theme toggle, download management, cache clearing
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Addons Section
                  _SettingsSection(
                    title: 'Addons',
                    isDark: isDark,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.extension_outlined),
                        title: const Text('Manage Addons'),
                        subtitle:
                            const Text('Install and configure extensions'),
                        trailing: const Icon(Icons.chevron_right),
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

                  // Appearance Section
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
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Downloads Section
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

                  // Integrations (Last.fm)
                  _SettingsSection(
                    title: 'Integrations',
                    isDark: isDark,
                    children: [
                      _LastFmTile(isDark: isDark),
                      ListTile(
                        leading: const Icon(Icons.recommend_outlined),
                        title: const Text('Personal recommendations'),
                        subtitle: const Text(
                            'Uses your Last.fm username to fetch recommendations for the home screen'),
                        trailing: Switch(
                          value: settings.useLastFmRecommendations,
                          onChanged: (val) =>
                              settings.setUseLastFmRecommendations(val),
                          activeThumbColor: AppTheme.primaryGreen,
                        ),
                      ),
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
                      Builder(builder: (context) {
                        final providers =
                            context.read<RecommendationService>().providers;
                        final selected = providers.any(
                                (p) => p.id == settings.recProviderId)
                            ? settings.recProviderId
                            : providers.first.id;
                        return ListTile(
                          leading: const Icon(Icons.hub_outlined),
                          title: const Text('Recommendation source'),
                          trailing: DropdownButton<String>(
                            value: selected,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final p in providers)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.displayName),
                                ),
                            ],
                            onChanged: (id) {
                              if (id != null) settings.setRecProviderId(id);
                            },
                          ),
                        );
                      }),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Playback Section
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

                  // About
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
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 60, // Align with text start
                    endIndent: 20,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                children[i],
              ],
            ],
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
