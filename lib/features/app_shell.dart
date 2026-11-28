import 'package:flutter/foundation.dart'; // kIsWeb
import '../core/utils/platform_helper.dart'; // compile-time conditional

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/app_toast.dart';
import '../core/services/audio_player_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/addon_service.dart';
import '../core/services/import_service.dart';
import '../core/services/navigation_service.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'settings/settings_screen.dart';
import 'search/search_screen.dart';
import 'addons/addons_screen.dart';
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
  StreamSubscription? _noticeSub;

  // Responsive breakpoint
  static const double _mobileBreakpoint = 768;

  @override
  void initState() {
    super.initState();
    _appFocusNode = FocusNode();
    _requestNotificationPermission();
    _noticeSub = context.read<AddonService>().onNotice.listen((event) {
      if (!mounted) return;
      AppToast.showNotice(
        context,
        addonName: context.read<AddonService>().displayNameFor(event.addon),
        notice: event.notice,
      );
    });

    _screens.addAll([
      HomeScreen(onNavigate: _onNavTap),
      const LibraryScreen(),
      const SettingsScreen(),
      SearchScreen(key: _searchKey, onNavigate: _onNavTap),
      const AddonsScreen(), // Index 4
    ]);
  }

  Future<void> _requestNotificationPermission() async {
    if (kIsWeb) return; // No permissions needed on web
    if (!PlatformHelper.isAndroid) return;
    // Android 13+ requires this for notifications
    // Use the native helper which is compiled only on native targets
    await _requestAndroidPermissions();
  }

  Future<void> _requestAndroidPermissions() async {
    // This method is only called on Android (guarded above), but dart2js
    // still compiles it. Use a dynamic import pattern or just catch errors.
    try {
      // ignore: avoid_dynamic_calls
      final dynamic permHandler = await _loadPermissionHandler();
      await permHandler.requestNotification();
      await permHandler.requestStorage();
      await permHandler.requestAudio();
    } catch (_) {}
  }

  Future<dynamic> _loadPermissionHandler() async => null;


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
    _noticeSub?.cancel();
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
          onPopInvokedWithResult: (didPop, result) {
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
                    PlayerBar(avoidBottomInset: !isMobile),
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
            child: SlideIndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return SlideIndexedStack(
      index: _selectedIndex,
      children: _screens,
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSidebar : AppTheme.lightSidebar,
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand Header with BeatBoss Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 38,
                      height: 38,
                      color: AppTheme.primaryGreen,
                      child: const Icon(Icons.music_note, color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'BeatBoss',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: _buildNavItems(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarSectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  List<Widget> _buildNavItems(bool isDark) {
    return [
      _sidebarSectionLabel('DISCOVER', isDark),
      _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home', isDark),
      _buildNavItem(3, Icons.search_rounded, Icons.search_rounded, 'Search', isDark),

      _sidebarSectionLabel('LIBRARY', isDark),
      _buildNavItem(1, Icons.library_music_outlined, Icons.library_music_rounded, 'Your Library', isDark),
      _buildActionItem(Icons.add_box_outlined, 'Create Library', isDark,
          onTap: _showCreateLibraryDialog),

      _sidebarSectionLabel('SYSTEM', isDark),
      _buildNavItem(2, Icons.settings_outlined, Icons.settings_rounded, 'Settings', isDark),
    ];
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon,
      String label, bool isDark) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: isSelected
            ? AppTheme.primaryGreen.withValues(alpha: isDark ? 0.16 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _onNavTap(index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: isSelected ? 18 : 0,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? AppTheme.primaryGreen
                      : (isDark ? Colors.white70 : Colors.black54),
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, bool isDark,
      {required VoidCallback onTap, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: color ?? (isDark ? Colors.white70 : Colors.black54),
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color ?? (isDark ? Colors.white70 : Colors.black54),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  void _showCreateLibraryDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_box, color: AppTheme.primaryGreen),
            const SizedBox(width: 10),
            const Text('New Library'),
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
                    setState(() => _selectedIndex = 1);
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
    final activeIndex = _selectedIndex > 3 ? 0 : _selectedIndex;
    // Keep the nav items clear of the system navigation bar (gesture pill or
    // 3-button bar) when the app is drawn edge-to-edge.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      height: 80 + bottomInset,
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
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildModernNavItem(0, Icons.home_rounded, Icons.home_rounded, 'Home', activeIndex == 0, isDark),
                _buildModernNavItem(1, Icons.library_music_rounded, Icons.library_music_rounded, 'Library', activeIndex == 1, isDark),
                _buildModernNavItem(3, Icons.search_rounded, Icons.search_rounded, 'Search', activeIndex == 3, isDark),
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
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black)
                        : inactiveColor,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SlideIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const SlideIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<SlideIndexedStack> createState() => _SlideIndexedStackState();
}

class _SlideIndexedStackState extends State<SlideIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.1), // Slide up subtly
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(SlideIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _controller,
        child: IndexedStack(
          index: widget.index,
          children: widget.children,
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
