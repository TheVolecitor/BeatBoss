import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../shared/track_list_tile.dart';
import '../shared/batch_download_dialog.dart';

/// Library Screen - display user's music libraries (collections)
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<MusicLibrary> _libraries = [];
  bool _isLoading = true;
  MusicLibrary? _selectedLibrary;
  List<Track>? _libraryTracks;

  @override
  void initState() {
    super.initState();
    _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    setState(() => _isLoading = true);

    final api = context.read<DabApiService>();
    final libs = await api.getLibraries();

    if (!mounted) return;

    setState(() {
      _libraries = libs;
      _isLoading = false;
    });
  }

  Future<void> _loadLibraryTracks(MusicLibrary library) async {
    setState(() {
      _selectedLibrary = library;
      _libraryTracks = null;
    });

    final api = context.read<DabApiService>();
    final tracks = await api.getLibraryTracks(library.id, limit: 1000);

    if (!mounted) return;

    setState(() => _libraryTracks = tracks);
  }

  void _goBack() {
    if (!mounted) return;
    setState(() {
      _selectedLibrary = null;
      _libraryTracks = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final api = context.read<DabApiService>();

    // Show login prompt if not logged in
    if (!api.isLoggedIn) {
      return _buildLoginPrompt(isDark);
    }

    // Show library detail if selected
    if (_selectedLibrary != null) {
      return _buildLibraryDetail(isDark);
    }

    return _buildLibraryList(isDark);
  }

  Widget _buildLoginPrompt(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music,
            size: 80,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 20),
          Text(
            'Sign in to access your library',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              // TODO: Show login dialog
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryList(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your Collections',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                color: AppTheme.primaryGreen,
                onPressed: _showCreateLibraryDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: isDark ? Colors.white54 : Colors.black45,
                onPressed: _loadLibraries,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _libraries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'No collections found',
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.white54 : Colors.black45),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _showCreateLibraryDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Create Library'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _libraries.length,
                        itemBuilder: (context, index) {
                          final lib = _libraries[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkCard
                                  : AppTheme.lightCard,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              title: Text(
                                lib.name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    color: Colors.blue,
                                    onPressed: () =>
                                        _showEditLibraryDialog(lib),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    onPressed: () => _confirmDeleteLibrary(lib),
                                  ),
                                ],
                              ),
                              onTap: () => _loadLibraryTracks(lib),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryDetail(bool isDark) {
    final player = context.read<AudioPlayerService>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: isDark ? Colors.white : Colors.black,
                onPressed: _goBack,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedLibrary!.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Library',
                      style: TextStyle(
                        color: isDark ? Colors.white30 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              if (_libraryTracks != null && _libraryTracks!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_circle_fill),
                  iconSize: 50,
                  color: AppTheme.primaryGreen,
                  onPressed: () => player.playAll(_libraryTracks!),
                ),
              if (_libraryTracks != null && _libraryTracks!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  iconSize: 28,
                  color: isDark ? Colors.white70 : Colors.black54,
                  tooltip: 'Download All',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          BatchDownloadDialog(tracks: _libraryTracks!),
                    );
                  },
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Tracks
          Expanded(
            child: _libraryTracks == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _libraryTracks!.isEmpty
                    ? Center(
                        child: Text(
                          'No tracks in this library',
                          style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _libraryTracks!.length,
                        itemBuilder: (context, index) {
                          return TrackListTile(
                            track: _libraryTracks![index],
                            tracks: _libraryTracks!,
                            index: index,
                            libraryId: _selectedLibrary!.id,
                            onRemove: () => _removeTrackFromLibrary(index),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showCreateLibraryDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_box, color: AppTheme.primaryGreen),
            SizedBox(width: 10),
            Text('New Library'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Library Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final api = context.read<DabApiService>();
                await api.createLibrary(controller.text);
                if (mounted) {
                  Navigator.pop(context);
                  _loadLibraries();
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditLibraryDialog(MusicLibrary lib) {
    final controller = TextEditingController(text: lib.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: AppTheme.primaryGreen),
            SizedBox(width: 10),
            Text('Edit Library'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Library Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final api = context.read<DabApiService>();
                await api.updateLibrary(lib.id, name: controller.text);
                if (mounted) {
                  Navigator.pop(context);
                  _loadLibraries();
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteLibrary(MusicLibrary lib) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Library?'),
        content: Text(
            'Are you sure you want to delete "${lib.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final api = context.read<DabApiService>();
              await api.deleteLibrary(lib.id);
              if (mounted) {
                Navigator.pop(context);
                _loadLibraries();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _removeTrackFromLibrary(int index) async {
    final track = _libraryTracks![index];
    final api = context.read<DabApiService>();

    final success =
        await api.removeTrackFromLibrary(_selectedLibrary!.id, track.id);

    if (success && mounted) {
      setState(() {
        _libraryTracks!.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${track.title}" from library')),
      );
    }
  }
}
