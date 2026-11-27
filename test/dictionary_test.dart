import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/dictionary.dart';
import 'package:michis_word_game/logic/word_list.dart';

import 'test_helpers.dart';

Set<String> _part(WordListPart p) =>
    decodeWordList(File(p.asset).readAsBytesSync()).map((w) => w.trim()).where((w) => w.isNotEmpty).toSet();

void main() {
  test('small trie lookups', () {
    final d = Dictionary.fromWords(['cat', 'cats', 'car', 'Dog', 'ab', 'x-ray', 'bad'], blocked: {'bad'});
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
    expect(d.wordCount, greaterThan(100000));
    for (final w in ['color', 'colour', 'honor', 'honour', 'quiet', 'retard', 'gypsy', 'nips', 'poof']) {
      expect(d.contains(w), isTrue, reason: w);
    }
    final blocked = File(blocklistAsset).readAsLinesSync().where((l) => l.trim().isNotEmpty && !l.startsWith('#'));
    expect(blocked.length, 87);
    for (final w in blocked) {
      expect(d.contains(w.trim()), isFalse, reason: 'blocked word present');
    }
  });

  test('slang and profanity lists are separate files, loaded by default', () {
    final core = _part(WordListPart.core);
    final slang = _part(WordListPart.slang);
    final profanity = _part(WordListPart.profanity);
    expect(slang.length, 2000);
    expect(profanity.length, 110);
    final az = RegExp(r'^[a-z]{3,}$');
    for (final w in [...slang, ...profanity]) {
      expect(az.hasMatch(w), isTrue, reason: w);
    }
    expect(slang.intersection(core), isEmpty);
    expect(profanity.intersection(core), isEmpty);
    expect(slang.intersection(profanity), isEmpty);

    final d = realDictionary();
    for (final w in ['droid', 'droids', 'roid', 'roids', 'app', 'cafe', 'donut', 'bruh', 'yeet', 'rizz']) {
      expect(d.contains(w), isTrue, reason: w);
    }
    for (final w in ['badass', 'dumbass', 'butthurt']) {
      expect(d.contains(w), isTrue, reason: w);
    }
  });

  test('places and people\'s names are separate files, loaded by default', () {
    final core = _part(WordListPart.core);
    final places = _part(WordListPart.places);
    final names = _part(WordListPart.personNames);
    expect(places.length, greaterThan(2000));
    expect(names.length, greaterThan(4000));
    final az = RegExp(r'^[a-z]{3,}$');
    for (final w in [...places, ...names]) {
      expect(az.hasMatch(w), isTrue, reason: w);
    }
    // Words that are only a place or only a name live in their own file...
    for (final w in ['korea', 'paris', 'london', 'riga', 'mumbai', 'georgia']) {
      expect(places, contains(w));
    }
    for (final w in ['robert', 'michael', 'jim', 'sonu', 'byron']) {
      expect(names, contains(w));
    }
    final surnames = _part(WordListPart.surnames);
    expect(surnames.length, greaterThan(1500));
    for (final w in surnames) {
      expect(az.hasMatch(w), isTrue, reason: w);
    }
    // Surname-only words have their own file; a name that is also a given name stays in person_names.
    for (final w in ['kubrick', 'asimov', 'wei', 'martinez', 'sharma', 'nguyen']) {
      expect(surnames, contains(w));
    }
    expect(surnames.intersection(names), isEmpty);
    expect(core, contains('gnu'));
    // ...but a word with another meaning stays in the main list.
    for (final w in [
      'turkey',
      'guinea',
      'china',
      'nice',
      'reading',
      'rob',
      'bill',
      'mark',
      'will',
      'jack',
      'grace',
      'bob',
    ]) {
      expect(core, contains(w));
    }
    final d = realDictionary();
    for (final w in ['korea', 'robert', 'turkey', 'rob']) {
      expect(d.contains(w), isTrue, reason: w);
    }
  });

  test('no word is repeated in a file or in more than one file', () {
    final seen = <String, WordListPart>{};
    for (final part in WordListPart.values) {
      final words = decodeWordList(File(part.asset).readAsBytesSync())
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList();
      final unique = words.toSet();
      expect(unique.length, words.length, reason: 'repeated word inside ${part.asset}');
      for (final w in unique) {
        final other = seen[w];
        expect(other, isNull, reason: '$w is in both ${other?.asset} and ${part.asset}');
        seen[w] = part;
      }
    }
  });

  test('each optional list can be switched off', () {
    final parts = bundledWordListParts();
    final blocklist = File(blocklistAsset).readAsStringSync();
    final noSlang = dictionaryFromParts(parts, blocklist, options: const WordListOptions(slang: false));
    final noProfanity = dictionaryFromParts(parts, blocklist, options: const WordListOptions(profanity: false));
    final core = dictionaryFromParts(parts, blocklist, options: WordListOptions.coreOnly);
    expect(noSlang.contains('droid'), isFalse);
    expect(noSlang.contains('badass'), isTrue);
    expect(noProfanity.contains('droid'), isTrue);
    expect(noProfanity.contains('badass'), isFalse);
    expect(core.contains('droid'), isFalse);
    expect(core.contains('badass'), isFalse);
    expect(core.contains('quiet'), isTrue);
    final noPlaces = dictionaryFromParts(parts, blocklist, options: const WordListOptions(places: false));
    final noNames = dictionaryFromParts(parts, blocklist, options: const WordListOptions(personNames: false));
    final noSurnames = dictionaryFromParts(parts, blocklist, options: const WordListOptions(surnames: false));
    expect(noSurnames.contains('martinez'), isFalse);
    expect(noSurnames.contains('robert'), isTrue);
    expect(noNames.contains('martinez'), isTrue);
    expect(core.contains('martinez'), isFalse);
    expect(noPlaces.contains('korea'), isFalse);
    expect(noPlaces.contains('robert'), isTrue);
    expect(noNames.contains('robert'), isFalse);
    expect(noNames.contains('korea'), isTrue);
    expect(core.contains('korea'), isFalse);
    expect(core.contains('robert'), isFalse);
    final extras =
        _part(WordListPart.slang).length +
        _part(WordListPart.profanity).length +
        _part(WordListPart.places).length +
        _part(WordListPart.personNames).length +
        _part(WordListPart.surnames).length;
    expect(realDictionary().wordCount, core.wordCount + extras);
  });

  test('the blocklist also applies to the optional lists', () {
    final d = dictionaryFromParts(bundledWordListParts(), 'droid\nbadass\nkorea\nrobert\nmartinez\n');
    expect(d.contains('droid'), isFalse);
    expect(d.contains('badass'), isFalse);
    expect(d.contains('korea'), isFalse);
    expect(d.contains('robert'), isFalse);
    expect(d.contains('martinez'), isFalse);
    expect(d.contains('droids'), isTrue);
  });

  test('obscure words and proper nouns were removed', () {
    final d = realDictionary();
    for (final w in [
      'ceyx',
      'ersh',
      'fley',
      'quidnunc',
      'gomel',
      'dneprodzerzhinsk',
      'befools',
      'airting',
      'superfuse',
      'supposititious',
    ]) {
      expect(d.contains(w), isFalse, reason: w);
    }
    final removed = File('tool/dict/removed_words.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    expect(removed.length, greaterThanOrEqualTo(25000));
    for (final w in removed) {
      expect(d.contains(w), isFalse, reason: 'removed word present: $w');
    }
  });
}
