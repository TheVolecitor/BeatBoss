// Conditional import: selects platform_io.dart on native, platform_web.dart on web.
export 'platform_web.dart'
    if (dart.library.io) 'platform_io.dart';
