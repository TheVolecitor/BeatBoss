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
import 'core/services/dab_api_service.dart';
import 'core/services/download_manager_service.dart';
import 'core/services/youtube_service.dart';
import 'core/services/spotify_service.dart';
import 'core/services/last_fm_service.dart';
import 'features/app_shell.dart';

import 'core/services/history_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize JustAudioMediaKit
  JustAudioMediaKit.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // 1. Settings (needed globally)
  final settingsService = SettingsService();
  await settingsService.init();

  // 2. Core Services
  final dabApiService = DabApiService();
  final downloadManager =
      DownloadManagerService(settingsService: settingsService);

  final historyService = HistoryService();
  await historyService.init();

  // 3. Audio Handler
  // Note: AppAudioHandler needs to be imported
  final audioHandler = await AudioService.init(
    builder: () => AppAudioHandler(
      downloadManager: downloadManager,
      dabApiService: dabApiService,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.beatboss.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/launcher_icon',
    ),
  );

  final youtubeService = YouTubeService();
  final spotifyService = SpotifyService();
  final lastFmService = LastFmService(); // New
  await lastFmService.init();

  // 4. UI Audio Service
  final audioPlayerService = AudioPlayerService(
    handler: audioHandler as AppAudioHandler,
    dabApiService: dabApiService,
    historyService: historyService,
    lastFmService: lastFmService, // Inject
  );

  // Auto-login
  if (settingsService.isLoggedIn) {
    final token = settingsService.authToken;
    if (token != null) {
      print('Attempting auto-login...');
      await dabApiService.autoLogin(token);
    }
  }

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: audioPlayerService),
        ChangeNotifierProvider.value(value: downloadManager),
        ChangeNotifierProvider.value(value: historyService),
        Provider.value(value: dabApiService),
        Provider.value(value: youtubeService),
        Provider.value(value: spotifyService),
        ChangeNotifierProvider.value(value: lastFmService),
      ],
      child: const BeatBossApp(),
    ),
  );
}

class BeatBossApp extends StatelessWidget {
  const BeatBossApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'BeatBoss',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AppShell(),
        );
      },
    );
  }
}
