/// Dual-Engine Hive Routing
/// 
/// This conditional export automatically routes Web builds to use the modern, 
/// Wasm-compatible `hive_ce` package (via `hive_web.dart`).
/// Native builds are routed to use the original `hive` package (via `hive_native.dart`) 
/// to ensure 0% risk of data migration/loss for existing users.
///
/// Because `hive_ce` is an exact structural fork of `hive`, the API surface 
/// (`Box`, `Hive.initFlutter()`, etc.) is identical and functions identically.

export 'hive_web.dart' if (dart.library.io) 'hive_native.dart';
