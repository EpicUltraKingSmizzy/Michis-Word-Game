import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/board.dart';
import 'package:michis_word_game/logic/challenge.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/net/chunker.dart';

import 'test_helpers.dart';

Challenge sampleChallenge(Board b, Map<String, List<int>> solved, GameSettings s, Random rng, int players) {
  final words = solved.keys.toList()..sort();
  return Challenge(
    settings: s,
    board: b,
    fromIndex: 1,
    players: [
      for (var i = 0; i < players; i++)
        () {
          // A decent player finds roughly a quarter of the board.
          final mine = words.where((_) => rng.nextDouble() < 0.25).toList();
          return ChallengePlayer(
            name: ['Michi', 'Ann ✨', 'Bob', 'Cat'][i],
            avatar: i * 3,
            score: mine.fold(0, (a, w) => a + wordPoints(w)),
            wordCount: mine.length,
            words: mine,
          );
        }(),
    ],
  );
}

void main() {
  test('challenge links round-trip the board, options, and word lists', () {
    final d = realDictionary();
    final rng = Random(11);
    for (final size in [4, 5, 6]) {
      final s = GameSettings(gridSize: size, minWordLength: 3, durationSeconds: 150);
      final b = generateGoodBoard(size: size, minWordLength: 3, dictionary: d, random: rng);
      final solved = solveBoard(b, d);
      final c = sampleChallenge(b, solved, s, rng, 3);
      final url = challengeUrl(c, d);
      final back = decodeChallenge(Uri.parse(url).queryParameters['d']!, d);
      expect(back.board.tiles, b.tiles);
      expect(back.settings, s);
      expect(back.fromIndex, 1);
      expect(back.players.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(back.players[i].name, c.players[i].name);
        expect(back.players[i].avatar, c.players[i].avatar);
        expect(back.players[i].score, c.players[i].score);
        expect(back.players[i].wordCount, c.players[i].wordCount);
        expect(back.players[i].words!.toSet(), c.players[i].words!.toSet());
      }
      expect(challengeDataFromUri(Uri.parse(url)), isNotNull);
    }
  });

  test('typical link lengths', () {
    final d = realDictionary();
    final rng = Random(5);
    for (final size in [4, 5, 6]) {
      for (final players in [1, 2, 4]) {
        final lens = <int>[];
        for (var k = 0; k < 30; k++) {
          final s = GameSettings(gridSize: size, minWordLength: 3, durationSeconds: 120);
          final b = generateGoodBoard(size: size, minWordLength: 3, dictionary: d, random: rng);
          lens.add(challengeUrl(sampleChallenge(b, solveBoard(b, d), s, rng, players), d).length);
        }
        lens.sort();
        // ignore: avoid_print
        print('LINKLEN ${size}x$size players=$players median=${lens[15]} max=${lens.last}');
        expect(lens.last, lessThanOrEqualTo(maxChallengeUrlLength));
      }
    }
  });

  test('a link from a different dictionary keeps scores but drops words', () {
    final d = realDictionary();
    final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: d, random: Random(2));
    const s = GameSettings();
    final c = sampleChallenge(b, solveBoard(b, d), s, Random(1), 2);
    final data = encodeChallenge(c, d);
    // Same board, smaller dictionary: the solution list doesn't match.
    final other = realDictionaryWithout(solveBoard(b, d).keys.first);
    final back = decodeChallenge(data, other);
    expect(back.players.first.score, c.players.first.score);
    expect(back.players.first.words, isNull);
  });

  test('broken links throw FormatException', () {
    final d = realDictionary();
    expect(() => decodeChallenge('not-a-link', d), throwsFormatException);
    expect(() => decodeChallenge('', d), throwsFormatException);
  });

  test('chunker splits and reassembles big messages', () {
    final big = {'t': 'chat', 'text': 'x' * 50000, 'n': 3};
    final parts = chunkMessage(big);
    expect(parts.length, greaterThan(3));
    final r = Reassembler();
    Map<String, dynamic>? out;
    for (final p in parts) {
      out = r.add(p);
    }
    expect(out, big);
    expect(chunkMessage({'t': 'ping'}), [
      {'t': 'ping'}
    ]);
    expect(r.add({'t': 'ping'}), {'t': 'ping'});
  });
}
