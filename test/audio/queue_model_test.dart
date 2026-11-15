import 'dart:math';

import 'package:beatboss/core/models/models.dart';
import 'package:beatboss/core/services/queue_model.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id) => Track(id: id, title: id, artist: 'artist');

List<String> ids(QueueModel q) => q.tracks.map((e) => e.id).toList();

/// Queue [a, b, c] playing `a`, with autoplay tracks x, y after it.
QueueModel withAutoplay() {
  final q = QueueModel()..replace([t('a'), t('b'), t('c')]);
  q.appendAutoplay([t('x'), t('y')]);
  return q;
}

void main() {
  group('basics', () {
    test('replace sets tracks and current, and clears autoplay', () {
      final q = withAutoplay();
      expect(q.autoplayStart, 3);

      q.replace([t('p'), t('q')], index: 1);

      expect(ids(q), ['p', 'q']);
      expect(q.currentIndex, 1);
      expect(q.current!.id, 'q');
      expect(q.autoplayStart, isNull);
    });

    test('hasNext and upcomingCount', () {
      final q = QueueModel()..replace([t('a'), t('b'), t('c')]);
      expect(q.upcomingCount, 2);
      q.currentIndex = 2;
      expect(q.hasNext, isFalse);
      expect(q.upcomingCount, 0);
    });

    test('removeUpcomingAutoplay drops only autoplay tracks not yet played', () {
      final q = withAutoplay(); // a b c | x y, playing a
      final removed = q.removeUpcomingAutoplay();

      expect(removed, 2);
      expect(ids(q), ['a', 'b', 'c']);
      expect(q.autoplayStart, isNull);
      expect(q.current!.id, 'a');
    });

    test('removeUpcomingAutoplay keeps the autoplay track that is playing', () {
      final q = withAutoplay()..currentIndex = 3; // playing x
      q.appendAutoplay([t('z')]);

      final removed = q.removeUpcomingAutoplay();

      expect(removed, 2); // y and z
      expect(ids(q), ['a', 'b', 'c', 'x']);
      expect(q.current!.id, 'x');
      expect(q.autoplayStart, isNull);
    });

    test('removeUpcomingAutoplay does nothing without an autoplay section', () {
      final q = QueueModel()..replace([t('a'), t('b')]);

      expect(q.removeUpcomingAutoplay(), 0);
      expect(ids(q), ['a', 'b']);
    });

    test('keepOnlyCurrent leaves just the playing track', () {
      final q = withAutoplay()..currentIndex = 1;
      q.keepOnlyCurrent();

      expect(ids(q), ['b']);
      expect(q.currentIndex, 0);
      expect(q.current!.id, 'b');
      expect(q.autoplayStart, isNull);
      expect(q.hasNext, isFalse);
    });

    test('keepOnlyCurrent empties a queue that has no current track', () {
      final q = QueueModel()..replace([t('a'), t('b')], index: -1);
      q.keepOnlyCurrent();

      expect(q.isEmpty, isTrue);
    });

    test('removeUpcoming keeps played tracks and the current one only', () {
      final q = withAutoplay()..currentIndex = 1;
      q.removeUpcoming();

      expect(ids(q), ['a', 'b']);
      expect(q.current!.id, 'b');
      expect(q.autoplayStart, isNull);
    });

    test('clear empties the queue', () {
      final q = withAutoplay()..clear();
      expect(q.isEmpty, isTrue);
      expect(q.currentIndex, -1);
      expect(q.autoplayStart, isNull);
    });
  });

  group('autoplay section', () {
    test('appendAutoplay marks where autoplay starts', () {
      final q = withAutoplay();
      expect(ids(q), ['a', 'b', 'c', 'x', 'y']);
      expect(q.autoplayStart, 3);

      q.appendAutoplay([t('z')]);
      expect(q.autoplayStart, 3); // unchanged by a second batch
      expect(ids(q).last, 'z');
    });

    test('addToEnd lands before the autoplay tracks', () {
      final q = withAutoplay()..addToEnd(t('n'));

      expect(ids(q), ['a', 'b', 'c', 'n', 'x', 'y']);
      expect(q.autoplayStart, 4);
    });

    test('insertNext goes right after the current track', () {
      final q = withAutoplay()..insertNext(t('n'));

      expect(ids(q), ['a', 'n', 'b', 'c', 'x', 'y']);
      expect(q.autoplayStart, 4);
    });

    test('while an autoplay track plays, added tracks go next, before the rest',
        () {
      final q = withAutoplay()..currentIndex = 3; // playing x
      q.addToEnd(t('n'));

      expect(ids(q), ['a', 'b', 'c', 'x', 'n', 'y']);
      expect(q.autoplayStart, 5); // only y is still autoplay
    });

    test('removing a user track shifts the boundary', () {
      final q = withAutoplay();
      q.removeAt(1);

      expect(ids(q), ['a', 'c', 'x', 'y']);
      expect(q.autoplayStart, 2);
    });

    test('removing an autoplay track keeps the boundary; removing them all '
        'clears it', () {
      final q = withAutoplay();
      q.removeAt(3);
      expect(q.autoplayStart, 3);
      q.removeAt(3);
      expect(q.autoplayStart, isNull);
      expect(ids(q), ['a', 'b', 'c']);
    });
  });

  group('removeAt', () {
    test('removing before the current track moves the index back', () {
      final q = QueueModel()..replace([t('a'), t('b'), t('c')], index: 2);
      final wasCurrent = q.removeAt(0);

      expect(wasCurrent, isFalse);
      expect(q.currentIndex, 1);
      expect(q.current!.id, 'c');
    });

    test('removing the current track reports it and points at the next', () {
      final q = QueueModel()..replace([t('a'), t('b'), t('c')], index: 1);
      final wasCurrent = q.removeAt(1);

      expect(wasCurrent, isTrue);
      expect(q.currentIndex, 1);
      expect(q.current!.id, 'c');
    });

    test('an out-of-range index does nothing', () {
      final q = QueueModel()..replace([t('a')]);
      expect(q.removeAt(5), isFalse);
      expect(q.length, 1);
    });
  });

  group('reorder', () {
    test('moving a track keeps the current track current', () {
      final q = QueueModel()..replace([t('a'), t('b'), t('c'), t('d')], index: 1);
      q.reorder(3, 0); // d to the front

      expect(ids(q), ['d', 'a', 'b', 'c']);
      expect(q.current!.id, 'b');
    });

    test('moving the current track updates the index', () {
      final q = QueueModel()..replace([t('a'), t('b'), t('c')], index: 0);
      q.reorder(0, 2);

      expect(ids(q), ['b', 'c', 'a']);
      expect(q.current!.id, 'a');
      expect(q.currentIndex, 2);
    });

    test('a user track dragged into the autoplay section moves the boundary',
        () {
      final q = withAutoplay();
      q.reorder(0, 4); // a to the end

      expect(ids(q), ['b', 'c', 'x', 'y', 'a']);
      expect(q.autoplayStart, 2);
    });

    test('an autoplay track dragged into the user section moves the boundary',
        () {
      final q = withAutoplay();
      q.reorder(4, 0); // y to the front

      expect(ids(q), ['y', 'a', 'b', 'c', 'x']);
      expect(q.autoplayStart, 4);
    });

    test('moving within the autoplay section keeps the boundary', () {
      final q = withAutoplay();
      q.reorder(4, 3); // y above x, exactly on the boundary

      expect(ids(q), ['a', 'b', 'c', 'y', 'x']);
      expect(q.autoplayStart, 3);
    });
  });

  group('shuffle', () {
    final names = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    QueueModel big() => QueueModel()..replace(names.map(t).toList());

    test('shuffleUpcoming keeps played tracks and the current track in place',
        () {
      final q = big()..currentIndex = 2;
      q.shuffleUpcoming(Random(1));

      expect(ids(q).sublist(0, 3), ['a', 'b', 'c']);
      expect(q.current!.id, 'c');
      expect(ids(q).sublist(3).toSet(), {'d', 'e', 'f', 'g', 'h'});
      expect(q.isShuffled, isTrue);
    });

    test('shuffleUpcoming leaves autoplay tracks at the end', () {
      final q = withAutoplay();
      q.shuffleUpcoming(Random(3));

      expect(ids(q).sublist(3), ['x', 'y']);
      expect(q.autoplayStart, 3);
    });

    test('unshuffle restores the original order and keeps the current track',
        () {
      final q = big();
      q.shuffleUpcoming(Random(5));
      q.currentIndex = 3; // moved along while shuffled
      final playing = q.current!.id;

      q.unshuffle();

      expect(ids(q), names);
      expect(q.current!.id, playing);
      expect(q.currentIndex, names.indexOf(playing));
      expect(q.isShuffled, isFalse);
    });

    test('unshuffle drops removed tracks and keeps ones queued since', () {
      final q = big()..shuffleUpcoming(Random(7));
      final removed = q.tracks.indexWhere((e) => e.id == 'f');
      q.removeAt(removed);
      q.insertNext(t('new'));

      q.unshuffle();

      expect(ids(q).contains('f'), isFalse);
      expect(ids(q)[q.currentIndex + 1], 'new'); // right after the current track
      expect(ids(q).where((e) => e != 'new').toList(),
          names.where((e) => e != 'f').toList());
    });

    test('unshuffle keeps a track that was queued twice', () {
      final a = t('a');
      final q = QueueModel()..replace([a, t('b'), t('c')]);
      q.shuffleUpcoming(Random(2));
      q.addToEnd(a); // same instance again

      q.unshuffle();

      expect(q.length, 4);
      expect(ids(q).where((e) => e == 'a').length, 2);
    });

    test('replace with shuffled plays the chosen track first', () {
      final q = QueueModel();
      q.replace(names.map(t).toList(),
          index: 4, shuffled: true, random: Random(9));

      expect(q.current!.id, 'e');
      expect(q.currentIndex, 0);
      expect(ids(q).toSet(), names.toSet());
      expect(q.isShuffled, isTrue);
    });
  });
}
