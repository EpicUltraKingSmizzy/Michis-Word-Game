/// Round highlights shown after scoring.
library;

import 'models.dart';

/// Computes the highlight cards for a round. Personal bests are tracked on
/// each device separately (see `ProfileStore`).
List<Highlight> computeHighlights({
  required List<PlayerResult> players,
  required List<WordEntry> entries,
  required int totalPossible,
  bool longestOnly = false,
}) {
  final out = <Highlight>[];
  if (players.isEmpty) return out;

  String names(List<PlayerResult> ps) {
    final n = ps.map((p) => p.player.name).toList();
    if (n.length == 1) return n.first;
    return '${n.sublist(0, n.length - 1).join(', ')} & ${n.last}';
  }

  void topBy(String title, int Function(PlayerResult) metric, String Function(int) detail) {
    final best = players.map(metric).reduce((a, b) => a > b ? a : b);
    if (best <= 0) return;
    final winners = players.where((p) => metric(p) == best).toList();
    out.add(Highlight(
      kind: HighlightKind.player,
      title: title,
      detail: '${names(winners)} ${detail(best)}',
      playerIds: winners.map((p) => p.player.id).toList(),
    ));
  }

  int countLen(PlayerResult p, bool Function(int) test) =>
      p.words.where((w) => test(w.length)).length;

  topBy('Word Machine', (p) => p.wordCount, (n) => 'found the most words ($n)');
  topBy('Lone Wolf', (p) => p.uniqueWords.length,
      (n) => 'found the most unique words ($n)');
  topBy('Triple Threat', (p) => countLen(p, (l) => l == 3),
      (n) => 'found the most 3-letter words ($n)');
  topBy('Four Square', (p) => countLen(p, (l) => l == 4),
      (n) => 'found the most 4-letter words ($n)');
  topBy('Big Word Energy', (p) => countLen(p, (l) => l >= 5),
      (n) => 'found the most words with 5+ letters ($n)');

  // Longest word of the round.
  if (entries.isNotEmpty) {
    final maxLen = entries.map((e) => e.word.length).reduce((a, b) => a > b ? a : b);
    final longest = entries.where((e) => e.word.length == maxLen).toList()
      ..sort((a, b) => a.word.compareTo(b.word));
    final ids = <String>{for (final e in longest) ...e.finders};
    final whoNames = players.where((p) => ids.contains(p.player.id)).toList();
    out.add(Highlight(
      kind: HighlightKind.player,
      title: 'Longest Word',
      detail:
          '${longest.map((e) => e.word.toUpperCase()).join(', ')} ($maxLen letters) by ${names(whoNames)}',
      playerIds: ids.toList(),
    ));

    // Highest-scoring single word (not in "Longest word only" rounds, where
    // only one word per player scores and the replay already shows it).
    if (!longestOnly) {
      final bestPts = entries.map((e) => e.pointsEach).reduce((a, b) => a > b ? a : b);
      final best = entries.where((e) => e.pointsEach == bestPts).toList()
        ..sort((a, b) => a.word.compareTo(b.word));
      final top = best.first;
      final finder = players.firstWhere((p) => p.player.id == top.finders.first);
      out.add(Highlight(
        kind: HighlightKind.player,
        title: 'Jackpot Word',
        detail: '${top.word.toUpperCase()} scored +$bestPts for ${finder.player.name}',
        playerIds: top.finders,
      ));
    }
  }

  // Group milestones.
  if (players.every((p) => p.wordCount >= 10)) {
    out.add(const Highlight(
      kind: HighlightKind.group,
      title: 'PICKING UP STEAM',
      detail: 'Every player found at least 10 words this round',
    ));
  }
  if (totalPossible > 0 && entries.length * 2 > totalPossible) {
    final pct = (entries.length * 100 / totalPossible).round();
    out.add(Highlight(
      kind: HighlightKind.group,
      title: 'BOARD BUSTERS',
      detail: 'Together you found $pct% of the $totalPossible words on the board',
    ));
  }
  if (players.length >= 2) {
    final scores = players.map((p) => p.score).toList()..sort((a, b) => b - a);
    if (scores[0] - scores[1] <= 2 && scores[0] > 0) {
      out.add(Highlight(
        kind: HighlightKind.group,
        title: 'PHOTO FINISH',
        detail: scores[0] == scores[1]
            ? 'A dead heat at the top!'
            : 'First and second were only ${scores[0] - scores[1]} point${scores[0] - scores[1] == 1 ? '' : 's'} apart',
      ));
    }
  }
  return out;
}
