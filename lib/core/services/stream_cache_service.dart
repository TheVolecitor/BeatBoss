// Conditional export: the io implementation on native targets, a no-op stub
// on web (same pattern as platform_helper.dart).
export 'stream_cache/cache_models.dart';
export 'stream_cache/stream_cache_service_stub.dart'
    if (dart.library.io) 'stream_cache/stream_cache_service_io.dart';
