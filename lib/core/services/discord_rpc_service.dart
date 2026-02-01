import 'dart:io';
import '../models/models.dart';
import 'discord_rpc_service_windows.dart';
import 'discord_rpc_service_noop.dart';

abstract class DiscordRpcService {
  factory DiscordRpcService() {
    if (Platform.isWindows) {
      return DiscordRpcServiceWindows();
    }
    return DiscordRpcServiceNoop();
  }

  void initialize();
  void updatePresence({
    required Track track,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
  });
  void clearPresence();
  void dispose();
}
