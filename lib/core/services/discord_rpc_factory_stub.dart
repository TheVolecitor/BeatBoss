import 'discord_rpc_service.dart';
import 'discord_rpc_service_noop.dart';

class DiscordRpcFactory {
  static DiscordRpcService create() {
    return DiscordRpcServiceNoop();
  }
}
