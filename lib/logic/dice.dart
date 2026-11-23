/// Boggle-style dice and board generation.
library;

import 'dart:math';

import 'board.dart';
import 'dictionary.dart';
import 'solver.dart';

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

/// Minimum number of findable words we want on a board of each size.
int targetWordCount(int size) => switch (size) {
      4 => 35,
      5 => 80,
      _ => 140,
    };

/// Rolls boards until one has a decent number of words (or attempts run out,
/// in which case the richest board seen is returned).
Board generateGoodBoard({
  required int size,
  required int minWordLength,
  required Dictionary dictionary,
  Random? random,
  int attempts = 40,
}) {
  final rng = random ?? Random();
  Board? best;
  var bestCount = -1;
  final target = targetWordCount(size);
  for (var i = 0; i < attempts; i++) {
    final board = rollBoard(size, rng);
    final count = solveBoard(board, dictionary, minWordLength: minWordLength).length;
    if (count > bestCount) {
      best = board;
      bestCount = count;
    }
    if (count >= target) break;
  }
  return best!;
}
