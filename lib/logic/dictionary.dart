/// Compact trie for the word list.
library;

/// A word list stored as a first-child / next-sibling trie in flat arrays.
class Dictionary {
  Dictionary._(this._firstChild, this._nextSibling, this._char, this._terminal,
      this.wordCount);

  /// Builds a dictionary from [words]. Words are lowercased; anything that is
  /// not purely a-z, shorter than [minLength], or in [blocked] is skipped.
  factory Dictionary.fromWords(Iterable<String> words,
      {Set<String> blocked = const {}, int minLength = 3}) {
    final clean = <String>{};
    final az = RegExp(r'^[a-z]+$');
    for (final raw in words) {
      final w = raw.trim().toLowerCase();
      if (w.length < minLength || !az.hasMatch(w) || blocked.contains(w)) {
        continue;
      }
      clean.add(w);
    }
    final sorted = clean.toList()..sort();

    final firstChild = <int>[-1];
    final nextSibling = <int>[-1];
    final lastChild = <int>[-1];
    final chars = <int>[0];
    final terminal = <bool>[false];

    for (final w in sorted) {
      var node = 0;
      for (final cu in w.codeUnits) {
        // Words are sorted, so if the child exists it is the last one added.
        final last = lastChild[node];
        if (last != -1 && chars[last] == cu) {
          node = last;
          continue;
        }
        final n = chars.length;
        chars.add(cu);
        firstChild.add(-1);
        nextSibling.add(-1);
        lastChild.add(-1);
        terminal.add(false);
        if (last == -1) {
          firstChild[node] = n;
        } else {
          nextSibling[last] = n;
        }
        lastChild[node] = n;
        node = n;
      }
      terminal[node] = true;
    }
    return Dictionary._(firstChild, nextSibling, chars, terminal, sorted.length);
  }

  /// Parses newline separated text.
  static List<String> parseLines(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();

  final List<int> _firstChild;
  final List<int> _nextSibling;
  final List<int> _char;
  final List<bool> _terminal;
  final int wordCount;

  static const int root = 0;

  /// Child of [node] for the character [codeUnit], or -1.
  int child(int node, int codeUnit) {
    var c = _firstChild[node];
    while (c != -1) {
      if (_char[c] == codeUnit) return c;
      c = _nextSibling[c];
    }
    return -1;
  }

  bool isWord(int node) => _terminal[node];

  /// Follows [s] from [node]; returns -1 if it falls off the trie.
  int walk(int node, String s) {
    var n = node;
    for (final cu in s.codeUnits) {
      n = child(n, cu);
      if (n == -1) return -1;
    }
    return n;
  }

  bool contains(String word) {
    final n = walk(root, word.toLowerCase());
    return n != -1 && _terminal[n];
  }

  bool hasPrefix(String prefix) => walk(root, prefix.toLowerCase()) != -1;
}
