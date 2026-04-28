import '../models/models.dart';
import 'discord_rpc_factory.dart'; // compile-time conditional: noop on web, io on native

/// Abstract interface for Discord Rich Presence.
/// Concrete implementations are selected at COMPILE TIME via conditional exports:
///   - Web / non-Windows native → DiscordRpcServiceNoop (no-op)
///   - Windows native           → DiscordRpcServiceWindows (win32 pipe)
abstract class DiscordRpcService {
  factory DiscordRpcService() => _createService();

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

// Resolved at compile-time: dart.library.io is false on web/dart2js
DiscordRpcService _createService() => DiscordRpcFactory.create();


