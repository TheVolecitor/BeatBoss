import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addon_models.dart';
import '../../core/recommendations/track_matching.dart';
import '../../core/services/addon_service.dart';
import 'addon_detail_screen.dart';

/// Picks the search result that best fits [name]: an exact (normalised) name
/// match if there is one, otherwise the first artist. Null when [artists] is
/// empty.
AddonArtist? pickArtist(List<AddonArtist> artists, String name) {
  if (artists.isEmpty) return null;
  final wanted = normalizeForMatch(name);
  for (final a in artists) {
    if (normalizeForMatch(a.name) == wanted) return a;
  }
  return artists.first;
}

/// Opens the page of an artist the addon knows by id.
void openArtistPage(
  BuildContext context, {
  required String id,
  required String addonId,
  required String name,
  String? artwork,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AddonDetailScreen(
        id: id,
        type: AddonDetailType.artist,
        addonId: addonId,
        initialTitle: name,
        initialArtwork: artwork,
      ),
    ),
  );
}

/// Opens the page for the artist called [name], looking it up in the active
/// addon first. Returns false when the addon has no such artist, so the
/// caller can do something else (like start a radio).
Future<bool> openArtistByName(BuildContext context, String name) async {
  final addons = context.read<AddonService>();
  AddonSearchResult? result;
  try {
    result = await addons.search(name, limit: 10);
  } catch (e) {
    print('openArtistByName: search failed for "$name": $e');
  }
  final artist = pickArtist(result?.artists ?? const [], name);
  if (artist == null ||
      normalizeForMatch(artist.name) != normalizeForMatch(name) ||
      !context.mounted) {
    return false;
  }
  openArtistPage(
    context,
    id: artist.id,
    addonId: artist.addonId,
    name: artist.name,
    artwork: artist.artworkURL,
  );
  return true;
}
