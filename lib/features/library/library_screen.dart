import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/local_library_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../shared/track_list_tile.dart';
import '../shared/batch_download_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../favourites/favourites_screen.dart';
import '../downloads/downloads_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Addon State
  List<MusicLibrary> _addonLibraries = [];
  bool _isLoadingAddon = false;

  // Selected State
  MusicLibrary? _selectedLibrary;
  List<Track>? _libraryTracks;
  bool _isLocalSelected = false;

  @override
  void initState() {
    super.initState();
    _loadAddonLibraries();
    
    context.read<AddonService>().addListener(_onAddonChanged);
  }

  @override
  void dispose() {
    context.read<AddonService>().removeListener(_onAddonChanged);
    super.dispose();
  }

  void _onAddonChanged() {
    if (mounted) {
      _loadAddonLibraries();
    }
  }

  Future<void> _loadAddonLibraries() async {
    if (!mounted) return;
    final addonService = context.read<AddonService>();
    if (!addonService.supportsLibrary) {
      if (mounted) {
        setState(() {
          _addonLibraries = [];
          if (!_isLocalSelected && _selectedLibrary != null) {
            _selectedLibrary = null;
          }
        });
      }
      return;
    }

    setState(() => _isLoadingAddon = true);
    final libs = await addonService.getLibraries();

    if (!mounted) return;

    // Sort: Favourites to the top
    libs.sort((a, b) {
      bool aIsSys = addonService.isSystemLibrary(a.name);
      bool bIsSys = addonService.isSystemLibrary(b.name);
      if (aIsSys && !bIsSys) return -1;
      if (!aIsSys && bIsSys) return 1;
      return a.name.compareTo(b.name);
    });

    setState(() {
      _addonLibraries = libs;
      _isLoadingAddon = false;
    });
  }

  Future<void> _loadLibraryTracks(MusicLibrary library, bool isLocal) async {
    setState(() {
      _selectedLibrary = library;
      _isLocalSelected = isLocal;
      _libraryTracks = null;
    });

    if (mounted) {
      context.read<NavigationService>().setBackHandler(_goBack);
    }

    List<Track> tracks = [];
    if (isLocal) {
      final localService = context.read<LocalLibraryService>();
      tracks = localService.getLibraryTracks(library.id);
    } else {
      final addonService = context.read<AddonService>();
      tracks = await addonService.getLibraryTracks(library.id, limit: 1000);
    }

    if (!mounted) return;

    setState(() => _libraryTracks = tracks);
  }

  void _goBack() {
    if (!mounted) return;
    setState(() {
      _selectedLibrary = null;
      _libraryTracks = null;
    });

    if (mounted) {
      context.read<NavigationService>().clearBackHandler();
    }

    // Refresh to update track counts
    if (_isLocalSelected) {
      // Local lists are fetched synchronously in builder
    } else {
      _loadAddonLibraries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final addonService = context.watch<AddonService>();
    final hasAddonLibrary = addonService.supportsLibrary;

    return _selectedLibrary != null
        ? _buildLibraryDetail(isDark)
        : DefaultTabController(
            length: hasAddonLibrary ? 4 : 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 15),
                    child: Text(
                      'Your Collections',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ),
                  TabBar(
                    indicatorColor: AppTheme.primaryGreen,
                    labelColor: AppTheme.primaryGreen,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    unselectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                    unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    tabs: [
                      const Tab(text: 'Liked Songs'),
                      if (hasAddonLibrary) const Tab(text: 'Cloud Library'),
                      const Tab(text: 'Local Library'),
                      const Tab(text: 'Downloads'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        const FavouritesScreen(),
                        if (hasAddonLibrary) _buildAddonLibraryList(isDark),
                        _buildLocalLibraryList(isDark),
                        const DownloadsScreen(),
                      ],
                    ),
                  ),
                ],
              ),
          );
  }

  // ========== LOCAL LIBRARY LIST ==========
  Widget _buildLocalLibraryList(bool isDark) {
    final localService = context.watch<LocalLibraryService>();
    final libs = localService.getLibraries();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final imported = await localService.importLibraries();
                  if (mounted && imported > 0) {
                    AppToast.show(context, 'Imported $imported libraries');
                  }
                },
                icon: const Icon(Icons.file_download),
                label: const Text('Import'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await localService.exportLibraries();
                  if (mounted && path != null) {
                    AppToast.show(context, 'Exported to $path');
                  }
                },
                icon: const Icon(Icons.file_upload),
                label: const Text('Export'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                color: AppTheme.primaryGreen,
                tooltip: 'Create Local Library',
                onPressed: () => _showCreateLibraryDialog(isLocal: true),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: libs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No local collections',
                          style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateLibraryDialog(isLocal: true),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Local Library'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: libs.length,
                    itemBuilder: (context, index) {
                      return _buildLibraryItem(libs[index], isDark, true);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ========== ADDON LIBRARY LIST ==========
  Widget _buildAddonLibraryList(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add),
                color: AppTheme.primaryGreen,
                tooltip: 'Create Remote Library',
                onPressed: () => _showCreateLibraryDialog(isLocal: false),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: isDark ? Colors.white54 : Colors.black45,
                onPressed: _loadAddonLibraries,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoadingAddon
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _addonLibraries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'No remote collections found',
                                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  onPressed: () => _showCreateLibraryDialog(isLocal: false),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create Remote Library'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _addonLibraries.length,
                            itemBuilder: (context, index) {
                              return _buildLibraryItem(_addonLibraries[index], isDark, false);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryItem(MusicLibrary lib, bool isDark, bool isLocal) {
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final addonService = context.read<AddonService>();
    final isSystem = !isLocal && addonService.isSystemLibrary(lib.name);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _loadLibraryTracks(lib, isLocal),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: (isLocal ? AppTheme.primaryGreen : Colors.blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isLocal ? Icons.folder_rounded : (isSystem ? Icons.favorite_rounded : Icons.cloud_rounded),
                      color: isLocal ? AppTheme.primaryGreen : (isSystem ? Colors.redAccent : Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lib.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (lib.trackCount != null)
                          Text(
                            '${lib.trackCount} tracks',
                            style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.black38,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isSystem) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          color: isDark ? Colors.white30 : Colors.black38,
                          onPressed: () => _showEditLibraryDialog(lib, isLocal),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_rounded, size: 20),
                          color: Colors.red.withOpacity(0.5),
                          onPressed: () => _confirmDeleteLibrary(lib, isLocal),
                        ),
                      ] else 
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.lock_outline_rounded, size: 20, color: Colors.white24),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========== LIBRARY DETAILS ==========
  Widget _buildLibraryDetail(bool isDark) {
    final player = context.read<AudioPlayerService>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _selectedLibrary!.name,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isLocalSelected ? AppTheme.primaryGreen : Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_isLocalSelected ? 'LOCAL' : 'REMOTE', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    Text(
                      'Library',
                      style: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
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
                      builder: (context) => BatchDownloadDialog(tracks: _libraryTracks!),
                    );
                  },
                ),
              if (_isLocalSelected && _libraryTracks != null && _libraryTracks!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.cloud_upload_rounded),
                  iconSize: 28,
                  color: AppTheme.primaryGreen,
                  tooltip: 'Sync to Cloud',
                  onPressed: () => _handleSync(context, _libraryTracks!),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _libraryTracks == null
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _libraryTracks!.isEmpty
                    ? Center(
                        child: Text('No tracks in this library',
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
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

  // ========== DIALOGS ==========

  void _showCreateLibraryDialog({required bool isLocal}) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_box, color: AppTheme.primaryGreen),
            const SizedBox(width: 10),
            Text(isLocal ? 'New Local Library' : 'New Remote Library'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Library Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                if (isLocal) {
                  await context.read<LocalLibraryService>().createLibrary(controller.text);
                } else {
                  await context.read<AddonService>().createLibrary(controller.text);
                }
                if (mounted) {
                  Navigator.pop(dialogContext);
                  if (!isLocal) _loadAddonLibraries();
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditLibraryDialog(MusicLibrary lib, bool isLocal) {
    final controller = TextEditingController(text: lib.name);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                if (isLocal) {
                  await context.read<LocalLibraryService>().updateLibrary(lib.id, controller.text);
                } else {
                  await context.read<AddonService>().updateLibrary(lib.id, name: controller.text);
                }
                if (mounted) {
                  Navigator.pop(dialogContext);
                  if (!isLocal) _loadAddonLibraries();
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteLibrary(MusicLibrary lib, bool isLocal) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Library?'),
        content: Text('Are you sure you want to delete "${lib.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (isLocal) {
                await context.read<LocalLibraryService>().deleteLibrary(lib.id);
              } else {
                await context.read<AddonService>().deleteLibrary(lib.id);
              }
              if (mounted) {
                Navigator.pop(dialogContext);
                if (!isLocal) _loadAddonLibraries();
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
    bool success = false;

    if (_isLocalSelected) {
      final localService = context.read<LocalLibraryService>();
      success = await localService.removeTrackFromLibrary(_selectedLibrary!.id, track.id);
    } else {
      final addonService = context.read<AddonService>();
      success = await addonService.removeTrackFromLibrary(_selectedLibrary!.id, track.id);
    }

    if (success && mounted) {
      setState(() {
        _libraryTracks!.removeAt(index);
      });
      AppToast.show(context, 'Removed "${track.title}" from library');
    }
  }

  Future<void> _handleSync(BuildContext context, List<Track> tracks) async {
    final addonService = context.read<AddonService>();
    
    if (!addonService.supportsLibrary) {
      AppToast.show(context, 'No cloud sync addon active', isError: true);
      return;
    }

    if (!context.mounted) return;
    AppToast.show(context, 'Starting sync...');

    // Get libraries from addon
    final libraries = await addonService.getLibraries();
    
    if (!context.mounted) return;

    if (libraries.isEmpty) {
      // Create a default "My Library" library if none exists
      final success = await addonService.createLibrary('My Library');
      if (success) {
        final newLibs = await addonService.getLibraries();
        if (newLibs.isNotEmpty) {
          await _performSync(context, newLibs.first.id, tracks);
        }
      } else {
        AppToast.show(context, 'Failed to create cloud library', isError: true);
      }
    } else {
      // Sync to the first library found
      await _performSync(context, libraries.first.id, tracks);
    }
  }

  Future<void> _performSync(BuildContext context, String libraryId, List<Track> tracks) async {
    final addonService = context.read<AddonService>();
    final success = await addonService.addTracksToLibrary(libraryId, tracks);
    
    if (context.mounted) {
      AppToast.show(
        context,
        success ? 'Sync successful!' : 'Sync failed',
        isError: !success,
      );
    }
  }
}
