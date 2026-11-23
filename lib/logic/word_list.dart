/// Decodes the bundled word list.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'dictionary.dart';

/// Builds the game dictionary from the gzipped word list and the blocklist.
Dictionary dictionaryFromAssets(List<int> gzippedWords, String blocklistText) {
  final text = utf8.decode(const GZipDecoder().decodeBytes(gzippedWords));
  final blocked = Dictionary.parseLines(blocklistText).map((w) => w.toLowerCase()).toSet();
  return Dictionary.fromWords(const LineSplitter().convert(text), blocked: blocked);
}
