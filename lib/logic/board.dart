/// The letter grid and pure helpers for working with tile paths.
library;

class Board {
  Board(this.size, List<String> tiles)
      : tiles = List.unmodifiable(tiles.map((t) => t.toUpperCase())),
        assert(tiles.length == size * size) {
    _neighbors = List.generate(tiles.length, _computeNeighbors);
  }

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        json['size'] as int,
        (json['tiles'] as List).cast<String>(),
      );

  /// Number of rows (and columns).
  final int size;

  /// Tile faces in row-major order. A `QU` tile is stored as the two letters.
  final List<String> tiles;

  late final List<List<int>> _neighbors;

  int get length => tiles.length;
  int row(int index) => index ~/ size;
  int col(int index) => index % size;

  List<int> neighbors(int index) => _neighbors[index];

  List<int> _computeNeighbors(int index) {
    final r = row(index), c = col(index);
    final out = <int>[];
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
        out.add(nr * size + nc);
      }
    }
    return out;
  }

  bool isAdjacent(int a, int b) {
    if (a == b) return false;
    return (row(a) - row(b)).abs() <= 1 && (col(a) - col(b)).abs() <= 1;
  }

  /// Display label for a tile ("Qu" instead of "QU").
  String label(int index) => tiles[index] == 'QU' ? 'Qu' : tiles[index];

  /// Lowercase word spelled by a path.
  String wordForPath(List<int> path) =>
      path.map((i) => tiles[i]).join().toLowerCase();

  Map<String, dynamic> toJson() => {'size': size, 'tiles': tiles};

  @override
  String toString() {
    final b = StringBuffer();
    for (var r = 0; r < size; r++) {
      b.writeln(List.generate(size, (c) => label(r * size + c).padRight(2)).join(' '));
    }
    return b.toString();
  }
}
