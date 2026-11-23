/// Decides the order words are revealed on the scoring screen.
library;

import 'models.dart';

/// Shared words first (most finders first), then unique words ordered to keep
/// the lead changing for as long as possible.
///
/// Unique words are handed out greedily: the player who is currently behind
/// reveals their next word, choosing the smallest word that takes the lead
/// (or their smallest word if none does). Each player's single biggest word
/// is held back until it is the only one they have left.
List<WordEntry> orderReplay(List<WordEntry> entries, List<String> playerIds) {
  final shared = entries.where((e) => !e.isUnique).toList()
    ..sort((a, b) {
      final byFinders = b.finders.length.compareTo(a.finders.length);
      if (byFinders != 0) return byFinders;
      final byPoints = a.basePoints.compareTo(b.basePoints);
      if (byPoints != 0) return byPoints;
      return a.word.compareTo(b.word);
    });

  final scores = {for (final id in playerIds) id: 0};
  for (final e in shared) {
    for (final f in e.finders) {
      scores[f] = (scores[f] ?? 0) + e.pointsEach;
    }
  }

  final pending = <String, List<WordEntry>>{};
  for (final e in entries.where((e) => e.isUnique)) {
    pending.putIfAbsent(e.finders.first, () => []).add(e);
    scores.putIfAbsent(e.finders.first, () => 0);
  }
  for (final list in pending.values) {
    list.sort((a, b) {
      final byPoints = a.pointsEach.compareTo(b.pointsEach);
      return byPoints != 0 ? byPoints : a.word.compareTo(b.word);
    });
  }

  int remainingPoints(String id) =>
      pending[id]!.fold(0, (sum, e) => sum + e.pointsEach);

  final uniqueOrder = <WordEntry>[];
  while (pending.values.any((l) => l.isNotEmpty)) {
    final candidates = pending.keys.where((id) => pending[id]!.isNotEmpty).toList()
      ..sort((a, b) {
        final byScore = scores[a]!.compareTo(scores[b]!);
        if (byScore != 0) return byScore;
        final byRemaining = remainingPoints(b).compareTo(remainingPoints(a));
        return byRemaining != 0 ? byRemaining : a.compareTo(b);
      });
    final id = candidates.first;
    final list = pending[id]!;
    var bestOther = 0;
    var hasOther = false;
    scores.forEach((other, s) {
      if (other == id) return;
      if (!hasOther || s > bestOther) bestOther = s;
      hasOther = true;
    });
    final need = bestOther - scores[id]!;

    // Hold the biggest word back while there is anything else to play.
    final playable = list.length > 1 ? list.sublist(0, list.length - 1) : list;
    var pick = playable.first;
    for (final e in playable) {
      if (e.pointsEach > need) {
        pick = e;
        break;
      }
    }
    list.remove(pick);
    scores[id] = scores[id]! + pick.pointsEach;
    uniqueOrder.add(pick);
  }

  return [...shared, ...uniqueOrder];
}

/// How long one replay step lasts on screen.
Duration replayStepDuration(WordEntry e) {
  const base = Duration(milliseconds: 750);
  if (e.isUnique && e.word.length >= 5) {
    return base + const Duration(milliseconds: 500);
  }
  return base;
}

/// Counts how many times the outright leader changes during a replay.
int countLeadChanges(List<WordEntry> replay, List<String> playerIds) {
  final scores = {for (final id in playerIds) id: 0};
  String? leader;
  var changes = 0;
  for (final e in replay) {
    for (final f in e.finders) {
      scores[f] = (scores[f] ?? 0) + e.pointsEach;
    }
    final top = scores.values.reduce((a, b) => a > b ? a : b);
    final leaders = scores.keys.where((k) => scores[k] == top).toList();
    if (leaders.length == 1 && leaders.first != leader) {
      if (leader != null) changes++;
      leader = leaders.first;
    }
  }
  return changes;
}
