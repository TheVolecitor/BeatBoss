import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/last_fm_service.dart';

/// Settings Screen - theme toggle, download management, cache clearing
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _downloadLocation;
  int? _storageSize;
  int? _downloadedCount;

  @override
  void initState() {
    super.initState();
    _loadSettingsInfo();
  }

  Future<void> _loadSettingsInfo() async {
    final settings = context.read<SettingsService>();

    final location = await settings.getDownloadLocation();
    final size = await settings.getStorageSize();
    final count = settings.downloadedCount;

    setState(() {
      _downloadLocation = location;
      _storageSize = size;
      _downloadedCount = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final downloadManager = context.watch<DownloadManagerService>();
    final isDark = settings.isDarkMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 30),

          // Settings card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Theme toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Theme',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Light Mode',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Switch(
                          value: !isDark,
                          onChanged: (value) {
                            settings.toggleTheme();
                          },
                          activeThumbColor: AppTheme.primaryGreen,
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(height: 30),

                // Download location
                Text(
                  'Download Location',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _downloadLocation ?? 'Loading...',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 14,
                  ),
                ),

                const Divider(height: 30),

                // Active downloads
                if (downloadManager.hasActiveDownloads) ...[
                  Text(
                    'Active Downloads: ${downloadManager.activeDownloads.length}',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 15),
                ],

                // Storage info
                Text(
                  'Downloaded Tracks: ${_downloadedCount ?? 0}',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Storage Used: ${_formatBytes(_storageSize ?? 0)}',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 20),

                // Clear cache button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear Downloaded Tracks'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Sign Out Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final api = context.read<DabApiService>();
                final settings = context.read<SettingsService>();

                api.clearUser();
                await settings.clearUser();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Logged out successfully'),
                    backgroundColor: Colors.blue,
                  ));
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Last.fm Section
          _LastFmSection(isDark: isDark),

          const SizedBox(height: 30),

          // About section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.music_note,
                          color: Colors.black, size: 30),
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BeatBoss',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Version 1.5.0 (Flutter)',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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

class _LastFmSection extends StatefulWidget {
  final bool isDark;
  const _LastFmSection({required this.isDark});

  @override
  State<_LastFmSection> createState() => _LastFmSectionState();
}

class _LastFmSectionState extends State<_LastFmSection> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Import LastFmService logic
    // We assume context.watch works because we added ChangeNotifierProvider in main
    // But we need to import service file at top of settings_screen.dart
    final lastFm = context.watch<LastFmService>();
    final isDark = widget.isDark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radio, color: Colors.red, size: 28),
              const SizedBox(width: 10),
              Text(
                'Last.fm Scrobbling',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (lastFm.isAuthenticated) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connected',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                      Text(lastFm.username ?? 'Unknown User',
                          style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87)),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await lastFm.logout();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: const Text('Disconnect'),
              ),
            ),
          ] else ...[
            const Text(
                'Connect your Last.fm account to scrobble your music history.'),
            const SizedBox(height: 15),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        if (_usernameController.text.isEmpty ||
                            _passwordController.text.isEmpty) return;

                        setState(() => _isLoading = true);
                        final success = await lastFm.login(
                            _usernameController.text, _passwordController.text);
                        if (mounted) {
                          setState(() => _isLoading = false);
                          if (!success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Last.fm Login Failed: Invalid credentials')),
                            );
                          } else {
                            _usernameController.clear();
                            _passwordController.clear();
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Connect'),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
