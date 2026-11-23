/// Turns every player's submissions into round results.
library;

import 'board.dart';
import 'models.dart';
import 'replay_order.dart';
import 'solver.dart';
import 'stats.dart';

/// Builds the full results for a round.
///
/// [submissions] maps player id to that player's accepted words. When several
/// players found a word, the path from the earliest submission is kept.
/// [solved] is every word on the board (from [solveBoard]).
RoundResults scoreRound({
  required Board board,
  required GameSettings settings,
  required List<PlayerInfo> players,
  required Map<String, List<Submission>> submissions,
  required Map<String, List<int>> solved,
}) {
  final firstPath = <String, List<int>>{};
  final firstTime = <String, int>{};
  final finders = <String, List<(String, int)>>{};

  for (final p in players) {
    final seen = <String>{};
    for (final s in submissions[p.id] ?? const <Submission>[]) {
      if (!seen.add(s.word)) continue;
      finders.putIfAbsent(s.word, () => []).add((p.id, s.atMs));
      if (!firstTime.containsKey(s.word) || s.atMs < firstTime[s.word]!) {
        firstTime[s.word] = s.atMs;
        firstPath[s.word] = s.path;
      }
    }
  }

  final entries = finders.entries.map((e) {
    final ordered = List.of(e.value)..sort((a, b) => a.$2.compareTo(b.$2));
    return WordEntry(
      word: e.key,
      path: firstPath[e.key]!,
      finders: ordered.map((f) => f.$1).toList(),
    );
  }).toList();

  final results = players.map((p) {
    final mine = entries.where((e) => e.finders.contains(p.id)).toList();
    final words = mine.map((e) => e.word).toList()..sort();
    final unique = mine.where((e) => e.isUnique).map((e) => e.word).toList()..sort();
    final score = mine.fold<int>(0, (s, e) => s + e.pointsEach);
    return PlayerResult(player: p, words: words, score: score, uniqueWords: unique);
  }).toList()
    ..sort((a, b) {
      final byCount = b.wordCount.compareTo(a.wordCount);
      return byCount != 0 ? byCount : b.score.compareTo(a.score);
    });

  final replay = orderReplay(entries, players.map((p) => p.id).toList());
  final highlights = computeHighlights(
    players: results,
    entries: entries,
    totalPossible: solved.length,
  );

  return RoundResults(
    settings: settings,
    board: board,
    players: results,
    replay: replay,
    highlights: highlights,
    longest: pickLongestWord(solved, entries),
    totalPossibleWords: solved.length,
  );
}

/// Picks the longest word on the board to show at the end. Prefers one that
/// nobody found; if all were found, reports who found them.
LongestWordInfo? pickLongestWord(
    Map<String, List<int>> solved, List<WordEntry> entries) {
  final longest = longestWords(solved);
  if (longest.isEmpty) return null;
  final byWord = {for (final e in entries) e.word: e};
  final unfound = longest.where((w) => !byWord.containsKey(w)).toList();
  if (unfound.isNotEmpty) {
    final w = unfound.first;
    return LongestWordInfo(
      word: w,
      path: solved[w]!,
      allLongest: longest,
      foundBy: const [],
      allFound: false,
    );
  }
  final w = longest.first;
  final who = <String>{};
  for (final l in longest) {
    who.addAll(byWord[l]!.finders);
  }
  return LongestWordInfo(
    word: w,
    path: byWord[w]!.path,
    allLongest: longest,
    foundBy: who.toList(),
    allFound: true,
  );
}
