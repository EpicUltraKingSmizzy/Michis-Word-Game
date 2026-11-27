import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/missed_words.dart';
import 'package:michis_word_game/logic/scoring.dart';
import 'package:michis_word_game/logic/solver.dart';

import 'test_helpers.dart';

void main() {
  const short = ['cat', 'cats', 'scat', 'act', 'acts', 'tac', 'tacs', 'cast', 'scab', 'cab', 'cabs', 'bat', 'bats', 'tab', 'tabs'];
  const long = ['castab', 'abstract', 'catbats', 'scabbat'];

  test('picks 10 missed 3-5 letter words, never found ones', () {
    final found = ['cat', 'cats', 'act'];
    final out = pickMissedWords(solved: [...short, ...long], found: found, seed: 1);
    expect(out.length, 10);
    expect(out.toSet().length, 10);
    for (final w in out) {
      expect(found.contains(w), isFalse);
      expect(w.length, inInclusiveRange(3, 5));
    }
  });

  test('sorted by length, then alphabetically', () {
    final out = pickMissedWords(solved: [...short, ...long], found: const [], seed: 3);
    final sorted = List.of(out)
      ..sort((a, b) => a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b));
    expect(out, sorted);
  });

  test('same seed gives the same list; another seed can differ', () {
    final a = pickMissedWords(solved: short, found: const [], seed: 42);
    final b = pickMissedWords(solved: short.reversed, found: const [], seed: 42);
    expect(a, b);
    final others = {for (var s = 0; s < 20; s++) pickMissedWords(solved: short, found: const [], seed: s).join(',')};
    expect(others.length, greaterThan(1));
  });

  test('fills with longer words (shortest first) when short ones run out', () {
    final found = short.take(12).toList(); // 3 short words left
    final out = pickMissedWords(
      solved: [...short, 'abcdef', 'abcdeg', 'abcdefgh', 'abcdefghi', 'abcdefghij'],
      found: found,
      count: 6,
    );
    expect(out.where((w) => w.length <= 5).length, 3);
    expect(out.where((w) => w.length > 5).toList(), ['abcdef', 'abcdeg', 'abcdefgh']);
  });

  test('all short words found: only longer words, longest excluded (with ties)', () {
    final out = pickMissedWords(
      solved: [...short, 'castab', 'catbats', 'abstract', 'abstrac2'],
      found: short,
      exclude: const ['abstract', 'abstrac2'],
    );
    expect(out, ['castab', 'catbats']);
  });

  test('fewer than 10 available returns what there is; none returns empty', () {
    expect(pickMissedWords(solved: const ['cat', 'bat'], found: const ['cat']), ['bat']);
    expect(pickMissedWords(solved: const ['cat'], found: const ['cat']), isEmpty);
    expect(pickMissedWords(solved: const ['abstract'], found: const [], exclude: const ['abstract']), isEmpty);
    expect(pickMissedWords(solved: const [], found: const []), isEmpty);
  });

  test('case-insensitive matching of found words', () {
    expect(pickMissedWords(solved: const ['cat', 'bat'], found: const ['CAT']), ['bat']);
  });

  test('real board: never shows the longest-word reveal word', () {
    final dict = realDictionary();
    for (var seed = 0; seed < 5; seed++) {
      final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: Random(seed));
      final solved = solveBoard(b, dict);
      final longest = pickLongestWord(solved, const [])!;
      final out = pickMissedWords(
        solved: solved.keys,
        found: const [],
        exclude: longest.allLongest,
        seed: missedWordsSeed(b.tiles),
      );
      expect(out.length, min(10, solved.length - longest.allLongest.length));
      expect(out.any(longest.allLongest.contains), isFalse);
      expect(out.every(solved.containsKey), isTrue);
    }
  });
}
