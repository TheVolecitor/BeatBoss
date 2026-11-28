import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/utils/app_toast.dart';
import '../queue/queue_widgets.dart';
import '../shared/artist_navigation.dart';

/// Opens the artist page for [track], falling back to a name search.
Future<void> openArtistForTrack(BuildContext context, Track track) async {
  final artistId = track.artistId;
  final addonId = track.addonId;
  if (artistId != null && addonId != null) {
    openArtistPage(context,
        id: artistId, addonId: addonId, name: track.artist);
    return;
  }
  // The track doesn't carry an artist id, so look the artist up by name.
  if (!await openArtistByName(context, track.artist) && context.mounted) {
    AppToast.show(context, 'No artist page found for ${track.artist}',
        isError: true);
  }
}

/// Opens the page of the artist of [track]. The tooltip shows on long-press.
class GoToArtistButton extends StatelessWidget {
  final Track track;
  final Color? color;
  final double iconSize;

  const GoToArtistButton({
    super.key,
    required this.track,
    this.color,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.person_outline),
      iconSize: iconSize,
      color: color,
      tooltip: 'Go to artist',
      onPressed: () => openArtistForTrack(context, track),
    );
  }
}

/// Starts a radio from [track], or stops the running one. Green while a radio
/// is playing. The tooltip shows on long-press.
class RadioButton extends StatelessWidget {
  final Track track;
  final Color? color;
  final Color activeColor;
  final double iconSize;

  const RadioButton({
    super.key,
    required this.track,
    required this.activeColor,
    this.color,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final on = player.radioSeed != null;
    return IconButton(
      icon: const Icon(Icons.radio),
      iconSize: iconSize,
      color: on ? activeColor : color,
      tooltip: on ? 'Stop radio' : 'Start radio',
      onPressed: () => toggleRadio(context, player, track),
    );
  }
}
