import 'dart:io';

import 'package:michis_word_game/logic/dictionary.dart';
import 'package:michis_word_game/logic/word_list.dart';

Dictionary? _cached;

/// The real bundled dictionary (loaded once per test run).
Dictionary realDictionary() => _cached ??= dictionaryFromAssets(
      File('assets/dict/words.txt.gz').readAsBytesSync(),
      File('assets/dict/blocklist.txt').readAsStringSync(),
    );
