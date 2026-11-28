import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/addon_models.dart';

class AppToast {
  static void show(BuildContext context, String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) {
        final maxW = math.min(400.0, MediaQuery.of(ctx).size.width - 32);
        return Positioned(
          top: 20,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isError
                      ? Colors.redAccent.shade700
                      : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isError
                        ? Colors.red
                        : const Color(0xFF1DB954).withValues(alpha: 0.5),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isError ? Icons.error_outline : Icons.check_circle_outline,
                      color: isError ? Colors.white : const Color(0xFF1DB954),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  /// Structured addon status notification (header, status badge, title,
  /// wrapped description, optional progress bar) bounded to the active window.
  static void showNotice(
    BuildContext context, {
    required String addonName,
    required AddonNotice notice,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    final (Color accent, IconData icon, String statusLabel) =
        switch (notice.level) {
      'error' => (Colors.redAccent, Icons.error_outline_rounded, 'ERROR'),
      'warning' => (
          Colors.amber,
          Icons.warning_amber_rounded,
          'WARNING',
        ),
      'success' => (
          const Color(0xFF1DB954),
          Icons.check_circle_outline_rounded,
          'SUCCESS',
        ),
      _ => (Colors.lightBlueAccent, Icons.info_outline_rounded, 'INFO'),
    };

    entry = OverlayEntry(
      builder: (ctx) {
        final maxW = math.min(380.0, MediaQuery.of(ctx).size.width - 32);
        return Positioned(
          top: 20,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header + status badge
                    Row(
                      children: [
                        Icon(icon, color: accent, size: 17),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            addonName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            if (entry.mounted) entry.remove();
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.white38),
                        ),
                      ],
                    ),
                    if (notice.title != null && notice.title!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        notice.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      notice.message,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    if (notice.progress != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: notice.progress,
                          minHeight: 4,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(Duration(seconds: notice.durationSeconds), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}
