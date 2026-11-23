/// Plain data shared between host, players, and the network protocol.
library;

import 'board.dart';

class GameSettings {
  const GameSettings({
    this.gridSize = 4,
    this.minWordLength = 3,
    this.durationSeconds = 120,
  });

  factory GameSettings.fromJson(Map<String, dynamic> j) => GameSettings(
        gridSize: j['gridSize'] as int? ?? 4,
        minWordLength: j['minWordLength'] as int? ?? 3,
        durationSeconds: j['durationSeconds'] as int? ?? 120,
      );

  static const gridSizes = [4, 5, 6];
  static const minWordLengths = [3, 4, 5];
  static const minDuration = 60;
  static const maxDuration = 180;
  static const durationStep = 30;

  final int gridSize;
  final int minWordLength;
  final int durationSeconds;

  String get gridLabel => '${gridSize}x$gridSize';
  String get gridName => switch (gridSize) { 4 => 'Classic', 5 => 'Big', _ => 'Super Big' };

  String get durationLabel {
    final m = durationSeconds ~/ 60, s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  GameSettings copyWith({int? gridSize, int? minWordLength, int? durationSeconds}) =>
      GameSettings(
        gridSize: gridSize ?? this.gridSize,
        minWordLength: minWordLength ?? this.minWordLength,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );

  Map<String, dynamic> toJson() => {
        'gridSize': gridSize,
        'minWordLength': minWordLength,
        'durationSeconds': durationSeconds,
      };

  @override
  bool operator ==(Object other) =>
      other is GameSettings &&
      other.gridSize == gridSize &&
      other.minWordLength == minWordLength &&
      other.durationSeconds == durationSeconds;

  @override
  int get hashCode => Object.hash(gridSize, minWordLength, durationSeconds);
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.avatar,
    this.isHost = false,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> j) => PlayerInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Player',
        avatar: j['avatar'] as int? ?? 0,
        isHost: j['isHost'] as bool? ?? false,
      );

  final String id;
  final String name;
  final int avatar;
  final bool isHost;

  PlayerInfo copyWith({String? name, int? avatar}) => PlayerInfo(
      id: id, name: name ?? this.name, avatar: avatar ?? this.avatar, isHost: isHost);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'avatar': avatar, 'isHost': isHost};
}

/// One word a player locked in during the round.
class Submission {
  const Submission({required this.word, required this.path, required this.atMs});

  final String word;
  final List<int> path;

  /// Milliseconds after the round started (as seen by the host).
  final int atMs;
}

/// One word in the scoring replay.
class WordEntry {
  const WordEntry({
    required this.word,
    required this.path,
    required this.finders,
  });

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        word: j['w'] as String,
        path: (j['p'] as List).cast<int>(),
        finders: (j['f'] as List).cast<String>(),
      );

  final String word;

  /// Path traced by whoever found the word first.
  final List<int> path;

  /// Player ids, earliest finder first.
  final List<String> finders;

  bool get isUnique => finders.length == 1;
  int get basePoints => wordPoints(word);

  /// Points each finder earns (doubled when only one player found it).
  int get pointsEach => isUnique ? basePoints * 2 : basePoints;

  Map<String, dynamic> toJson() => {'w': word, 'p': path, 'f': finders};
}

/// Letters minus two (a 3-letter word is worth 1 point).
int wordPoints(String word) => word.length < 3 ? 0 : word.length - 2;

class PlayerResult {
  const PlayerResult({
    required this.player,
    required this.words,
    required this.score,
    required this.uniqueWords,
  });

  factory PlayerResult.fromJson(Map<String, dynamic> j) => PlayerResult(
        player: PlayerInfo.fromJson(j['player'] as Map<String, dynamic>),
        words: (j['words'] as List).cast<String>(),
        score: j['score'] as int,
        uniqueWords: (j['unique'] as List).cast<String>(),
      );

  final PlayerInfo player;
  final List<String> words;
  final int score;
  final List<String> uniqueWords;

  int get wordCount => words.length;

  Map<String, dynamic> toJson() =>
      {'player': player.toJson(), 'words': words, 'score': score, 'unique': uniqueWords};
}

enum HighlightKind { player, group }

class Highlight {
  const Highlight({
    required this.kind,
    required this.title,
    required this.detail,
    this.playerIds = const [],
  });

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        kind: HighlightKind.values.byName(j['kind'] as String),
        title: j['title'] as String,
        detail: j['detail'] as String,
        playerIds: (j['players'] as List? ?? const []).cast<String>(),
      );

  final HighlightKind kind;
  final String title;
  final String detail;
  final List<String> playerIds;

  Map<String, dynamic> toJson() =>
      {'kind': kind.name, 'title': title, 'detail': detail, 'players': playerIds};
}

class LongestWordInfo {
  const LongestWordInfo({
    required this.word,
    required this.path,
    required this.allLongest,
    required this.foundBy,
    required this.allFound,
  });

  factory LongestWordInfo.fromJson(Map<String, dynamic> j) => LongestWordInfo(
        word: j['word'] as String,
        path: (j['path'] as List).cast<int>(),
        allLongest: (j['all'] as List).cast<String>(),
        foundBy: (j['foundBy'] as List).cast<String>(),
        allFound: j['allFound'] as bool,
      );

  /// The word to show.
  final String word;
  final List<int> path;

  /// Every word tied for longest.
  final List<String> allLongest;

  /// Players who found any of the longest words (only used when [allFound]).
  final List<String> foundBy;

  /// True when every longest word was found by someone.
  final bool allFound;

  Map<String, dynamic> toJson() => {
        'word': word,
        'path': path,
        'all': allLongest,
        'foundBy': foundBy,
        'allFound': allFound,
      };
}

class RoundResults {
  const RoundResults({
    required this.settings,
    required this.board,
    required this.players,
    required this.replay,
    required this.highlights,
    required this.longest,
    required this.totalPossibleWords,
  });

  factory RoundResults.fromJson(Map<String, dynamic> j) => RoundResults(
        settings: GameSettings.fromJson(j['settings'] as Map<String, dynamic>),
        board: Board.fromJson(j['board'] as Map<String, dynamic>),
        players: (j['players'] as List)
            .map((e) => PlayerResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        replay: (j['replay'] as List)
            .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        highlights: (j['highlights'] as List)
            .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
            .toList(),
        longest: j['longest'] == null
            ? null
            : LongestWordInfo.fromJson(j['longest'] as Map<String, dynamic>),
        totalPossibleWords: j['total'] as int? ?? 0,
      );

  final GameSettings settings;
  final Board board;

  /// Sorted by word count (most first), then score.
  final List<PlayerResult> players;

  /// Words in the order they are scored on screen.
  final List<WordEntry> replay;
  final List<Highlight> highlights;
  final LongestWordInfo? longest;
  final int totalPossibleWords;

  PlayerResult? playerById(String id) {
    for (final p in players) {
      if (p.player.id == id) return p;
    }
    return null;
  }

  /// Players with the top score (more than one means a tie).
  List<PlayerResult> get winners {
    if (players.isEmpty) return const [];
    final top = players.map((p) => p.score).reduce((a, b) => a > b ? a : b);
    return players.where((p) => p.score == top).toList();
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'board': board.toJson(),
        'players': players.map((p) => p.toJson()).toList(),
        'replay': replay.map((e) => e.toJson()).toList(),
        'highlights': highlights.map((h) => h.toJson()).toList(),
        'longest': longest?.toJson(),
        'total': totalPossibleWords,
      };
}
