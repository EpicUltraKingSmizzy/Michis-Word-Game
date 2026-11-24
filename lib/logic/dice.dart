/// Boggle-style dice and board generation.
library;

import 'dart:math';

import 'board.dart';
import 'dictionary.dart';
import 'grid_rules.dart';
import 'solver.dart';

export 'grid_rules.dart';

/// Faces of a die. `Q` always becomes the `QU` tile.
typedef Die = String;

/// Classic 16-die set (4x4).
const List<Die> classicDice = [
  'AAEEGN', 'ABBJOO', 'ACHOPS', 'AFFKPS', 'AOOTTW', 'CIMOTU', 'DEILRX', 'DELRVY',
  'DISTTY', 'EEGHNW', 'EEINSU', 'EHRTVW', 'EIOSST', 'ELRTTY', 'HIMNUQ', 'HLNNRZ',
];

/// Big Boggle-style 25-die set (5x5).
const List<Die> bigDice = [
  'AAAFRS', 'AAEEEE', 'AAFIRS', 'ADENNN', 'AEEEEM', 'AEEGMU', 'AEGMNN', 'AFIRSY',
  'BJKQXZ', 'CCENST', 'CEIILT', 'CEILPT', 'CEIPST', 'DDHNOT', 'DHHLOR', 'DHLNOR',
  'DHLNOR', 'EIIITT', 'EMOTTT', 'ENSSSU', 'FIPRSY', 'GORRVW', 'IPRRRY', 'NOOTUW',
  'OOOTTU',
];

/// Super Big Boggle-style 36-die set (6x6). The original multi-letter and
/// blank faces are replaced with single letters (Q still becomes Qu).
const List<Die> superBigDice = [
  'AAAFRS', 'AAEEEE', 'AAEEOO', 'AAFIRS', 'ABDEIO', 'ADENNN', 'AEEEEM', 'AEEGMU',
  'AEGMNN', 'AEILMN', 'AEINOU', 'AFIRSY', 'AEHIQR', 'BBJKXZ', 'CCENST', 'CDDLNN',
  'CEIITT', 'CEIPST', 'CFGNUY', 'DDHNOT', 'DHHLOR', 'DHHNOW', 'DHLNOR', 'EHILRS',
  'EIILST', 'EILPST', 'EIOAEU', 'EMTTTO', 'ENSSSU', 'GORRVW', 'HIRSTV', 'HOPRST',
  'IPRRRY', 'NOOTUW', 'OOOTTU', 'AEIRST',
];

List<Die> diceForSize(int size) => switch (size) {
      4 => classicDice,
      5 => bigDice,
      6 => superBigDice,
      _ => throw ArgumentError('Unsupported grid size $size'),
    };

/// Shake the dice once.
Board rollBoard(int size, Random random) {
  final dice = List<Die>.of(diceForSize(size))..shuffle(random);
  final tiles = dice.map((die) {
    final face = die[random.nextInt(die.length)];
    return face == 'Q' ? 'QU' : face;
  }).toList();
  return Board(size, tiles);
}

/// True when every tile is part of some word and there are enough words.
bool isGoodBoard(BoardAnalysis a, int size, int minWordLength) =>
    (!rejectDeadLetters || a.deadTiles.isEmpty) && a.wordCount >= minWordsFor(size, minWordLength);

/// Rolls boards until one passes [isGoodBoard]: no "dead" letters that can't
/// be used in any word, and at least [minWordsFor] words. After [attempts]
/// rolls it settles for the best board seen (fewest dead tiles, then most
/// words), so dealing a board never stalls.
Board generateGoodBoard({
  required int size,
  required int minWordLength,
  required Dictionary dictionary,
  Random? random,
  int attempts = maxBoardRolls,
  void Function(int tries)? onDone,
}) {
  final rng = random ?? Random();
  Board? best;
  var bestDead = 1 << 30, bestCount = -1;
  for (var i = 0; i < attempts; i++) {
    final board = rollBoard(size, rng);
    final a = analyzeBoard(board, dictionary, minWordLength: minWordLength);
    final dead = a.deadTiles.length;
    if (isGoodBoard(a, size, minWordLength)) {
      onDone?.call(i + 1);
      return board;
    }
    final better = dead < bestDead || (dead == bestDead && a.wordCount > bestCount);
    if (better) {
      best = board;
      bestDead = dead;
      bestCount = a.wordCount;
    }
  }
  onDone?.call(attempts);
  return best!;
}
