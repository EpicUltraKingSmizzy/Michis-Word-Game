/// Validates paths traced on the grid and classifies submissions.
library;

import 'board.dart';
import 'dictionary.dart';

/// True if [path] stays on the board, never reuses a tile, and every step
/// moves to one of the 8 neighbouring tiles.
bool isValidPath(Board board, List<int> path) {
  if (path.isEmpty) return false;
  final seen = <int>{};
  for (var i = 0; i < path.length; i++) {
    final t = path[i];
    if (t < 0 || t >= board.length) return false;
    if (!seen.add(t)) return false;
    if (i > 0 && !board.isAdjacent(path[i - 1], t)) return false;
  }
  return true;
}

/// Whether a dragged tile can be appended to the current path.
bool canExtendPath(Board board, List<int> path, int tile) {
  if (tile < 0 || tile >= board.length) return false;
  if (path.contains(tile)) return false;
  return path.isEmpty || board.isAdjacent(path.last, tile);
}

enum SubmissionResult { added, tooShort, alreadyFound, notAWord, invalidPath }

/// Classifies a submitted path from one player's point of view.
SubmissionResult checkSubmission({
  required Board board,
  required List<int> path,
  required Dictionary dictionary,
  required int minWordLength,
  required Set<String> alreadyFound,
}) {
  if (!isValidPath(board, path)) return SubmissionResult.invalidPath;
  final word = board.wordForPath(path);
  if (word.length < minWordLength) return SubmissionResult.tooShort;
  if (alreadyFound.contains(word)) return SubmissionResult.alreadyFound;
  if (!dictionary.contains(word)) return SubmissionResult.notAWord;
  return SubmissionResult.added;
}
