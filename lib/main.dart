import 'package:flutter/foundation.dart'; // For kIsWeb
import 'dart:io'; // For Platform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:audio_service/audio_service.dart';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'core/theme/app_theme.dart';
import 'core/services/settings_service.dart';
import 'core/services/audio_player_service.dart';
import 'core/services/audio_handler.dart';
import 'core/services/download_manager_service.dart';
import 'core/services/discord_rpc_service.dart';
import 'core/services/last_fm_service.dart';
import 'core/services/youtube_service.dart';
import 'core/services/spotify_service.dart';

import 'features/app_shell.dart';

import 'core/services/history_service.dart';
import 'core/services/import_service.dart';
import 'core/services/addon_service.dart';
import 'core/services/lrclib_addon_handler.dart';
import 'core/services/local_library_service.dart';
import 'core/services/navigation_service.dart';
import 'core/services/local_library_service.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize JustAudioMediaKit (Desktop only)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // 1. Settings (needed globally)
  final settingsService = SettingsService();
  await settingsService.init();

  // 2. Core Services
  final downloadManager =
      DownloadManagerService(settingsService: settingsService);

  final historyService = HistoryService();
  await historyService.init();

  final importService = ImportService(); // New background import service
  
  final localLibraryService = LocalLibraryService();
  await localLibraryService.init();

  final addonService = AddonService(settingsService: settingsService);
  
  final lrcLibHandler = LrcLibAddonHandler();
  addonService.registerUserHandler('net.lrclib', lrcLibHandler);

  await addonService.initAddons();

  // 3. Audio Handler (Background)
  final audioHandler = await AudioService.init(
    builder: () => AppAudioHandler(
      downloadManager: downloadManager,
      addonService: addonService,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.beatboss.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/launcher_icon',
    ),
  );

  final lastFmService = LastFmService(); // New
  try {
    await lastFmService.init();
  } catch (e) {
    print('Error initializing LastFM: $e');
  }

  final discordRpcService = DiscordRpcService();
  discordRpcService.initialize();

  final youtubeService = YouTubeService();
  final spotifyService = SpotifyService();

  // 4. UI Audio Service
  final audioPlayerService = AudioPlayerService(
    handler: audioHandler,
    addonService: addonService,
    historyService: historyService,
    lastFmService: lastFmService,
    discordRpcService: discordRpcService, // Inject
  );

  final navigationService = NavigationService();

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: audioPlayerService),
        ChangeNotifierProvider.value(value: addonService),
        ChangeNotifierProvider.value(value: historyService),
        ChangeNotifierProvider.value(value: localLibraryService),
        ChangeNotifierProvider.value(value: downloadManager),
        ChangeNotifierProvider.value(value: importService),
        ChangeNotifierProvider.value(value: lastFmService),
        ChangeNotifierProvider.value(value: navigationService),
        Provider.value(value: discordRpcService),
        Provider.value(value: youtubeService),
        Provider.value(value: spotifyService),
      ],
      child: const BeatBossApp(),
    ),
  );
}

class BeatBossApp extends StatelessWidget {
  const BeatBossApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<SettingsService>().isDarkMode
        ? ThemeMode.dark
        : ThemeMode.light;

    return MaterialApp(
      title: 'BeatBoss',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
