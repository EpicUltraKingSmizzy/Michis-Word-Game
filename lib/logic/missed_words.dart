/// Picks the words a solo player missed, for the "Words you missed" page at
/// the end of a solo round.
library;

import 'dart:math';

/// Tunable numbers for the missed-words page.
class MissedWordsTuning {
  MissedWordsTuning._();

  /// How many missed words to show.
  static const count = 10;

  /// Shortest and longest length of the "everyday" missed words that are
  /// shown first. Longer missed words only fill in when there aren't enough
  /// of these.
  static const shortMin = 3;
  static const shortMax = 5;
}

/// Picks up to [count] words from [solved] (every word on the board) that are
/// not in [found].
///
/// Words of [shortMin]-[shortMax] letters come first. If there are fewer
/// than [count] of those, the rest are filled with longer missed words,
/// shortest first. Words in [exclude] (the longest word(s) on the board,
/// which get their own reveal) are never picked.
///
/// Within a length group the choice is random but seeded by [seed], so the
/// same board always gives the same list. The result is sorted by length,
/// then alphabetically.
List<String> pickMissedWords({
  required Iterable<String> solved,
  required Iterable<String> found,
  Iterable<String> exclude = const [],
  int count = MissedWordsTuning.count,
  int shortMin = MissedWordsTuning.shortMin,
  int shortMax = MissedWordsTuning.shortMax,
  int seed = 0,
}) {
  if (count <= 0) return const [];
  final skip = {for (final w in found) w.toLowerCase(), for (final w in exclude) w.toLowerCase()};
  final missed = {
    for (final w in solved)
      if (!skip.contains(w.toLowerCase())) w.toLowerCase(),
  }.toList()
    ..sort(); // stable starting order, so the seeded shuffle is repeatable

  final rng = Random(seed);
  final short = missed.where((w) => w.length >= shortMin && w.length <= shortMax).toList()..shuffle(rng);
  final picked = short.take(count).toList();

  if (picked.length < count) {
    // Not enough everyday words left: fill with longer ones, shortest first
    // (random within each length).
    final byLen = <int, List<String>>{};
    for (final w in missed.where((w) => w.length > shortMax)) {
      byLen.putIfAbsent(w.length, () => []).add(w);
    }
    for (final len in byLen.keys.toList()..sort()) {
      final group = byLen[len]!..shuffle(rng);
      for (final w in group) {
        if (picked.length >= count) break;
        picked.add(w);
      }
      if (picked.length >= count) break;
    }
  }

  picked.sort((a, b) {
    final byLen = a.length.compareTo(b.length);
    return byLen != 0 ? byLen : a.compareTo(b);
  });
  return picked;
}

/// A repeatable seed for a board (same letters -> same missed-words list).
int missedWordsSeed(List<String> tiles) {
  var h = 17;
  for (final c in tiles.join().codeUnits) {
    h = (h * 31 + c) & 0x3fffffff;
  }
  return h;
}
