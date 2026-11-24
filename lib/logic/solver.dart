/// Finds every word on a board.
library;

import 'board.dart';
import 'dictionary.dart';

/// Returns every dictionary word on [board] with at least [minWordLength]
/// letters, mapped to one tile path that spells it.
Map<String, List<int>> solveBoard(Board board, Dictionary dictionary,
    {int minWordLength = 3}) {
  final found = <String, List<int>>{};
  final used = List<bool>.filled(board.length, false);
  final path = <int>[];
  final faces = board.tiles.map((t) => t.toLowerCase()).toList();

  void dfs(int tile, int node, String sofar) {
    final next = dictionary.walk(node, faces[tile]);
    if (next == -1) return;
    final word = sofar + faces[tile];
    used[tile] = true;
    path.add(tile);
    if (dictionary.isWord(next) && word.length >= minWordLength) {
      found.putIfAbsent(word, () => List.of(path));
    }
    for (final n in board.neighbors(tile)) {
      if (!used[n]) dfs(n, next, word);
    }
    path.removeLast();
    used[tile] = false;
  }

  for (var i = 0; i < board.length; i++) {
    dfs(i, Dictionary.root, '');
  }
  return found;
}

/// The longest words in a solved word map (all of them if there is a tie).
List<String> longestWords(Map<String, List<int>> solved) {
  if (solved.isEmpty) return const [];
  final maxLen = solved.keys.fold<int>(0, (m, w) => w.length > m ? w.length : m);
  return solved.keys.where((w) => w.length == maxLen).toList()..sort();
}

/// Every word on a board plus which tiles are part of at least one word.
class BoardAnalysis {
  const BoardAnalysis(this.words, this.covered);

  /// Word -> one path that spells it (same as [solveBoard]).
  final Map<String, List<int>> words;

  /// `covered[i]` is true when tile `i` is used by any path of any valid word.
  final List<bool> covered;

  int get wordCount => words.length;

  /// Tiles that are not part of any word ("dead" letters).
  List<int> get deadTiles => [
        for (var i = 0; i < covered.length; i++)
          if (!covered[i]) i
      ];
}

/// Like [solveBoard], but also records which tiles appear in any valid word.
BoardAnalysis analyzeBoard(Board board, Dictionary dictionary, {int minWordLength = 3}) {
  final found = <String, List<int>>{};
  final covered = List<bool>.filled(board.length, false);
  final used = List<bool>.filled(board.length, false);
  final path = <int>[];
  final faces = board.tiles.map((t) => t.toLowerCase()).toList();

  void dfs(int tile, int node, int len) {
    final next = dictionary.walk(node, faces[tile]);
    if (next == -1) return;
    final l = len + faces[tile].length;
    used[tile] = true;
    path.add(tile);
    if (l >= minWordLength && dictionary.isWord(next)) {
      for (final t in path) {
        covered[t] = true;
      }
      final word = board.wordForPath(path);
      found.putIfAbsent(word, () => List.of(path));
    }
    for (final n in board.neighbors(tile)) {
      if (!used[n]) dfs(n, next, l);
    }
    path.removeLast();
    used[tile] = false;
  }

  for (var i = 0; i < board.length; i++) {
    dfs(i, Dictionary.root, 0);
  }
  return BoardAnalysis(found, covered);
}
