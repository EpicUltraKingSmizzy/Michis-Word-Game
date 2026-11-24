import 'dart:convert';
import 'package:archive/archive.dart';
import 'dart:io';

import 'package:michis_word_game/logic/dictionary.dart';
import 'package:michis_word_game/logic/word_list.dart';

Dictionary? _cached;

/// The real bundled dictionary (loaded once per test run).
Dictionary realDictionary() => _cached ??= dictionaryFromAssets(
      File('assets/dict/words.txt.gz').readAsBytesSync(),
      File('assets/dict/blocklist.txt').readAsStringSync(),
    );

/// The real dictionary minus one word (to fake a different version).
Dictionary realDictionaryWithout(String word) {
  final words = utf8
      .decode(const GZipDecoder().decodeBytes(File('assets/dict/words.txt.gz').readAsBytesSync()))
      .split('\n');
  return Dictionary.fromWords(words.where((w) => w.trim() != word));
}
