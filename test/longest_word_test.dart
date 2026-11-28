import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/board.dart';
import 'package:michis_word_game/logic/challenge.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/longest_word.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/scoring.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/net/fake_link.dart';
import 'package:michis_word_game/state/session.dart';

import 'test_helpers.dart';

void main() {
  group('letter scores', () {
    test('match the table', () {
      for (final c in 'aeio'.split('')) {
        expect(letterScoreOf(c), 0, reason: c);
      }
      for (final c in 'uysrtlnhcdfbm'.split('')) {
        expect(letterScoreOf(c), 1, reason: c);
      }
      for (final c in 'wpgjv'.split('')) {
        expect(letterScoreOf(c), 2, reason: c);
      }
      for (final c in 'zxqk'.split('')) {
        expect(letterScoreOf(c), 3, reason: c);
      }
      expect(letterPoints.length, 26, reason: 'every letter has a score');
      expect(letterScoreOf('K'), 3, reason: 'upper case works too');
    });

    test('a word adds up its letters; QU counts as Q + U', () {
      expect(letterScore('cat'), 2);
      expect(letterScore('quiz'), 3 + 1 + 0 + 3);
      expect(letterScore('aeio'), 0);
    });
  });

  group('counted word', () {
    test('longest wins', () => expect(pickCountedWord(['cat', 'stone', 'tones', 'at']), 'stone'));
    test('same length: higher letter score wins', () {
      // stone = 1+1+0+1+0 = 3, joker = 2+0+3+0+1 = 6
      expect(pickCountedWord(['stone', 'joker']), 'joker');
    });
    test('same length and letter score: found first wins', () {
      expect(pickCountedWord(['stone', 'tones']), 'stone');
      expect(pickCountedWord(['tones', 'stone']), 'tones');
    });
    test('nothing found', () => expect(pickCountedWord(const []), isNull));
  });

  group('tie-breaker', () {
    test('no tie, no tie-breaker', () {
      expect(resolveTieBreak(counted: {'a': 'stone', 'b': 'cat'}, scores: {'a': 3, 'b': 1}, order: ['a', 'b']), isNull);
    });
    test('higher letter total wins', () {
      final tb = resolveTieBreak(counted: {'a': 'stone', 'b': 'joker'}, scores: {'a': 3, 'b': 3}, order: ['a', 'b'])!;
      expect(tb.playerIds, ['a', 'b']);
      expect(tb.words, ['stone', 'joker']);
      expect(tb.winnerIds, ['b']);
      expect(tb.sameWord, isFalse);
    });
    test('same word: "Same Word!" and still a tie', () {
      final tb = resolveTieBreak(counted: {'a': 'stone', 'b': 'stone'}, scores: {'a': 3, 'b': 3}, order: ['a', 'b'])!;
      expect(tb.sameWord, isTrue);
      expect(tb.winnerIds, ['a', 'b']);
    });
    test('different words with equal letter totals share the win', () {
      final tb = resolveTieBreak(counted: {'a': 'stone', 'b': 'tones'}, scores: {'a': 3, 'b': 3}, order: ['a', 'b'])!;
      expect(tb.sameWord, isFalse);
      expect(tb.winnerIds, ['a', 'b']);
    });
    test('only players tied for the top score take part', () {
      final tb = resolveTieBreak(
        counted: {'a': 'stone', 'b': 'joker', 'c': 'cat', 'd': 'dog'},
        scores: {'a': 3, 'b': 3, 'c': 1, 'd': 1},
        order: ['a', 'b', 'c', 'd'],
      )!;
      expect(tb.playerIds, ['a', 'b']);
    });
    test('nobody scored: no tie-breaker', () {
      expect(resolveTieBreak(counted: const {}, scores: {'a': 0, 'b': 0}, order: ['a', 'b']), isNull);
    });
  });

  group('better missed words', () {
    const solved = ['cat', 'stone', 'tones', 'joker', 'stones', 'jokers', 'at'];
    test('only longer, or same length with a higher letter score; best first', () {
      expect(pickBetterMissedWords(solved: solved, counted: 'stone'), ['jokers', 'stones', 'joker']);
    });
    test('equal letter score at the same length is not better', () {
      expect(pickBetterMissedWords(solved: solved, counted: 'stone').contains('tones'), isFalse);
    });
    test('empty when the player found the best word', () {
      expect(pickBetterMissedWords(solved: solved, counted: 'jokers'), isEmpty);
    });
    test('at most 10, and every word qualifies with nothing found', () {
      final many = [for (var i = 0; i < 30; i++) 'w${'x' * (i % 7)}abc$i'];
      expect(pickBetterMissedWords(solved: many, counted: null).length, 10);
      expect(pickBetterMissedWords(solved: solved, counted: null).first, 'jokers');
    });
  });

  group('scoreRound in "Longest word only"', () {
    final board = Board(4, 'STONEJKRABCDEFGH'.split(''));
    const settings = GameSettings(minWordLength: 3, longestOnly: true);
    const players = [
      PlayerInfo(id: 'a', name: 'Ann', avatar: 0),
      PlayerInfo(id: 'b', name: 'Bob', avatar: 1),
      PlayerInfo(id: 'c', name: 'Cy', avatar: 2),
    ];
    Submission sub(String w, int t) => Submission(word: w, path: const [0, 1, 2], atMs: t);
    final solved = {for (final w in ['cat', 'stone', 'tones', 'joker', 'dog']) w: const [0, 1, 2]};

    test('only the counted word scores, no unique double, tie-breaker by letters', () {
      final r = scoreRound(
        board: board,
        settings: settings,
        players: players,
        submissions: {
          'a': [sub('cat', 1), sub('stone', 2), sub('dog', 3)],
          'b': [sub('joker', 5)],
          'c': [sub('cat', 4)],
        },
        solved: solved,
      );
      expect(r.playerById('a')!.score, 3);
      expect(r.playerById('a')!.countedWord, 'stone');
      expect(r.playerById('a')!.wordCount, 3, reason: 'every word still counts as found');
      expect(r.playerById('b')!.score, 3, reason: 'unique, but not doubled');
      expect(r.playerById('c')!.score, 1);
      expect(r.replay.map((e) => e.word).toSet(), {'stone', 'joker', 'cat'});
      expect(r.replay.every((e) => e.noBonus), isTrue);
      final catEntry = r.replay.firstWhere((e) => e.word == 'cat');
      expect(catEntry.finders, ['c'], reason: "cat isn't Ann's counted word");
      expect(r.tieBreak, isNotNull);
      expect(r.tieBreak!.winnerIds, ['b']);
      expect(r.winners.map((p) => p.player.id), ['b']);
      expect(r.players.first.player.id, 'b', reason: 'tie-breaker winner ranks first');
      expect(r.highlights.any((h) => h.title == 'Jackpot Word'), isFalse);

      // Survives the trip to the other players.
      final back = RoundResults.fromJson(r.toJson());
      expect(back.settings.longestOnly, isTrue);
      expect(back.tieBreak!.winnerIds, ['b']);
      expect(back.playerById('a')!.countedWord, 'stone');
      expect(back.replay.first.noBonus, isTrue);
      expect(back.winners.map((p) => p.player.id), ['b']);
    });

    test('same word: shared win', () {
      final r = scoreRound(
        board: board,
        settings: settings,
        players: players.take(2).toList(),
        submissions: {
          'a': [sub('stone', 1)],
          'b': [sub('stone', 2)],
        },
        solved: solved,
      );
      expect(r.tieBreak!.sameWord, isTrue);
      expect(r.winners.length, 2);
      expect(r.replay.single.finders, ['a', 'b']);
      expect(r.replay.single.pointsEach, 3);
    });
  });

  test('normal rounds are unchanged (unique words still double)', () {
    final board = Board(4, 'STONEJKRABCDEFGH'.split(''));
    final r = scoreRound(
      board: board,
      settings: const GameSettings(),
      players: const [PlayerInfo(id: 'a', name: 'A', avatar: 0)],
      submissions: {
        'a': [const Submission(word: 'stone', path: [0], atMs: 0), const Submission(word: 'cat', path: [0], atMs: 1)],
      },
      solved: const {'stone': [0], 'cat': [0]},
    );
    expect(r.playerById('a')!.score, 3 * 2 + 1 * 2);
    expect(r.tieBreak, isNull);
    expect(r.playerById('a')!.countedWord, isNull);
  });

  test('settings JSON and challenge links keep the mode', () {
    const s = GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 90, longestOnly: true);
    expect(GameSettings.fromJson(s.toJson()), s);
    expect(GameSettings.fromJson(const GameSettings().toJson()).longestOnly, isFalse);
    final dict = realDictionary();
    final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: Random(2));
    final words = (solveBoard(b, dict).keys.toList()..sort()).take(4).toList();
    final c = Challenge(settings: s, board: b, players: [
      ChallengePlayer(name: 'Ann', avatar: 1, score: 2, wordCount: words.length, words: words),
    ]);
    final back = decodeChallenge(encodeChallenge(c, dict), dict);
    expect(back.settings, s);
    expect(back.players.first.words, words);
    final normal = decodeChallenge(
        encodeChallenge(Challenge(settings: s.copyWith(longestOnly: false, minWordLength: 4), board: b, players: const []), dict),
        dict);
    expect(normal.settings.longestOnly, isFalse);
    expect(normal.settings.minWordLength, 4);
  });

  test('the host syncs the mode to players', () async {
    final dict = realDictionary();
    final net = FakeNetwork();
    final host = await HostSession.create(
        dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Michi', avatar: 2, random: Random(7));
    final p1 = await ClientSession.join(
        dictionary: dict, linkFactory: () => FakeClientLink(net, 'c1'), roomCode: host.roomCode, name: 'Ann', avatar: 1);
    host.updateSettings(host.settings.copyWith(longestOnly: true, minWordLength: 3));
    expect(p1.settings.longestOnly, isTrue);
    host.startGame();
    expect(p1.roundSettings.longestOnly, isTrue);
    await host.leave();
    await p1.leave();
  });
}
