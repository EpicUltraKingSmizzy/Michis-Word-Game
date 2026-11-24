/// Board quality rules. Edit the numbers here to change which boards get dealt.
library;

/// Minimum number of findable words a board must have to be dealt, by grid
/// size, then shortest-word setting. Chosen from 2,000 random boards per
/// setting (see tool/grid_stats.dart and grid_stats.md). Set a value to 0 to
/// turn the word-count check off for that setting.
const Map<int, Map<int, int>> minWordsTable = {
  4: {3: 40, 4: 20, 5: 8},
  5: {3: 130, 4: 80, 5: 30},
  6: {3: 250, 4: 175, 5: 75},
};

/// Reroll boards that have a letter which isn't part of any valid word.
const bool rejectDeadLetters = true;

/// Most boards to roll before settling for the best one seen.
const int maxBoardRolls = 300;

int minWordsFor(int size, int minWordLength) => minWordsTable[size]?[minWordLength] ?? 0;
