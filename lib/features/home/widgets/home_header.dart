import 'package:flutter/material.dart';

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The time-based greeting at the top of Home.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      greetingFor(DateTime.now()),
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }
}

/// Shown when no Last.fm account is connected.
class ConnectBanner extends StatelessWidget {
  final VoidCallback onConnect;
  const ConnectBanner({super.key, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connect Last.fm',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Get mixes made from your listening.',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onConnect, child: const Text('Connect')),
        ],
      ),
    );
  }
}
