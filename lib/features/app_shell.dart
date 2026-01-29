import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/services/audio_player_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/dab_api_service.dart';
import 'home/home_screen.dart';
import 'search/search_screen.dart';
import 'library/library_screen.dart';
import 'favorites/favorites_screen.dart';
import 'settings/settings_screen.dart';
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
      const SearchScreen(),
      const LibraryScreen(),
      const FavoritesScreen(),
      const SettingsScreen(),
    ]);
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ requires this for notifications (SMTC)
      // Older versions accept it gracefully or ignore it
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleBack() {
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
        child: Scaffold(
          backgroundColor:
              isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
          body: SafeArea(
            child: Column(
              children: [
                // Main content area
                Expanded(
                  child: isMobile
                      ? _buildMobileLayout(isDark)
                      : _buildDesktopLayout(isDark),
                ),
                // Player bar at bottom
                const PlayerBar(),
              ],
            ),
          ),
          // Bottom nav for mobile only
          bottomNavigationBar: isMobile ? _buildBottomNav(isDark) : null,
        ),
      ),
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
            child: _screens[_selectedIndex],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return _screens[_selectedIndex];
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
      _buildNavItem(1, Icons.search_outlined, Icons.search, 'Search', isDark),
      _buildNavItem(2, Icons.library_music_outlined, Icons.library_music,
          'Library', isDark),

      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Divider(color: isDark ? Colors.white10 : Colors.black12),
      ),

      // Create Library Action
      _buildActionItem(Icons.add_box_outlined, 'Create Library', isDark,
          onTap: _showCreateLibraryDialog),

      _buildNavItem(
          3, Icons.favorite_outline, Icons.favorite, 'Liked Songs', isDark),
      _buildNavItem(
          4, Icons.settings_outlined, Icons.settings, 'Settings', isDark),

      const Spacer(),

      // Sign Out
      _buildActionItem(
        Icons.logout,
        'Sign Out',
        isDark,
        onTap: _handleLogout,
        color: Colors.red,
      ),

      const SizedBox(height: 20),
    ];
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon,
      String label, bool isDark) {
    final isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () => _onNavTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white10 : Colors.black.withOpacity(0.05))
              : Colors.transparent,
          border: isSelected
              ? Border(left: BorderSide(color: AppTheme.primaryGreen, width: 3))
              : null,
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

  void _handleLogout() async {
    final api = context.read<DabApiService>();
    final settings = context.read<SettingsService>();

    api.clearUser();
    await settings.clearUser();

    // Reset to Home (which will show Login)
    if (mounted) {
      setState(() {
        _selectedIndex = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Logged out successfully'),
        backgroundColor: Colors.blue,
      ));
    }
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
            border: OutlineInputBorder(),
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
                final lib = await api.createLibrary(controller.text);

                if (mounted) {
                  Navigator.pop(context);
                  if (lib != null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Created library "${lib.name}"')));
                    // Navigate to Library screen to see it
                    setState(() => _selectedIndex = 2);
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
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppTheme.primaryGreen,
        unselectedItemColor: isDark ? Colors.white54 : Colors.black45,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(
              icon: Icon(Icons.library_music), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Liked'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
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
