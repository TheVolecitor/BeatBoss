import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../models/models.dart';
import 'discord_rpc_service.dart';

class DiscordRpcServiceWindows implements DiscordRpcService {
  static const String _appId = '1466686438450925786';
  static const String _pipeName = r'\\.\pipe\discord-ipc-0';

  int _hPipe = INVALID_HANDLE_VALUE;
  bool _isInitialized = false;

  @override
  void initialize() {
    if (_isInitialized) return;
    _connect();
  }

  void _connect() {
    final lpszPipeName = _pipeName.toNativeUtf16();
    try {
      _hPipe = CreateFile(
        lpszPipeName,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        NULL,
      );

      if (_hPipe != INVALID_HANDLE_VALUE) {
        print('[DiscordRPC] Connected to pipe.');
        _sendHandshake();
        _isInitialized = true;
      } else {
        print('[DiscordRPC] Failed to connect: ${GetLastError()}');
      }
    } finally {
      calloc.free(lpszPipeName);
    }
  }

  void _sendHandshake() {
    final handshake = {
      'v': 1,
      'client_id': _appId,
    };
    _sendFrame(0, handshake);
  }

  @override
  void updatePresence({
    required Track track,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    if (_hPipe == INVALID_HANDLE_VALUE) {
      // Try reconnecting if pipe was lost
      _connect();
      if (_hPipe == INVALID_HANDLE_VALUE) return;
    }

    final int startTimestamp = (isPlaying && position != null)
        ? DateTime.now().millisecondsSinceEpoch - position.inMilliseconds
        : 0;

    final int? endTimestamp =
        (isPlaying && position != null && duration != null)
            ? DateTime.now().millisecondsSinceEpoch +
                (duration.inMilliseconds - position.inMilliseconds)
            : null;

    final Map<String, dynamic> activity = {
      'type': 2, // Listening to
      'details': track.title,
      'state': track.artist,
      'assets': {
        'large_image': track.albumCover ?? 'logo',
        'large_text': track.albumTitle ?? 'BeatBoss',
        'small_image': isPlaying ? 'play' : 'pause',
        'small_text': isPlaying ? 'Playing' : 'Paused',
      },
      'buttons': [
        {
          'label': 'View on GitHub',
          'url': 'https://github.com/TheVolecitor/BeatBoss',
        },
        {
          'label': 'Download App',
          'url': 'https://github.com/TheVolecitor/BeatBoss/releases/latest',
        }
      ],
    };

    if (isPlaying && endTimestamp != null) {
      activity['timestamps'] = {
        'start': startTimestamp,
        'end': endTimestamp,
      };
    } else {
      // Explicitly nullify to remove timer on pause
      activity['timestamps'] = null;
    }

    final payload = {
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'activity': activity,
      },
      'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    _sendFrame(1, payload);
  }

  void _sendFrame(int opcode, Map<String, dynamic> jsonBody) {
    if (_hPipe == INVALID_HANDLE_VALUE) return;

    final jsonStr = jsonEncode(jsonBody);
    final jsonBytes = utf8.encode(jsonStr);
    final length = jsonBytes.length;

    // Buffer: Opcode (4) + Length (4) + Payload (N)
    final totalSize = 8 + length;
    final buffer = calloc<Uint8>(totalSize);

    try {
      final data = buffer.cast<Uint32>();
      data[0] = opcode; // Little endian by default on Windows/x86/x64
      data[1] = length;

      final payloadPtr = buffer.elementAt(8);
      for (var i = 0; i < length; i++) {
        payloadPtr[i] = jsonBytes[i];
      }

      final lpNumberOfBytesWritten = calloc<DWORD>();
      final result = WriteFile(
        _hPipe,
        buffer,
        totalSize,
        lpNumberOfBytesWritten,
        nullptr,
      );

      if (result == 0) {
        print('[DiscordRPC] WriteFile failed: ${GetLastError()}');
        _close();
      }

      calloc.free(lpNumberOfBytesWritten);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void clearPresence() {
    if (_hPipe == INVALID_HANDLE_VALUE) return;

    final payload = {
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'activity': null,
      },
      'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    _sendFrame(1, payload);
  }

  void _close() {
    if (_hPipe != INVALID_HANDLE_VALUE) {
      CloseHandle(_hPipe);
      _hPipe = INVALID_HANDLE_VALUE;
      _isInitialized = false;
    }
  }

  @override
  void dispose() {
    clearPresence();
    _close();
  }
}
