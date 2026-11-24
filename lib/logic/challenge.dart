/// "Challenge a friend" links: the exact board, the options, and how everyone
/// did, packed into a short URL. Nothing is stored on a server.
///
/// The board's letters are stored directly (not a random seed), so a link
/// keeps working even if the board generator changes. Each player's words are
/// stored as a bitset over the board's sorted solution list, which the
/// receiving app recomputes from the same dictionary. If that list doesn't
/// match (a different dictionary version), the words are dropped and only the
/// scores are shown.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'board.dart';
import 'dictionary.dart';
import 'models.dart';
import 'room_code.dart' show webOrigin;
import 'solver.dart';

const int _formatVersion = 1;
const int _flagDeflated = 1;

/// Links longer than this drop the word lists and keep only the scores.
const int maxChallengeUrlLength = 1800;

class ChallengePlayer {
  const ChallengePlayer({
    required this.name,
    required this.avatar,
    required this.score,
    required this.wordCount,
    this.words,
  });

  final String name;
  final int avatar;
  final int score;
  final int wordCount;

  /// The words they found, or null when the link only carries scores.
  final List<String>? words;
}

class Challenge {
  const Challenge({
    required this.settings,
    required this.board,
    required this.players,
    this.fromIndex = 0,
  });

  final GameSettings settings;
  final Board board;
  final List<ChallengePlayer> players;

  /// Which player sent the link.
  final int fromIndex;

  ChallengePlayer? get from => fromIndex < players.length ? players[fromIndex] : null;

  /// Builds a challenge from finished round results. [fromId] is the player
  /// sharing the link.
  factory Challenge.fromResults(RoundResults r, {required String fromId}) {
    final ps = [
      for (final p in r.players)
        ChallengePlayer(
          name: p.player.name,
          avatar: p.player.avatar,
          score: p.score,
          wordCount: p.wordCount,
          words: p.words,
        ),
    ];
    final from = r.players.indexWhere((p) => p.player.id == fromId);
    return Challenge(settings: r.settings, board: r.board, players: ps, fromIndex: from < 0 ? 0 : from);
  }
}

/// Sorted list of every word on the board, used to number the words.
List<String> _solution(Board b, Dictionary d, int minLen) =>
    solveBoard(b, d, minWordLength: minLen).keys.toList()..sort();

int _hash16(List<String> words) {
  var h = 0x811c9dc5;
  for (final w in words) {
    for (final c in w.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    h = ((h ^ 10) * 0x01000193) & 0xffffffff;
  }
  return (h ^ (h >> 16)) & 0xffff;
}

/// The `d=` payload for [c].
String encodeChallenge(Challenge c, Dictionary dictionary, {bool includeWords = true}) {
  final solution = _solution(c.board, dictionary, c.settings.minWordLength);
  final index = {for (var i = 0; i < solution.length; i++) solution[i]: i};
  final out = BytesBuilder();
  void u8(int v) => out.addByte(v.clamp(0, 255));
  void u16(int v) {
    final x = v.clamp(0, 65535);
    out
      ..addByte(x >> 8)
      ..addByte(x & 255);
  }

  u8(c.settings.gridSize);
  u8(c.settings.minWordLength);
  u8(c.settings.durationSeconds ~/ 10);
  for (final t in c.board.tiles) {
    u8(t.codeUnitAt(0) - 65); // QU is stored as Q
  }
  u16(solution.length);
  u16(_hash16(solution));
  u8(c.fromIndex);
  u8(c.players.length);
  for (final p in c.players) {
    var name = utf8.encode(p.name);
    if (name.length > 48) name = name.sublist(0, 48);
    u8(p.avatar);
    u8(name.length);
    out.add(name);
    u16(p.score);
    u16(p.wordCount);
    final words = includeWords ? p.words : null;
    u8(words == null ? 0 : 1);
    if (words != null) {
      final bits = Uint8List((solution.length + 7) ~/ 8);
      for (final w in words) {
        final i = index[w];
        if (i != null) bits[i >> 3] |= 1 << (i & 7);
      }
      out.add(bits);
    }
  }
  final body = out.toBytes();
  final packed = Deflate(body).getBytes();
  final useDeflate = packed.length < body.length;
  final bytes = [_formatVersion, useDeflate ? _flagDeflated : 0, ...(useDeflate ? packed : body)];
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Full share link for [c]. Drops word lists if the link would be too long.
String challengeUrl(Challenge c, Dictionary dictionary) {
  var url = '$webOrigin/challenge?d=${encodeChallenge(c, dictionary)}';
  if (url.length > maxChallengeUrlLength) {
    url = '$webOrigin/challenge?d=${encodeChallenge(c, dictionary, includeWords: false)}';
  }
  return url;
}

/// Reads a `d=` payload. Throws [FormatException] if it isn't valid.
Challenge decodeChallenge(String data, Dictionary dictionary) {
  try {
    var s = data.trim();
    while (s.length % 4 != 0) {
      s += '=';
    }
    final raw = base64Url.decode(s);
    if (raw.length < 3 || raw[0] != _formatVersion) {
      throw const FormatException('Unknown challenge format');
    }
    final body = (raw[1] & _flagDeflated) != 0 ? Inflate(raw.sublist(2)).getBytes() : raw.sublist(2);
    var pos = 0;
    int u8() => body[pos++];
    int u16() => (u8() << 8) | u8();

    final size = u8();
    final minLen = u8();
    final duration = u8() * 10;
    if (!GameSettings.gridSizes.contains(size)) throw const FormatException('Bad grid size');
    final tiles = [
      for (var i = 0; i < size * size; i++)
        () {
          final ch = String.fromCharCode(65 + u8());
          return ch == 'Q' ? 'QU' : ch;
        }(),
    ];
    final board = Board(size, tiles);
    final settings = GameSettings(gridSize: size, minWordLength: minLen.clamp(3, 5), durationSeconds: duration.clamp(10, 600));
    final count = u16();
    final hash = u16();
    final solution = _solution(board, dictionary, settings.minWordLength);
    final wordsOk = solution.length == count && _hash16(solution) == hash;
    final fromIndex = u8();
    final n = u8();
    final players = <ChallengePlayer>[];
    for (var i = 0; i < n; i++) {
      final avatar = u8();
      final nameLen = u8();
      final name = utf8.decode(body.sublist(pos, pos + nameLen), allowMalformed: true);
      pos += nameLen;
      final score = u16();
      final wordCount = u16();
      final hasWords = u8() == 1;
      List<String>? words;
      if (hasWords) {
        final len = (count + 7) ~/ 8;
        final bits = body.sublist(pos, pos + len);
        pos += len;
        if (wordsOk) {
          words = [
            for (var j = 0; j < count; j++)
              if ((bits[j >> 3] >> (j & 7)) & 1 == 1) solution[j],
          ];
        }
      }
      players.add(ChallengePlayer(name: name, avatar: avatar, score: score, wordCount: wordCount, words: words));
    }
    return Challenge(settings: settings, board: board, players: players, fromIndex: fromIndex);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Broken challenge link: $e');
  }
}

/// The `d=` value from a challenge link, if [uri] is one.
String? challengeDataFromUri(Uri uri) {
  if (!uri.path.contains('challenge')) return null;
  final d = uri.queryParameters['d'];
  return d == null || d.isEmpty ? null : d;
}
