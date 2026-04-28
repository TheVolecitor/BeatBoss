import 'dart:io';
import 'discord_rpc_service.dart';
import 'discord_rpc_service_noop.dart';
import 'discord_rpc_service_windows.dart';

class DiscordRpcFactory {
  static DiscordRpcService create() {
    if (Platform.isWindows) {
      return DiscordRpcServiceWindows();
    }
    return DiscordRpcServiceNoop();
  }
}
