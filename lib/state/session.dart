/// Game sessions: the host runs the authoritative copy of the game, players
/// mirror it. Both sides share [GameSession] so the UI doesn't care which one
/// it is looking at.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../logic/board.dart';
import '../logic/dice.dart';
import '../logic/dictionary.dart';
import '../logic/models.dart';
import '../logic/path_validation.dart';
import '../logic/room_code.dart';
import '../logic/scoring.dart';
import '../logic/solver.dart';
import '../net/link.dart';

enum SessionPhase { lobby, countdown, playing, waitingForResults, results }

const countdownDuration = Duration(seconds: 3);

/// Extra time the host waits after the buzzer for words still in flight.
const resultsGrace = Duration(milliseconds: 1500);

/// Protocol version, bumped on incompatible message changes.
const protocolVersion = 1;

abstract class GameSession extends ChangeNotifier {
  GameSession({required this.dictionary, required this.roomCode});

  final Dictionary dictionary;
  final String roomCode;

  bool get isHost;
  String get myId;

  List<PlayerInfo> players = [];
  GameSettings settings = const GameSettings();
  SessionPhase phase = SessionPhase.lobby;

  /// True while a round that this device isn't part of is being played.
  bool roundInProgress = false;

  Board? board;
  GameSettings roundSettings = const GameSettings();
  List<PlayerInfo> roundPlayers = [];
  DateTime? countdownStart;
  DateTime? playStart;
  DateTime? playEnd;

  final Set<String> foundWords = {};
  final List<String> foundOrder = [];
  RoundResults? results;

  /// Set when the session ended on its own (host left, connection lost).
  String? endedReason;
  bool _disposed = false;

  final _mascot = StreamController<String>.broadcast();

  /// Short system messages for the mascot to say.
  Stream<String> get mascotMessages => _mascot.stream;
  void say(String text) {
    if (!_mascot.isClosed) _mascot.add(text);
  }

  final List<Timer> _timers = [];
  void _after(Duration d, void Function() f) => _timers.add(Timer(d, () {
        if (!_disposed) f();
      }));
  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  PlayerInfo? get me => players.where((p) => p.id == myId).firstOrNull;

  Duration get timeLeft {
    final end = playEnd;
    if (end == null) return Duration.zero;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void updateProfile(String name, int avatar);

  /// Checks a traced path and, if it's a new word, locks it in.
  SubmissionResult submitPath(List<int> path) {
    final b = board;
    if (b == null || phase != SessionPhase.playing) return SubmissionResult.invalidPath;
    final result = checkSubmission(
      board: b,
      path: path,
      dictionary: dictionary,
      minWordLength: roundSettings.minWordLength,
      alreadyFound: foundWords,
    );
    if (result == SubmissionResult.added) {
      final word = b.wordForPath(path);
      foundWords.add(word);
      foundOrder.add(word);
      sendWord(word, path);
      notifyListeners();
    }
    return result;
  }

  @protected
  void sendWord(String word, List<int> path);

  /// Starts the local countdown and round clock.
  @protected
  void beginRound(Board b, GameSettings s, List<PlayerInfo> participants) {
    _cancelTimers();
    board = b;
    roundSettings = s;
    roundPlayers = participants;
    foundWords.clear();
    foundOrder.clear();
    results = null;
    final now = DateTime.now();
    countdownStart = now;
    playStart = now.add(countdownDuration);
    playEnd = playStart!.add(Duration(seconds: s.durationSeconds));
    phase = SessionPhase.countdown;
    _after(countdownDuration, () {
      phase = SessionPhase.playing;
      notifyListeners();
    });
    _after(countdownDuration + Duration(seconds: s.durationSeconds), () {
      phase = SessionPhase.waitingForResults;
      notifyListeners();
      onBuzzer();
    });
    notifyListeners();
  }

  @protected
  void onBuzzer() {}

  @protected
  void showResults(RoundResults r) {
    _cancelTimers();
    results = r;
    phase = SessionPhase.results;
    notifyListeners();
  }

  @protected
  void returnToLobby() {
    _cancelTimers();
    phase = SessionPhase.lobby;
    board = null;
    results = null;
    notifyListeners();
  }

  @protected
  void end(String reason) {
    if (endedReason != null || _disposed) return;
    endedReason = reason;
    _cancelTimers();
    notifyListeners();
  }

  /// Leave the room (the host closes it for everyone).
  Future<void> leave();

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _mascot.close();
    super.dispose();
  }
}

/// The host's copy of the game. It owns the room, the board, and the scores.
class HostSession extends GameSession {
  HostSession._({
    required super.dictionary,
    required super.roomCode,
    required this.link,
    required PlayerInfo host,
    Random? random,
  }) : _random = random ?? Random() {
    players = [host];
    _hostId = host.id;
  }

  /// Opens a room, retrying with fresh codes if one is taken.
  static Future<HostSession> create({
    required Dictionary dictionary,
    required HostLink Function() linkFactory,
    required String name,
    required int avatar,
    GameSettings settings = const GameSettings(),
    Random? random,
  }) async {
    LinkException? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      final code = generateRoomCode(random);
      final link = linkFactory();
      try {
        await link.open(code);
      } on LinkException catch (e) {
        last = e;
        await link.close();
        if (e.kind == LinkErrorKind.roomTaken) continue;
        rethrow;
      }
      final s = HostSession._(
        dictionary: dictionary,
        roomCode: code,
        link: link,
        host: PlayerInfo(id: 'host', name: name, avatar: avatar, isHost: true),
        random: random,
      )..settings = settings;
      s._listen();
      return s;
    }
    throw last ?? const LinkException(LinkErrorKind.network, 'Could not open a room.');
  }

  final HostLink link;
  final Random _random;
  late final String _hostId;
  StreamSubscription<HostEvent>? _sub;
  Timer? _ping;
  final Set<String> _hello = {};
  Map<String, List<int>> _solved = {};
  final Map<String, List<Submission>> _submissions = {};

  @override
  bool get isHost => true;
  @override
  String get myId => _hostId;

  void _listen() {
    _sub = link.events.listen(_onEvent);
    _ping = Timer.periodic(const Duration(seconds: 5), (_) => _broadcast({'t': 'ping'}));
  }

  void _onEvent(HostEvent e) {
    switch (e) {
      case ClientConnected():
        break;
      case ClientDisconnected(:final connId):
        _hello.remove(connId);
        final gone = players.where((p) => p.id == connId).firstOrNull;
        players = players.where((p) => p.id != connId).toList();
        if (gone != null) {
          say('${gone.name} left the room.');
          _broadcastLobby();
          notifyListeners();
        }
      case ClientMessage(:final connId, :final data):
        _onMessage(connId, data);
    }
  }

  void _onMessage(String id, Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hello':
        final name = _cleanName(m['name']);
        final avatar = (m['avatar'] as num?)?.toInt() ?? 0;
        _hello.add(id);
        players = [
          ...players.where((p) => p.id != id),
          PlayerInfo(id: id, name: name, avatar: avatar),
        ];
        link.send(id, {'t': 'welcome', 'id': id, 'v': protocolVersion});
        _broadcastLobby();
        say('$name joined the room!');
        notifyListeners();
      case 'profile':
        final i = players.indexWhere((p) => p.id == id);
        if (i < 0) return;
        players = [...players]
          ..[i] = players[i].copyWith(
              name: _cleanName(m['name']), avatar: (m['avatar'] as num?)?.toInt());
        _broadcastLobby();
        notifyListeners();
      case 'word':
        final w = m['w'];
        final p = m['p'];
        if (w is String && p is List) _record(id, p.whereType<num>().map((n) => n.toInt()).toList());
      case 'ping':
        link.send(id, {'t': 'pong'});
    }
  }

  String _cleanName(Object? raw) {
    final s = (raw is String ? raw : '').trim();
    if (s.isEmpty) return 'Player';
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  void _broadcast(Map<String, dynamic> m) {
    for (final id in _hello.toList()) {
      link.send(id, m);
    }
  }

  void _broadcastLobby() => _broadcast(_lobbyMessage());

  Map<String, dynamic> _lobbyMessage() => {
        't': 'lobby',
        'code': roomCode,
        'players': players.map((p) => p.toJson()).toList(),
        'settings': settings.toJson(),
        'inRound': phase != SessionPhase.lobby,
      };

  void updateSettings(GameSettings s) {
    if (s == settings) return;
    settings = s;
    _broadcastLobby();
    notifyListeners();
  }

  @override
  void updateProfile(String name, int avatar) {
    players = [
      for (final p in players) p.id == _hostId ? p.copyWith(name: _cleanName(name), avatar: avatar) : p
    ];
    _broadcastLobby();
    notifyListeners();
  }

  void startGame() {
    if (phase != SessionPhase.lobby) return;
    final b = generateGoodBoard(
      size: settings.gridSize,
      minWordLength: settings.minWordLength,
      dictionary: dictionary,
      random: _random,
    );
    _solved = solveBoard(b, dictionary, minWordLength: settings.minWordLength);
    _submissions.clear();
    final participants = List.of(players);
    for (final p in participants) {
      _submissions[p.id] = [];
    }
    _broadcast({
      't': 'start',
      'board': b.toJson(),
      'settings': settings.toJson(),
      'players': participants.map((p) => p.toJson()).toList(),
    });
    beginRound(b, settings, participants);
    _broadcastLobby();
  }

  @override
  void sendWord(String word, List<int> path) => _record(_hostId, path);

  void _record(String playerId, List<int> path) {
    final b = board;
    final start = playStart;
    if (b == null || start == null) return;
    if (phase != SessionPhase.playing && phase != SessionPhase.waitingForResults) return;
    final list = _submissions[playerId];
    if (list == null) return; // not in this round
    final res = checkSubmission(
      board: b,
      path: path,
      dictionary: dictionary,
      minWordLength: roundSettings.minWordLength,
      alreadyFound: list.map((s) => s.word).toSet(),
    );
    if (res != SubmissionResult.added) return;
    list.add(Submission(
      word: b.wordForPath(path),
      path: path,
      atMs: DateTime.now().difference(start).inMilliseconds,
    ));
  }

  @override
  void onBuzzer() => _after(resultsGrace, _finishRound);

  void _finishRound() {
    final b = board;
    if (b == null) return;
    // Use the latest names/avatars for anyone still here.
    final current = {for (final p in players) p.id: p};
    final roster = [for (final p in roundPlayers) current[p.id] ?? p];
    final r = scoreRound(
      board: b,
      settings: roundSettings,
      players: roster,
      submissions: _submissions,
      solved: _solved,
    );
    showResults(r);
    _broadcast({'t': 'results', 'results': r.toJson()});
  }

  /// Ends the scoring screen for everyone and goes back to the room.
  void backToRoom() {
    returnToLobby();
    _broadcast({'t': 'toLobby'});
    _broadcastLobby();
  }

  @override
  Future<void> leave() async {
    _broadcast({'t': 'bye', 'reason': 'The host closed the game.'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _shutdown();
  }

  Future<void> _shutdown() async {
    _ping?.cancel();
    await _sub?.cancel();
    await link.close();
  }

  @override
  void dispose() {
    _ping?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// A player's mirror of the host's game.
class ClientSession extends GameSession {
  ClientSession._({
    required super.dictionary,
    required super.roomCode,
    required this.link,
  });

  /// Joins [roomCode]. Throws [LinkException] with a friendly message.
  static Future<ClientSession> join({
    required Dictionary dictionary,
    required ClientLink Function() linkFactory,
    required String roomCode,
    required String name,
    required int avatar,
  }) async {
    final link = linkFactory();
    await link.connect(roomCode);
    final s = ClientSession._(
      dictionary: dictionary,
      roomCode: roomCode,
      link: link,
    );
    s._listen();
    final welcomed = s._welcome.future;
    link.send({'t': 'hello', 'name': name, 'avatar': avatar, 'v': protocolVersion});
    try {
      await welcomed.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await link.close();
      s.dispose();
      throw const LinkException(LinkErrorKind.timeout,
          'I reached the host but they never let us in. Try joining again!');
    }
    return s;
  }

  final ClientLink link;
  String _myId = '';
  final _welcome = Completer<void>();
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _ping;
  DateTime _lastHeard = DateTime.now();

  @override
  bool get isHost => false;
  @override
  String get myId => _myId;

  void _listen() {
    _sub = link.messages.listen(_onMessage);
    link.closed.then((_) => end('Lost the connection to the host.'));
    _ping = Timer.periodic(const Duration(seconds: 5), (_) {
      link.send({'t': 'ping'});
      if (DateTime.now().difference(_lastHeard) > const Duration(seconds: 40)) {
        end("I haven't heard from the host in a while, so we lost the game.");
        link.close();
      }
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    _lastHeard = DateTime.now();
    switch (m['t']) {
      case 'welcome':
        _myId = m['id'] as String;
        if (!_welcome.isCompleted) _welcome.complete();
        notifyListeners();
      case 'lobby':
        players = (m['players'] as List)
            .map((e) => PlayerInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        settings = GameSettings.fromJson(Map<String, dynamic>.from(m['settings'] as Map));
        // Only matters while we're sitting in the waiting room.
        roundInProgress =
            phase == SessionPhase.lobby && (m['inRound'] as bool? ?? false);
        notifyListeners();
      case 'start':
        final participants = (m['players'] as List)
            .map((e) => PlayerInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (!participants.any((p) => p.id == _myId)) {
          roundInProgress = true;
          notifyListeners();
          return;
        }
        roundInProgress = false;
        beginRound(
          Board.fromJson(Map<String, dynamic>.from(m['board'] as Map)),
          GameSettings.fromJson(Map<String, dynamic>.from(m['settings'] as Map)),
          participants,
        );
      case 'results':
        if (!roundPlayers.any((p) => p.id == _myId) || board == null) return;
        showResults(RoundResults.fromJson(_deepMap(m['results'])));
      case 'toLobby':
        roundInProgress = false;
        roundPlayers = [];
        returnToLobby();
      case 'bye':
        end(m['reason'] as String? ?? 'The host closed the game.');
        link.close();
    }
  }

  static Map<String, dynamic> _deepMap(Object? o) => Map<String, dynamic>.from(_deep(o) as Map);
  static Object? _deep(Object? o) {
    if (o is Map) return {for (final e in o.entries) '${e.key}': _deep(e.value)};
    if (o is List) return o.map(_deep).toList();
    return o;
  }

  @override
  void updateProfile(String name, int avatar) {
    link.send({'t': 'profile', 'name': name, 'avatar': avatar});
  }

  @override
  void sendWord(String word, List<int> path) => link.send({'t': 'word', 'w': word, 'p': path});

  @override
  Future<void> leave() async {
    await link.close();
  }

  @override
  void dispose() {
    _ping?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
