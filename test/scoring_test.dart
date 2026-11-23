import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/board.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/replay_order.dart';
import 'package:michis_word_game/logic/room_code.dart';
import 'package:michis_word_game/logic/scoring.dart';

WordEntry e(String w, List<String> f) => WordEntry(word: w, path: const [0], finders: f);

void main() {
  test('points are letters minus two', () {
    expect(wordPoints('cat'), 1);
    expect(wordPoints('cats'), 2);
    expect(wordPoints('quiet'), 3);
    expect(e('cats', ['a']).pointsEach, 4, reason: 'unique doubles');
    expect(e('cats', ['a', 'b']).pointsEach, 2);
  });

  final board = Board(4, 'CATSODENRUXLMPIX'.split(''));
  const a = PlayerInfo(id: 'a', name: 'Ann', avatar: 0, isHost: true);
  const b = PlayerInfo(id: 'b', name: 'Bob', avatar: 1);

  test('scoreRound: shared, unique, first path wins, dedupe', () {
    final r = scoreRound(
      board: board,
      settings: const GameSettings(),
      players: [a, b],
      submissions: {
        'a': const [
          Submission(word: 'cat', path: [0, 1, 2], atMs: 500),
          Submission(word: 'cats', path: [0, 1, 2, 3], atMs: 900),
          Submission(word: 'cat', path: [0, 1, 2], atMs: 950),
        ],
        'b': const [
          Submission(word: 'cat', path: [9, 9, 9], atMs: 100),
          Submission(word: 'den', path: [5, 6, 7], atMs: 2000),
        ],
      },
      solved: {'cat': [0, 1, 2], 'cats': [0, 1, 2, 3], 'den': [5, 6, 7], 'cadets': [0, 1, 5, 6, 2, 3]},
    );
    final ann = r.playerById('a')!, bob = r.playerById('b')!;
    expect(ann.words, ['cat', 'cats']);
    expect(ann.score, 1 + 4);
    expect(bob.score, 1 + 2);
    expect(r.replay.first.word, 'cat');
    expect(r.replay.first.path, [9, 9, 9], reason: 'earliest finder path kept');
    expect(r.replay.first.finders, ['b', 'a']);
    expect(r.replay.length, 3);
    expect(r.longest!.word, 'cadets');
    expect(r.longest!.allFound, isFalse);
    // JSON round trip.
    final back = RoundResults.fromJson(r.toJson());
    expect(back.replay.map((x) => x.word), r.replay.map((x) => x.word));
    expect(back.playerById('a')!.score, 5);
  });

  test('longest word congratulates when all found', () {
    final info = pickLongestWord({'cat': [0], 'cats': [1], 'dens': [2]}, [e('cats', ['a']), e('dens', ['b', 'a'])]);
    expect(info!.allFound, isTrue);
    expect(info.allLongest, ['cats', 'dens']);
    expect(info.foundBy.toSet(), {'a', 'b'});
  });

  test('replay order: shared by finders desc, then uniques; totals preserved', () {
    final entries = [
      e('two', ['a', 'b']),
      e('three', ['a', 'b', 'c']),
      for (final w in ['aaa', 'aaaa', 'aaaaa', 'aaaaaa', 'aab', 'aac']) e(w, ['a']),
      for (final w in ['bbb', 'bbbb', 'bbbbb', 'bbbbbbb', 'bbc']) e(w, ['b']),
      e('ccc', ['c']),
    ];
    final order = orderReplay(entries, ['a', 'b', 'c']);
    expect(order.length, entries.length);
    expect(order.toSet(), entries.toSet());
    expect(order[0].word, 'three');
    expect(order[1].word, 'two');
    expect(order.skip(2).every((x) => x.isUnique), isTrue);
    // Each player's biggest unique word comes after all their other uniques.
    for (final p in ['a', 'b']) {
      final mine = order.where((x) => x.isUnique && x.finders.first == p).toList();
      final maxPts = mine.map((x) => x.pointsEach).reduce((m, v) => v > m ? v : m);
      expect(mine.last.pointsEach, maxPts);
    }
    expect(countLeadChanges(order, ['a', 'b', 'c']), greaterThanOrEqualTo(3));
  });

  test('balanced game swaps the lead several times', () {
    final entries = [
      for (var i = 0; i < 8; i++) e('a${'x' * (i % 4 + 2)}$i', ['a']),
      for (var i = 0; i < 8; i++) e('b${'y' * (i % 4 + 2)}$i', ['b']),
    ];
    final order = orderReplay(entries, ['a', 'b']);
    expect(countLeadChanges(order, ['a', 'b']), greaterThanOrEqualTo(5));
  });

  test('replay timing', () {
    expect(replayStepDuration(e('cat', ['a', 'b'])).inMilliseconds, 750);
    expect(replayStepDuration(e('crate', ['a', 'b'])).inMilliseconds, 750);
    expect(replayStepDuration(e('crate', ['a'])).inMilliseconds, 1250);
    expect(replayStepDuration(e('cart', ['a'])).inMilliseconds, 750);
  });

  test('highlights', () {
    final r = scoreRound(
      board: board,
      settings: const GameSettings(),
      players: [a, b],
      submissions: {
        'a': [for (var i = 0; i < 10; i++) Submission(word: 'w${'a' * (i % 3 + 2)}$i', path: const [0], atMs: i)],
        'b': [for (var i = 0; i < 10; i++) Submission(word: 'w${'a' * (i % 3 + 2)}$i', path: const [0], atMs: i + 1)],
      },
      solved: const {},
    );
    final titles = r.highlights.map((h) => h.title).toList();
    expect(titles, contains('PICKING UP STEAM'));
    expect(titles, contains('PHOTO FINISH'));
    expect(titles, contains('Word Machine'));
  });

  test('room codes and join links', () {
    final code = generateRoomCode();
    expect(isValidRoomCode(code), isTrue);
    expect(hostPeerId('ABCD'), 'mwg-abcd');
    expect(joinUrl('ABCD'), 'https://michiswordgame.github.io/join?code=ABCD');
    expect(roomCodeFromUri(Uri.parse('https://michiswordgame.github.io/join?code=abcd')), 'ABCD');
    expect(roomCodeFromUri(Uri.parse('https://michiswordgame.github.io/')), isNull);
    expect(normalizeRoomCode(' ab-cd '), 'ABCD');
  });
}
