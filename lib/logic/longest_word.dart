/// Rules for "Longest word only" rounds: which word counts, the letter
/// scores used to break ties, and the better words a solo player missed.
library;

import 'models.dart';

/// Tie-breaker points for each letter.
const Map<String, int> letterPoints = {
  'a': 0, 'e': 0, 'i': 0, 'o': 0, //
  'u': 1, 'y': 1, 's': 1, 'r': 1, 't': 1, 'l': 1, 'n': 1,
  'h': 1, 'c': 1, 'd': 1, 'f': 1, 'b': 1, 'm': 1,
  'w': 2, 'p': 2, 'g': 2, 'j': 2, 'v': 2,
  'z': 3, 'x': 3, 'q': 3, 'k': 3,
};

/// Tie-breaker points for one letter (0 for anything that isn't a-z).
int letterScoreOf(String letter) => letterPoints[letter.toLowerCase()] ?? 0;

/// A word's tie-breaker total: the sum of its letters. A QU tile counts as
/// its two letters, Q (3) and U (1).
int letterScore(String word) => word.split('').fold(0, (s, c) => s + letterScoreOf(c));

/// Positive when [a] beats [b]: longer wins, then the higher letter score.
int compareWordStrength(String a, String b) {
  final byLen = a.length.compareTo(b.length);
  if (byLen != 0) return byLen;
  return letterScore(a).compareTo(letterScore(b));
}

/// The word that counts for a player: the longest, then the highest letter
/// score, then the one found first. [foundInOrder] is the player's words in
/// the order they were found. Null when they found nothing.
String? pickCountedWord(Iterable<String> foundInOrder) {
  String? best;
  for (final w in foundInOrder) {
    if (best == null || compareWordStrength(w, best) > 0) best = w;
  }
  return best;
}

/// The tie-breaker for players tied on the top score, or null when there is
/// no tie. [counted] maps player id to their counted word (players with no
/// word are left out); [scores] maps player id to score. [order] is the order
/// to list players in.
TieBreak? resolveTieBreak({
  required Map<String, String> counted,
  required Map<String, int> scores,
  required List<String> order,
}) {
  final ids = order.where(counted.containsKey).toList();
  if (ids.length < 2) return null;
  final top = ids.map((id) => scores[id] ?? 0).reduce((a, b) => a > b ? a : b);
  if (top <= 0) return null;
  final tied = ids.where((id) => (scores[id] ?? 0) == top).toList();
  if (tied.length < 2) return null;
  final words = [for (final id in tied) counted[id]!];
  final same = words.toSet().length == 1;
  final List<String> winners;
  if (same) {
    winners = List.of(tied);
  } else {
    final best = words.map(letterScore).reduce((a, b) => a > b ? a : b);
    winners = [for (var i = 0; i < tied.length; i++) if (letterScore(words[i]) == best) tied[i]];
  }
  return TieBreak(playerIds: tied, words: words, winnerIds: winners, sameWord: same);
}

/// Words on the board that would have beaten [counted]: longer, or the same
/// length with a higher letter score. Best first (longest, then highest
/// letter score, then alphabetical), at most [count]. With no counted word,
/// every word qualifies. Empty when the player found the best word.
List<String> pickBetterMissedWords({
  required Iterable<String> solved,
  required String? counted,
  int count = 10,
}) {
  final better = {
    for (final w in solved)
      if (counted == null || compareWordStrength(w.toLowerCase(), counted.toLowerCase()) > 0) w.toLowerCase(),
  }.toList()
    ..sort((a, b) {
      final s = compareWordStrength(b, a);
      return s != 0 ? s : a.compareTo(b);
    });
  return better.take(count).toList();
}
