import 'dart:io';

import 'package:michis_word_game/logic/dictionary.dart';
import 'package:michis_word_game/logic/word_list.dart';

Dictionary? _cached;

/// The gzipped bytes of every bundled word-list part.
Map<WordListPart, List<int>> bundledWordListParts() => {
      for (final part in WordListPart.values) part: File(part.asset).readAsBytesSync(),
    };

/// The real bundled dictionary, as the game builds it (loaded once per test run).
Dictionary realDictionary() => _cached ??= dictionaryFromParts(
      bundledWordListParts(),
      File(blocklistAsset).readAsStringSync(),
    );

/// The real dictionary minus one word (to fake a different version).
Dictionary realDictionaryWithout(String word) {
  final words = [
    for (final bytes in bundledWordListParts().values) ...decodeWordList(bytes),
  ];
  return Dictionary.fromWords(words.where((w) => w.trim() != word));
}
