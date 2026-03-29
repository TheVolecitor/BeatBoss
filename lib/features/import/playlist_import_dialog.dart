import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/youtube_service.dart';
import '../../core/services/spotify_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/import_service.dart';
import '../../core/models/models.dart';

class ImportItem {
  final String id;
  final String title;
  final String subtitle;

  ImportItem({required this.id, required this.title, required this.subtitle});
}

/// Playlist Import Dialog - import playlist tracks to library
class PlaylistImportDialog extends StatefulWidget {
  const PlaylistImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const PlaylistImportDialog(),
    );
  }

  @override
  State<PlaylistImportDialog> createState() => _PlaylistImportDialogState();
}

class _PlaylistImportDialogState extends State<PlaylistImportDialog> {
  final TextEditingController _urlController = TextEditingController();

  // State mgmt
  int _step = 0; // 0: URL input, 1: Select Tracks, 2: Select Library, 3: Importing
  List<ImportItem> _playlistItems = [];
  Map<String, bool> _selectedItems = {};
  bool _isLoading = false;
  String? _error;

  Future<void> _fetchPlaylist() async {
    final url = _urlController.text;
    if (url.isEmpty) return;

    final ytService = context.read<YouTubeService>();
    final spotifyService = context.read<SpotifyService>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    List<ImportItem> items = [];
    try {
      if (ytService.isValidPlaylistUrl(url)) {
        final ytItems = await ytService.getPlaylistTracks(url);
        items = ytItems
            .map((e) =>
                ImportItem(id: e.videoId, title: e.title, subtitle: e.channel))
            .toList();
      } else if (spotifyService.isValidPlaylistUrl(url)) {
        final spItems = await spotifyService.getPlaylistTracks(url);
        // Generate unique ID for Spotify items using index or title signature
        items = spItems
            .asMap()
            .entries
            .map((e) => ImportItem(
                id: '${e.key}_${e.value.title}', // Temporary ID
                title: e.value.title,
                subtitle: e.value.artist))
            .toList();
      } else {
        throw Exception(
            'Invalid URL. Please enter a valid YouTube playlist URL.');
      }

      if (items.isEmpty) {
        throw Exception('No tracks found or playlist is private/empty.');
      }

      setState(() {
        _playlistItems = items;
        _selectedItems = {for (var item in items) item.id: true};
        _isLoading = false;
        _step = 1; // Move to selection step
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
      });
    }
  }

  void _goToLibrarySelection() {
    final selectedCount = _selectedItems.values.where((e) => e).length;
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No tracks selected')));
      return;
    }
    setState(() => _step = 2);
  }

  void _startImport(String libraryId) {
    final selectedTracks =
        _playlistItems.where((i) => _selectedItems[i.id] == true).toList();

    setState(() {
      _step = 3;
    });

    final api = context.read<DabApiService>();
    final importService = context.read<ImportService>();

    importService.startImport(
      api: api,
      libraryId: libraryId,
      tracks: selectedTracks,
    ).then((_) {
      // Auto-close if finished and not backgrounded
      if (mounted && importService.statusMessage == 'Done!' && !importService.isBackgrounded) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Import complete: ${importService.importedCount} / ${importService.totalTracks} tracks added')),
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.playlist_play, color: AppTheme.primaryGreen),
          SizedBox(width: 10),
          Text('Playlist Import'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: _buildContent(isDark),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryGreen));
    }

    switch (_step) {
      case 0: // URL Input
        return Column(
          children: [
            const Text(
                'Enter a YouTube or Spotify Playlist URL to fetch tracks.'),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'YouTube or Spotify Playlist URL...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _fetchPlaylist(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        );

      case 1: // Track Selection
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Found ${_playlistItems.length} tracks'),
                TextButton(
                  onPressed: () {
                    setState(() {
                      final allSelected = _selectedItems.values.every((e) => e);
                      _selectedItems.updateAll((key, val) => !allSelected);
                    });
                  },
                  child: const Text('Toggle All'),
                )
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _playlistItems.length,
                itemBuilder: (context, index) {
                  final item = _playlistItems[index];
                  return CheckboxListTile(
                    value: _selectedItems[item.id] ?? false,
                    onChanged: (val) =>
                        setState(() => _selectedItems[item.id] = val ?? false),
                    title: Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    activeColor: AppTheme.primaryGreen,
                  );
                },
              ),
            ),
          ],
        );

      case 2: // Library Selection
        return FutureBuilder<List<MusicLibrary>>(
          future: context.read<DabApiService>().getLibraries(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final libs = snapshot.data!;
            if (libs.isEmpty) {
              return const Center(child: Text('No libraries found.'));
            }

            return Column(
              children: [
                const Text('Select Library to Import Into:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: libs.length,
                    itemBuilder: (context, index) {
                      final lib = libs[index];
                      return ListTile(
                        leading: const Icon(Icons.library_music,
                            color: AppTheme.primaryGreen),
                        title: Text(lib.name),
                        onTap: () => _startImport(lib.id),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );

      case 3: // Importing Progress
        return Consumer<ImportService>(
          builder: (context, importService, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Importing Tracks...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: importService.progress,
                  backgroundColor: Colors.grey[800],
                  color: AppTheme.primaryGreen,
                  minHeight: 10,
                ),
                const SizedBox(height: 10),
                Text('${importService.importedCount} / ${importService.totalTracks}'),
                const SizedBox(height: 20),
                Text(importService.statusMessage,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            );
          },
        );

      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildActions() {
    if (_step == 3) {
      final importService = context.watch<ImportService>();
      return [
        TextButton(
          onPressed: () {
            importService.stopImport();
          },
          child: const Text('Stop', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () {
            importService.setBackground(true);
            Navigator.pop(context); // Hide dialog
          },
          child: const Text('Run in background'),
        ),
      ];
    }

    return [
      if (_step > 0)
        TextButton(
          onPressed: () => setState(() => _step--),
          child: const Text('Back'),
        )
      else
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      if (_step == 0)
        ElevatedButton(
          onPressed: _fetchPlaylist,
          child: const Text('Next'),
        ),
      if (_step == 1)
        ElevatedButton(
          onPressed: _goToLibrarySelection,
          child: const Text('Next'),
        ),
    ];
  }
}
