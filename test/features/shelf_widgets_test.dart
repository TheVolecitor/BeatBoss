import 'package:beatboss/features/home/widgets/home_header.dart';
import 'package:beatboss/features/shared/media_card.dart';
import 'package:beatboss/features/shared/mix_card.dart';
import 'package:beatboss/features/shared/quick_pick_tile.dart';
import 'package:beatboss/features/shared/shelf_section.dart';
import 'package:beatboss/features/shared/shelf_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  test('quick picks use 2, 3 or 4 columns by width', () {
    expect(quickPickColumns(400), 2);
    expect(quickPickColumns(767), 2);
    expect(quickPickColumns(768), 3);
    expect(quickPickColumns(1199), 3);
    expect(quickPickColumns(1200), 4);
  });

  test('placeholder colours are stable per title', () {
    expect(placeholderColors('Song'), placeholderColors('Song'));
    expect(placeholderColors('Song'), isNot(placeholderColors('Other')));
  });

  test('greeting follows the time of day', () {
    expect(greetingFor(DateTime(2024, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2024, 1, 1, 14)), 'Good afternoon');
    expect(greetingFor(DateTime(2024, 1, 1, 21)), 'Good evening');
  });

  for (final size in [const Size(390, 800), const Size(1400, 900)]) {
    testWidgets('shelf widgets lay out at ${size.width.toInt()} px',
        (tester) async {
      await pumpAt(
        tester,
        size,
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuickPickGrid(tiles: [
                for (var i = 0; i < 8; i++)
                  QuickPickTile(title: 'A fairly long song title number $i'),
              ]),
              ShelfSection(
                title: 'Cards',
                subtitle: 'With a subtitle',
                onSeeAll: () {},
                height: 205,
                children: [
                  for (var i = 0; i < 10; i++)
                    MediaCard(
                        title: 'Song $i', subtitle: 'Artist', circle: i.isOdd),
                ],
              ),
              ShelfSection(
                title: 'Mixes',
                height: 215,
                itemWidth: MixCard.width,
                children: [
                  for (var i = 0; i < 5; i++)
                    MixCard(
                        title: 'Artist $i Mix',
                        subtitle: 'Made from your top artists',
                        covers: const [null, null],
                        onPlay: () {}),
                ],
              ),
              const ShelfSkeleton.cards(),
              const ShelfSkeleton.quickPicks(),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Cards'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(find.text('Artist 0 Mix'), findsOneWidget);
    });
  }
}
