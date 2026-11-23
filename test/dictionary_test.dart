import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/dictionary.dart';

import 'test_helpers.dart';

void main() {
  test('small trie lookups', () {
    final d = Dictionary.fromWords(['cat', 'cats', 'car', 'Dog', 'ab', 'x-ray', 'bad'],
        blocked: {'bad'});
    expect(d.contains('cat'), isTrue);
    expect(d.contains('cats'), isTrue);
    expect(d.contains('car'), isTrue);
    expect(d.contains('dog'), isTrue);
    expect(d.contains('ca'), isFalse);
    expect(d.hasPrefix('ca'), isTrue);
    expect(d.contains('ab'), isFalse, reason: 'too short');
    expect(d.contains('x-ray'), isFalse, reason: 'not a-z');
    expect(d.contains('bad'), isFalse, reason: 'blocked');
    expect(d.wordCount, 4);
  });

  test('bundled dictionary has US and UK spellings and no blocked words', () {
    final d = realDictionary();
    expect(d.wordCount, greaterThan(120000));
    for (final w in ['color', 'colour', 'honor', 'honour', 'quiet', 'retard', 'gypsy', 'nips', 'poof']) {
      expect(d.contains(w), isTrue, reason: w);
    }
    final blocked = File('assets/dict/blocklist.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'));
    expect(blocked.length, 87);
    for (final w in blocked) {
      expect(d.contains(w.trim()), isFalse, reason: 'blocked word present');
    }
  });
}
