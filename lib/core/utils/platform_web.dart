/// Web stub for platform helpers.
/// On web there is no dart:io, so all platform checks return safe defaults.
class PlatformHelper {
  static bool get isAndroid => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;

  /// Always false on web — no local filesystem access
  static bool fileExists(String path) => false;

  /// Always empty on web
  static String get pathSeparator => '/';

  /// No-op on web
  static Future<void> cleanupTempFiles(String dir) async {}

  /// Always returns fallback on web — no environment variables
  static String getEnv(String key, {String fallback = ''}) => fallback;

  /// Always 0 on web — no local files
  static int fileSize(String path) => 0;

  /// No-op on web
  static void deleteFile(String path) {}

  /// No-op on web — no directories to create
  static Future<void> ensureDir(String path) async {}

  /// No-op on web
  static Future<void> renameFile(String from, String to) async {}

  /// Always null on web — no file system
  static String? getHistoryFilePath(String fileName) => null;

  /// No-op on web
  static Future<void> writeFile(String path, String content) async {}

  /// Always null on web
  static Future<String?> readFile(String path) async => null;

  /// No-op on web
  static void ensureMpvConfig() {}
}
