import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/services/audio_player_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/addon_service.dart';
import '../core/services/import_service.dart';
import '../core/services/navigation_service.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'settings/settings_screen.dart';
import 'search/search_screen.dart';
import 'player/player_bar.dart';

/// Main App Shell - responsive layout with sidebar + viewport + player bar
/// Mirrors original DabFletApp layout exactly
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [];
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();
  late FocusNode _appFocusNode;

  // Responsive breakpoint
  static const double _mobileBreakpoint = 768;

  @override
  void initState() {
    super.initState();
    _appFocusNode = FocusNode();
    _requestNotificationPermission();

    _screens.addAll([
      HomeScreen(onNavigate: _onNavTap),
      const LibraryScreen(),
      const SettingsScreen(),
      SearchScreen(key: _searchKey, onNavigate: _onNavTap),
    ]);
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ requires this for notifications (SMTC)
      // Older versions accept it gracefully or ignore it
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // Explicitly request storage permissions as well (user request)
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        await Permission.storage.request();
      }

      // For Android 13+ audio/images
      if (await Permission.audio.status.isDenied) {
        await Permission.audio.request();
      }
      if (await Permission.manageExternalStorage.status.isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    // Auto-focus search field if navigating to search tab
    if (index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchKey.currentState?.focusSearch();
      });
    }
  }

  void _handleBack() {
    final navService = context.read<NavigationService>();
    if (navService.canGoBack) {
      navService.handleBack();
      return;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  // ... rest of class ...

  @override
  void dispose() {
    _appFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _mobileBreakpoint;

    return Focus(
      focusNode: _appFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // 1. If typing in a text field, let it handle the key
        if (_isTextInputFocused()) {
          return KeyEventResult.ignored;
        }

        // 2. Otherwise, handle shortcuts
        final player = context.read<AudioPlayerService>();

        switch (event.logicalKey) {
          case LogicalKeyboardKey.space:
            player.togglePlayPause();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowRight:
            player.nextTrack();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowLeft:
            player.previousTrack();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.escape:
            _handleBack();
            return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          // Ensure we regain focus if clicking background
          if (!_appFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(_appFocusNode);
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (didPop) return;
            _handleBack();
          },
          child: Scaffold(
            backgroundColor:
                isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
            body: Stack(
              children: [
                Column(
                  children: [
                    // Main content area with SafeArea
                    Expanded(
                      child: SafeArea(
                        bottom: false, // Don't add padding below content
                        child: isMobile
                            ? _buildMobileLayout(isDark)
                            : _buildDesktopLayout(isDark),
                      ),
                    ),
                    // Player bar at bottom - sits flush
                    const PlayerBar(),
                  ],
                ),
                // Overlay for Background Imports
                _buildBackgroundImportOverlay(),
              ],
            ),
            // Bottom nav for mobile only
            bottomNavigationBar: isMobile ? _buildBottomNav(isDark) : null,
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundImportOverlay() {
    return Consumer<ImportService>(
      builder: (context, importService, child) {
        if (!importService.isImporting || !importService.isBackgrounded) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 10,
          right: 10,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardColor,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              width: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Importing Playlist...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => importService.stopImport(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: importService.progress,
                    backgroundColor: Colors.grey[800],
                    color: AppTheme.primaryGreen,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    importService.statusMessage,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${importService.importedCount} / ${importService.totalTracks} Tracks',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      // Check if the focused widget is inside an EditableText (TextField, TextFormField)
      // The Focus widget is usually a child of EditableText, so we look up the tree
      if (!focus.context!.mounted) return false; // Safety
      final editable =
          focus.context!.findAncestorWidgetOfExactType<EditableText>();
      return editable != null;
    }
    return false;
  }

  Widget _buildDesktopLayout(bool isDark) {
    return Row(
      children: [
        // Sidebar
        _buildSidebar(isDark),
        // Main viewport
        Expanded(
          child: Container(
            color: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return IndexedStack(
      index: _selectedIndex,
      children: _screens,
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 260, // Expanded width
      color: isDark ? AppTheme.darkSidebar : AppTheme.lightSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.black),
                ),
                const SizedBox(width: 12),
                Text(
                  'BeatBoss',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Helper for Nav Items
          ..._buildNavItems(isDark),
        ],
      ),
    );
  }

  List<Widget> _buildNavItems(bool isDark) {
    return [
      _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home', isDark),
      _buildNavItem(1, Icons.library_music_outlined, Icons.library_music, 'Library', isDark),

      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Divider(color: isDark ? Colors.white10 : Colors.black12),
      ),

      // Create Library Action
      _buildActionItem(Icons.add_box_outlined, 'Create Library', isDark,
          onTap: _showCreateLibraryDialog),

      _buildNavItem(2, Icons.settings_outlined, Icons.settings, 'Settings', isDark),

      const Spacer(),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon,
      String label, bool isDark) {
    // For search (index 3), we visually highlight Home (index 0)
    final isSelected = _selectedIndex == index || (_selectedIndex == 3 && index == 0);

    return InkWell(
      onTap: () => _onNavTap(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected
                  ? AppTheme.primaryGreen
                  : (isDark ? Colors.white70 : Colors.black54),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? Colors.white70 : Colors.black54),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, bool isDark,
      {required VoidCallback onTap, Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? (isDark ? Colors.white70 : Colors.black54),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color ?? (isDark ? Colors.white70 : Colors.black54),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }



  void _showCreateLibraryDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            border: OutlineInputBorder(),
          ),
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
                final addonService = context.read<AddonService>();
                final success = await addonService.createLibrary(controller.text);

                if (mounted) {
                  Navigator.pop(dialogContext);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Created library "${controller.text}"')));
                    // Navigate to Library screen to see it
                    setState(() => _selectedIndex = 2);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Failed to create library. Ensure a Sync Addon is configured.')));
                  }
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomNav(bool isDark) {
    final activeIndex = _selectedIndex > 2 ? 0 : _selectedIndex;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBackground.withOpacity(0.9) : Colors.white.withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildModernNavItem(0, Icons.home_rounded, Icons.home_rounded, 'Home', activeIndex == 0, isDark),
                _buildModernNavItem(1, Icons.library_music_rounded, Icons.library_music_rounded, 'Library', activeIndex == 1, isDark),
                _buildModernNavItem(2, Icons.settings_rounded, Icons.settings_rounded, 'Settings', activeIndex == 2, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernNavItem(int index, IconData icon, IconData activeIcon, String label, bool isSelected, bool isDark) {
    final activeColor = AppTheme.primaryGreen;
    final inactiveColor = isDark ? Colors.white24 : Colors.black26;

    return Expanded(
      child: InkWell(
        onTap: () => _onNavTap(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? (isDark ? Colors.white : Colors.black) : inactiveColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

class BackIntent extends Intent {
  const BackIntent();
}
