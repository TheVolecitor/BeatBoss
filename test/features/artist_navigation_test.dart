import 'package:flutter_test/flutter_test.dart';

import 'package:beatboss/core/models/addon_models.dart';
import 'package:beatboss/features/shared/artist_navigation.dart';

AddonArtist artist(String name) =>
    AddonArtist(id: name, name: name, addonId: 'a');

void main() {
  test('pickArtist prefers an exact name match over the first result', () {
    final result =
        pickArtist([artist('Radiohead Tribute'), artist('Radiohead')], 'radiohead');
    expect(result?.name, 'Radiohead');
  });

  test('pickArtist falls back to the first result', () {
    final result = pickArtist([artist('Foo'), artist('Bar')], 'Baz');
    expect(result?.name, 'Foo');
  });

  test('pickArtist returns null for no results', () {
    expect(pickArtist(const [], 'Anything'), isNull);
  });
}
