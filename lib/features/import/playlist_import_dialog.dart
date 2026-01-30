import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/youtube_service.dart';
import '../../core/services/spotify_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/settings_service.dart';
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
  int _step =
      0; // 0: URL input, 1: Select Tracks, 2: Select Library, 3: Importing
  List<ImportItem> _playlistItems = [];
  Map<String, bool> _selectedItems = {};
  bool _isLoading = false;
  String? _error;

  // Import Progress
  int _importedCount = 0;
  int _totalToImport = 0;
  String _currentImportingTitle = '';

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

  Future<void> _startImport(String libraryId) async {
    final selectedTracks =
        _playlistItems.where((i) => _selectedItems[i.id] == true).toList();

    setState(() {
      _step = 3;
      _totalToImport = selectedTracks.length;
      _importedCount = 0;
    });

    final api = context.read<DabApiService>();

    for (final item in selectedTracks) {
      if (!mounted) break;

      setState(() => _currentImportingTitle = item.title);

      try {
        // Clean title for better search
        String query = '${item.title} ${item.subtitle}'
            .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
            .trim();

        final results = await api.search(query, limit: 1);

        if (results != null && results.tracks.isNotEmpty) {
          final track = results.tracks.first;
          await api.addTrackToLibrary(libraryId, track);
          setState(() => _importedCount++);
        }
      } catch (e) {
        print('Import error for ${item.title}: $e');
      }

      // Small delay to prevent rate limits if necessary
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      setState(() => _currentImportingTitle = 'Done!');
      await Future.delayed(const Duration(seconds: 1));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Import complete: $_importedCount / $_totalToImport tracks added')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return AlertDialog(
      title: Row(
        children: const [
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
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final libs = snapshot.data!;
            if (libs.isEmpty)
              return const Center(child: Text('No libraries found.'));

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
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Importing Tracks...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _totalToImport > 0 ? _importedCount / _totalToImport : 0,
              backgroundColor: Colors.grey[800],
              color: AppTheme.primaryGreen,
              minHeight: 10,
            ),
            const SizedBox(height: 10),
            Text('$_importedCount / $_totalToImport'),
            const SizedBox(height: 20),
            Text(_currentImportingTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildActions() {
    if (_step == 3) return []; // No actions during import

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
