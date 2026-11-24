import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/board.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/path_validation.dart';
import 'package:michis_word_game/logic/solver.dart';

import 'test_helpers.dart';

Board sample() => Board(4, 'CATS ODEN RUQL MPIX'.replaceAll(' ', '').split('').map((c) => c == 'Q' ? 'QU' : c).toList());

void main() {
  test('dice sets have the right sizes', () {
    expect(classicDice.length, 16);
    expect(bigDice.length, 25);
    expect(superBigDice.length, 36);
    for (final d in [...classicDice, ...bigDice, ...superBigDice]) {
      expect(d.length, 6);
    }
  });

  test('neighbours cover all 8 directions', () {
    final b = sample();
    expect(b.neighbors(0).toSet(), {1, 4, 5});
    expect(b.neighbors(5).toSet(), {0, 1, 2, 4, 6, 8, 9, 10});
    expect(b.isAdjacent(0, 5), isTrue);
    expect(b.isAdjacent(0, 2), isFalse);
  });

  test('path validation', () {
    final b = sample();
    expect(isValidPath(b, [0, 1, 2]), isTrue);
    expect(isValidPath(b, [0, 5, 10, 15]), isTrue, reason: 'diagonal');
    expect(isValidPath(b, [0, 2]), isFalse, reason: 'not adjacent');
    expect(isValidPath(b, [0, 1, 0]), isFalse, reason: 'reused tile');
    expect(isValidPath(b, [0, 16]), isFalse, reason: 'off board');
    expect(canExtendPath(b, [0, 1], 2), isTrue);
    expect(canExtendPath(b, [0, 1], 0), isFalse);
  });

  test('qu tile spells two letters', () {
    final b = sample();
    expect(b.label(10), 'Qu');
    expect(b.wordForPath([10, 9]), 'quu');
  });

  test('submission classification', () {
    final d = realDictionary();
    final b = sample();
    SubmissionResult check(List<int> p, {Set<String> found = const {}, int min = 3}) =>
        checkSubmission(board: b, path: p, dictionary: d, minWordLength: min, alreadyFound: found);
    expect(check([0, 1, 2]), SubmissionResult.added); // cat
    expect(check([0, 1]), SubmissionResult.tooShort);
    expect(check([0, 1, 2, 3], min: 5), SubmissionResult.tooShort);
    expect(check([0, 1, 2], found: {'cat'}), SubmissionResult.alreadyFound);
    expect(check([0, 4, 0]), SubmissionResult.invalidPath);
    expect(check([3, 2, 1]), SubmissionResult.notAWord); // sta? -> check
  });

  test('solver finds words with valid paths and both spellings', () {
    final d = realDictionary();
    // C O L X
    // X U O X
    // X X R X
    // X X X X  -> color and colour both reachable
    final b = Board(4, 'COLXXUOXXXRXXXXX'.split(''));
    final words = solveBoard(b, d);
    expect(words.containsKey('color'), isTrue);
    expect(words.containsKey('colour'), isTrue);
    for (final e in words.entries) {
      expect(isValidPath(b, e.value), isTrue);
      expect(b.wordForPath(e.value), e.key);
      expect(e.key.length, greaterThanOrEqualTo(3));
    }
    final min5 = solveBoard(b, d, minWordLength: 5);
    expect(min5.keys.every((w) => w.length >= 5), isTrue);
  });

  test('generated boards pass the quality filter', () {
    final d = realDictionary();
    final rng = Random(42);
    for (final size in [4, 5, 6]) {
      for (final minLen in [3, 4, 5]) {
        for (var i = 0; i < 5; i++) {
          final b = generateGoodBoard(size: size, minWordLength: minLen, dictionary: d, random: rng);
          expect(b.length, size * size);
          final a = analyzeBoard(b, d, minWordLength: minLen);
          expect(a.wordCount, greaterThanOrEqualTo(minWordsFor(size, minLen)), reason: '$size x $size min $minLen\n$b');
          expect(a.deadTiles, isEmpty, reason: 'every letter is in some word\n$b');
        }
      }
    }
  });

  test('analyzeBoard finds dead letters and matches solveBoard', () {
    final d = realDictionary();
    // X in the corner surrounded by consonants can't be in any word.
    final b = Board(4, 'XBCD BCDF CATS DOGS'.replaceAll(' ', '').split(''));
    final a = analyzeBoard(b, d);
    expect(a.words.keys.toSet(), solveBoard(b, d).keys.toSet());
    expect(a.deadTiles, contains(0));
    expect(a.covered[8], isTrue, reason: 'C of CAT');
    for (final e in a.words.entries) {
      expect(b.wordForPath(e.value), e.key);
    }
    expect(isGoodBoard(a, 4, 3), isFalse);
  });

  test('minimum word table covers every setting', () {
    for (final size in [4, 5, 6]) {
      for (final minLen in [3, 4, 5]) {
        expect(minWordsFor(size, minLen), greaterThan(0));
      }
    }
  });
}
