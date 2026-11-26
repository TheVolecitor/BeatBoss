import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/local_library_service.dart';
import '../../core/utils/app_toast.dart';
import '../queue/queue_widgets.dart';

/// Menu action ids shared by every track menu.
class TrackMenuAction {
  static const addQueue = 'add_queue';
  static const playNext = 'play_next';
  static const startRadio = 'start_radio';
  static const addLibrary = 'add_library';
  static const download = 'download';
}

PopupMenuItem<String> _item(String value, IconData icon, String label) {
  return PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );
}

/// The entries every track menu has: queue, play next, radio, library and
/// (optionally) download.
List<PopupMenuEntry<String>> trackMenuItems({bool includeDownload = true}) => [
      _item(TrackMenuAction.addQueue, Icons.queue_music, 'Add to Queue'),
      _item(TrackMenuAction.playNext, Icons.playlist_play, 'Play Next'),
      _item(TrackMenuAction.startRadio, Icons.radio, 'Start Radio'),
      _item(TrackMenuAction.addLibrary, Icons.library_add, 'Add to Library'),
      if (includeDownload)
        _item(TrackMenuAction.download, Icons.download, 'Download'),
    ];

/// Runs one of the [TrackMenuAction]s. Returns false for any other action so
/// the caller can handle its own entries.
bool handleTrackMenuAction(BuildContext context, Track track, String action) {
  final player = context.read<AudioPlayerService>();
  switch (action) {
    case TrackMenuAction.addQueue:
      player.addToQueue(track);
      AppToast.show(context, 'Added "${track.title}" to queue');
      return true;
    case TrackMenuAction.playNext:
      player.playNext(track);
      AppToast.show(context, 'Will play "${track.title}" next');
      return true;
    case TrackMenuAction.startRadio:
      startRadioWithFeedback(context, player, track);
      return true;
    case TrackMenuAction.addLibrary:
      showAddToLibrarySheet(context, track);
      return true;
    case TrackMenuAction.download:
      downloadTrackWithFeedback(context, track);
      return true;
  }
  return false;
}

Future<void> downloadTrackWithFeedback(
    BuildContext context, Track track) async {
  final addons = context.read<AddonService>();
  final downloads = context.read<DownloadManagerService>();
  final url = await addons.getStreamUrl(track.addonTrackId ?? track.id,
      addonId: track.addonId);
  if (!context.mounted) return;
  if (url != null) {
    downloads.downloadTrack(track: track, streamUrl: url);
    AppToast.show(context, 'Download started');
  } else {
    AppToast.show(context, 'Failed to get download URL', isError: true);
  }
}

/// Bottom sheet listing the local and cloud libraries [track] can go into.
Future<void> showAddToLibrarySheet(BuildContext context, Track track) async {
  final addons = context.read<AddonService>();
  final local = context.read<LocalLibraryService>();

  final cloudLibraries = await addons.getLibraries();
  final localLibraries = local.getLibraries();
  if (!context.mounted) return;

  Future<void> add(
      BuildContext sheet, String name, Future<bool> Function() action) async {
    Navigator.pop(sheet);
    final ok = await action();
    if (context.mounted) {
      AppToast.show(context, ok ? 'Added to $name' : 'Failed to add',
          isError: !ok);
    }
  }

  showModalBottomSheet(
    context: context,
    builder: (sheet) {
      final scheme = Theme.of(sheet).colorScheme;
      Widget header(String text) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant)),
          );

      if (cloudLibraries.isEmpty && localLibraries.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            heightFactor: 1,
            child: Text('No libraries found. Create one first!'),
          ),
        );
      }

      return ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
            0, 20, 0, 20 + MediaQuery.of(sheet).viewPadding.bottom),
        children: [
          if (localLibraries.isNotEmpty) ...[
            header('LOCAL LIBRARIES'),
            for (final lib in localLibraries)
              ListTile(
                leading: Icon(Icons.folder, color: scheme.primary),
                title: Text(lib.name),
                onTap: () => add(sheet, lib.name,
                    () => local.addTrackToLibrary(lib.id, track)),
              ),
          ],
          if (cloudLibraries.isNotEmpty) ...[
            header('CLOUD LIBRARIES'),
            for (final lib in cloudLibraries)
              ListTile(
                leading: Icon(Icons.cloud, color: scheme.primary),
                title: Text(lib.name),
                onTap: () => add(sheet, lib.name,
                    () => addons.addTracksToLibrary(lib.id, [track])),
              ),
          ],
        ],
      );
    },
  );
}

/// A "more" button with the shared track menu, used on media cards.
class TrackMenuButton extends StatelessWidget {
  final Track track;

  /// Overrides the default round "more" icon.
  final Widget? icon;

  const TrackMenuButton({super.key, required this.track, this.icon});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: icon ??
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_vert, size: 16, color: Colors.white),
          ),
      onSelected: (value) => handleTrackMenuAction(context, track, value),
      itemBuilder: (_) => trackMenuItems(),
    );
  }
}
