import '../models/models.dart';
import 'discord_rpc_service.dart';

class DiscordRpcServiceNoop implements DiscordRpcService {
  @override
  void initialize() {}

  @override
  void updatePresence({
    required Track track,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
  }) {}

  @override
  void clearPresence() {}

  @override
  void dispose() {}
}
