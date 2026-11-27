/// Decodes the bundled word lists.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'dictionary.dart';

/// The separate word-list files the game dictionary is built from.
///
/// [core] is the main dictionary. [slang], [profanity], [places] (words that
/// are only place names) and [personNames] (words that are only people's
/// names) are kept in their own files so a feature can leave them out later
/// (see [WordListOptions]). A word is in exactly one file;
/// tool/dict/check_duplicates.py and test/dictionary_test.dart enforce that.
enum WordListPart {
  core('assets/dict/words.txt.gz'),
  slang('assets/dict/slang.txt.gz'),
  profanity('assets/dict/profanity.txt.gz'),
  places('assets/dict/places.txt.gz'),
  personNames('assets/dict/person_names.txt.gz');

  const WordListPart(this.asset);

  /// Bundled asset path (a gzipped, one-word-per-line list).
  final String asset;
}

/// Path of the slur blocklist, applied to every word-list part.
const String blocklistAsset = 'assets/dict/blocklist.txt';

/// Which optional word lists are part of a dictionary. All are on by default.
class WordListOptions {
  const WordListOptions({this.slang = true, this.profanity = true, this.places = true, this.personNames = true});

  /// Everything on (the game's normal dictionary).
  static const all = WordListOptions();

  /// Only the core dictionary.
  static const coreOnly = WordListOptions(slang: false, profanity: false, places: false, personNames: false);

  final bool slang;
  final bool profanity;
  final bool places;
  final bool personNames;

  /// The parts to load. [WordListPart.core] is always included.
  Set<WordListPart> get parts => {
    WordListPart.core,
    if (slang) WordListPart.slang,
    if (profanity) WordListPart.profanity,
    if (places) WordListPart.places,
    if (personNames) WordListPart.personNames,
  };

  @override
  bool operator ==(Object other) =>
      other is WordListOptions &&
      other.slang == slang &&
      other.profanity == profanity &&
      other.places == places &&
      other.personNames == personNames;

  @override
  int get hashCode => Object.hash(slang, profanity, places, personNames);
}

/// Decodes one gzipped word-list file into its lines.
List<String> decodeWordList(List<int> gzipped) =>
    const LineSplitter().convert(utf8.decode(const GZipDecoder().decodeBytes(gzipped)));

/// Builds the game dictionary from the gzipped word-list parts and the
/// blocklist. Parts missing from [gzippedParts] or switched off in [options]
/// are skipped; the blocklist applies to all of them.
Dictionary dictionaryFromParts(
  Map<WordListPart, List<int>> gzippedParts,
  String blocklistText, {
  WordListOptions options = WordListOptions.all,
}) {
  final blocked = Dictionary.parseLines(blocklistText).map((w) => w.toLowerCase()).toSet();
  final words = <String>[];
  for (final part in WordListPart.values) {
    final bytes = gzippedParts[part];
    if (bytes == null || !options.parts.contains(part)) continue;
    words.addAll(decodeWordList(bytes));
  }
  return Dictionary.fromWords(words, blocked: blocked);
}

/// Builds a dictionary from the core word list only (plus the blocklist).
Dictionary dictionaryFromAssets(List<int> gzippedWords, String blocklistText) =>
    dictionaryFromParts({WordListPart.core: gzippedWords}, blocklistText);
