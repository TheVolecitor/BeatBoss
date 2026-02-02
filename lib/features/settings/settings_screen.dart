import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/last_fm_service.dart';

import 'package:flutter/foundation.dart'; // For platform check, though we might use service.isSupported

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
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Clear Downloads',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600)),
                onTap: _clearCache,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Integrations (Last.fm)
          _SettingsSection(
            title: 'Integrations',
            isDark: isDark,
            children: [
              _LastFmTile(isDark: isDark),
            ],
          ),

          const SizedBox(height: 20),

          // About & Account
          _SettingsSection(
            title: 'About & Account',
            isDark: isDark,
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Version'),
                subtitle: Text('1.5.0 (Flutter)'),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Sign Out',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final api = context.read<DabApiService>();
                  final set = context.read<SettingsService>();
                  api.clearUser();
                  await set.clearUser();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Logged out successfully')));
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                        : Colors.black.withOpacity(0.05),
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
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

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
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
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
                        _passwordController.text.isEmpty) {
                      return;
                    }
                    setState(() => _isLoading = true);
                    final success = await lastFm.login(
                        _usernameController.text, _passwordController.text);
                    if (mounted) {
                      setState(() => _isLoading = false);
                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Last.fm Login Failed')));
                      } else {
                        _usernameController.clear();
                        _passwordController.clear();
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.black,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.black))
                : const Text('Connect',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
