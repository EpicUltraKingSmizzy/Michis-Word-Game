/// Game sessions: the host runs the authoritative copy of the game, players
/// mirror it. Both sides share [GameSession] so the UI doesn't care which one
/// it is looking at. [SoloSession] plays a challenge link offline.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../logic/board.dart';
import '../logic/challenge.dart';
import '../logic/chat.dart';
import '../logic/dice.dart';
import '../logic/dictionary.dart';
import '../logic/models.dart';
import '../logic/path_validation.dart';
import '../logic/room_code.dart';
import '../logic/scoring.dart';
import '../logic/solver.dart';
import '../net/chunker.dart';
import '../net/link.dart';

enum SessionPhase { lobby, countdown, playing, waitingForResults, results }

/// Where a player is, as shown in the host's player list.
enum PlayerPresence {
  /// In the room and ready for the next round.
  ready,

  /// Connected, but still looking at the last round's results.
  viewingResults,

  /// Connection dropped; waiting a little while for them to come back.
  reconnecting,
}

const countdownDuration = Duration(seconds: 3);

/// Extra time the host waits after the buzzer for words still in flight.
const resultsGrace = Duration(milliseconds: 1500);

/// How long the host keeps a dropped player's seat before removing them.
const reconnectGrace = Duration(seconds: 30);

/// A player the host hasn't heard from for this long counts as dropped
/// (players ping every 5 seconds).
const silenceTimeout = Duration(seconds: 20);

/// Protocol version, bumped on incompatible message changes.
const protocolVersion = 2;

String _randomKey([int n = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

abstract class GameSession extends ChangeNotifier {
  GameSession({required this.dictionary, required this.roomCode});

  final Dictionary dictionary;
  final String roomCode;

  bool get isHost;
  String get myId;

  List<PlayerInfo> players = [];
  GameSettings settings = const GameSettings();
  SessionPhase phase = SessionPhase.lobby;

  /// Presence of players who aren't simply ready (missing = ready).
  Map<String, PlayerPresence> presence = {};
  PlayerPresence presenceOf(String id) => presence[id] ?? PlayerPresence.ready;

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
  final Map<String, List<int>> foundPaths = {};
  RoundResults? results;

  /// Lobby chat, oldest first. Kept for as long as the room is open.
  final List<ChatMessage> chat = [];

  /// Set when the session ended on its own (host left, connection lost).
  String? endedReason;
  bool _disposed = false;
  bool get isDisposed => _disposed;

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

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  PlayerInfo? get me => players.where((p) => p.id == myId).firstOrNull;

  Duration get timeLeft {
    final end = playEnd;
    if (end == null) return Duration.zero;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void updateProfile(String name, int avatar);

  /// Sends a chat message (text and/or a JPEG photo), optionally replying.
  void sendChat(String text, {Uint8List? image, Uint8List? thumb, ChatMessage? replyTo});

  /// Toggles my [emoji] reaction on a chat message.
  void react(String messageId, String emoji);

  ChatReply _replyRef(ChatMessage m) =>
      ChatReply(id: m.id, name: m.name, text: m.snippet, hasImage: m.hasImage);

  @protected
  void addChat(ChatMessage m) {
    if (chat.any((c) => c.id == m.id)) return;
    chat.add(m);
    if (chat.length > 300) chat.removeRange(0, chat.length - 300);
    notifyListeners();
  }

  @protected
  void mergeChatHistory(List<ChatMessage> history) {
    final known = {for (final c in chat) c.id: c};
    for (final m in history) {
      final mine = known[m.id];
      if (mine == null) {
        chat.add(m);
      } else {
        mine.reactions = m.reactions;
      }
    }
    chat.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    notifyListeners();
  }

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
      foundPaths[word] = List.of(path);
      sendWord(word, path);
      notifyListeners();
    }
    return result;
  }

  @protected
  void sendWord(String word, List<int> path);

  /// Starts the local countdown and round clock.
  @protected
  void beginRound(Board b, GameSettings s, List<PlayerInfo> participants, {DateTime? startAt}) {
    _cancelTimers();
    board = b;
    roundSettings = s;
    roundPlayers = participants;
    foundWords.clear();
    foundOrder.clear();
    foundPaths.clear();
    results = null;
    final now = startAt ?? DateTime.now();
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

  /// Connection id -> player id, and back.
  final Map<String, String> _playerOf = {};
  final Map<String, String> _connOf = {};
  final Map<String, Reassembler> _assemblers = {};
  final Map<String, DateTime> _lastHeard = {};
  final Map<String, Timer> _dropTimers = {};
  Map<String, List<int>> _solved = {};
  final Map<String, List<Submission>> _submissions = {};
  Map<String, dynamic>? _startMessage;
  RoundResults? _lastResults;

  @override
  bool get isHost => true;
  @override
  String get myId => _hostId;

  /// Players still looking at the last round's results.
  List<PlayerInfo> get playersViewingResults =>
      players.where((p) => presenceOf(p.id) == PlayerPresence.viewingResults).toList();

  /// Why Start is disabled right now, or null if the game can start.
  String? get startBlockedReason {
    final viewing = playersViewingResults;
    if (viewing.isEmpty) return null;
    final names = viewing.map((p) => p.name).toList();
    final who = names.length == 1
        ? names.first
        : names.length == 2
            ? '${names[0]} & ${names[1]}'
            : '${names.length} players';
    return '$who ${names.length == 1 ? 'is' : 'are'} still viewing results';
  }

  bool get canStart => phase == SessionPhase.lobby && startBlockedReason == null;

  void _listen() {
    _sub = link.events.listen(_onEvent);
    _ping = Timer.periodic(const Duration(seconds: 5), (_) {
      _broadcast({'t': 'ping'});
      _checkSilence();
    });
  }

  void _onEvent(HostEvent e) {
    switch (e) {
      case ClientConnected(:final connId):
        _lastHeard[connId] = DateTime.now();
      case ClientDisconnected(:final connId):
        _connectionLost(connId);
      case ClientMessage(:final connId, :final data):
        _lastHeard[connId] = DateTime.now();
        final full = _assemblers.putIfAbsent(connId, Reassembler.new).add(data);
        if (full != null) _onMessage(connId, full);
    }
  }

  /// A player's connection went away. Keep their seat for [reconnectGrace]
  /// in case they come back (app switch, network blip).
  void _connectionLost(String connId) {
    _assemblers.remove(connId);
    _lastHeard.remove(connId);
    final id = _playerOf.remove(connId);
    if (id == null) return;
    if (_connOf[id] != connId) return; // already replaced by a newer connection
    _connOf.remove(id);
    if (!players.any((p) => p.id == id)) return;
    presence[id] = PlayerPresence.reconnecting;
    _dropTimers[id]?.cancel();
    _dropTimers[id] = Timer(reconnectGrace, () => _removePlayer(id));
    _broadcastLobby();
    notifyListeners();
  }

  void _removePlayer(String id, {bool quit = false}) {
    if (_disposed) return;
    _dropTimers.remove(id)?.cancel();
    final conn = _connOf.remove(id);
    if (conn != null) {
      _playerOf.remove(conn);
      link.disconnect(conn);
    }
    presence.remove(id);
    final gone = players.where((p) => p.id == id).firstOrNull;
    players = players.where((p) => p.id != id).toList();
    if (gone != null) {
      say(quit ? '${gone.name} left the room.' : '${gone.name} lost their connection and left the room.');
      _broadcastLobby();
      notifyListeners();
    }
  }

  void _checkSilence() {
    final now = DateTime.now();
    for (final e in _lastHeard.entries.toList()) {
      if (now.difference(e.value) > silenceTimeout) {
        link.disconnect(e.key);
        _connectionLost(e.key);
      }
    }
  }

  void _onMessage(String connId, Map<String, dynamic> m) {
    if (m['t'] == 'hello') return _hello(connId, m);
    final id = _playerOf[connId];
    if (id == null) return;
    switch (m['t']) {
      case 'profile':
        final i = players.indexWhere((p) => p.id == id);
        if (i < 0) return;
        players = [...players]
          ..[i] = players[i].copyWith(name: _cleanName(m['name']), avatar: (m['avatar'] as num?)?.toInt());
        _broadcastLobby();
        notifyListeners();
      case 'word':
        final w = m['w'];
        final p = m['p'];
        if (w is String && p is List) _record(id, p.whereType<num>().map((n) => n.toInt()).toList());
      case 'presence':
        if (m['state'] == 'lobby' && presenceOf(id) == PlayerPresence.viewingResults) {
          presence.remove(id);
          _broadcastLobby();
          notifyListeners();
        }
      case 'chat':
        final img = m['img'], thumb = m['thumb'];
        _postChat(
          from: id,
          text: (m['text'] as String? ?? '').trim(),
          image: _b64(img),
          thumb: _b64(thumb),
          reply: m['reply'] is Map ? ChatReply.fromJson(Map<String, dynamic>.from(m['reply'] as Map)) : null,
        );
      case 'react':
        _applyReaction(id, m['id'] as String? ?? '', m['e'] as String? ?? '');
      case 'leave':
        _removePlayer(id, quit: true);
      case 'ping':
        _sendTo(connId, {'t': 'pong'});
    }
  }

  static Uint8List? _b64(Object? o) {
    if (o is! String || o.isEmpty) return null;
    try {
      return base64Decode(o);
    } catch (_) {
      return null;
    }
  }

  void _hello(String connId, Map<String, dynamic> m) {
    final key = (m['key'] as String?)?.trim();
    final id = key == null || key.isEmpty || key == _hostId ? connId : key;
    final name = _cleanName(m['name']);
    final avatar = (m['avatar'] as num?)?.toInt() ?? 0;
    final existing = players.indexWhere((p) => p.id == id);
    final resumed = existing >= 0;

    // Point the player at this (newest) connection.
    final old = _connOf[id];
    if (old != null && old != connId) {
      _playerOf.remove(old);
      link.disconnect(old);
    }
    _connOf[id] = connId;
    _playerOf[connId] = id;
    _dropTimers.remove(id)?.cancel();
    if (presenceOf(id) == PlayerPresence.reconnecting) presence.remove(id);

    if (resumed) {
      players = [...players]..[existing] = players[existing].copyWith(name: name, avatar: avatar);
    } else {
      players = [...players, PlayerInfo(id: id, name: name, avatar: avatar)];
    }
    _sendTo(connId, {'t': 'welcome', 'id': id, 'v': protocolVersion});
    if (chat.isNotEmpty) _sendTo(connId, {'t': 'chatHistory', 'ms': chatHistoryJson(chat)});

    if (resumed) _catchUp(connId, id, m);
    _broadcastLobby();
    if (!resumed) say('$name joined the room!');
    notifyListeners();
  }

  /// Brings a player who reconnected up to date with the round.
  void _catchUp(String connId, String id, Map<String, dynamic> m) {
    final theirPhase = m['phase'] as String? ?? 'lobby';
    final inRound = roundPlayers.any((p) => p.id == id);
    // Words they found while the connection was down.
    final words = m['words'];
    if (words is List && inRound) {
      for (final w in words) {
        if (w is List) _record(id, w.whereType<num>().map((n) => n.toInt()).toList());
      }
    }
    final roundRunning = phase == SessionPhase.countdown ||
        phase == SessionPhase.playing ||
        phase == SessionPhase.waitingForResults;
    final theyPlaying = theirPhase == 'countdown' || theirPhase == 'playing' || theirPhase == 'waitingForResults';
    if (roundRunning && inRound && !theyPlaying && _startMessage != null) {
      _sendTo(connId, _startMessage!);
    } else if (!roundRunning && theyPlaying && inRound && _lastResults != null) {
      _sendTo(connId, {'t': 'results', 'results': _lastResults!.toJson()});
      if (phase == SessionPhase.lobby) {
        presence[id] = PlayerPresence.viewingResults;
        _sendTo(connId, {'t': 'toLobby'});
      }
    } else if (phase == SessionPhase.lobby && theirPhase == 'results') {
      presence[id] = PlayerPresence.viewingResults;
      _sendTo(connId, {'t': 'toLobby'});
    }
  }

  String _cleanName(Object? raw) {
    final s = (raw is String ? raw : '').trim();
    if (s.isEmpty) return 'Player';
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  void _sendTo(String connId, Map<String, dynamic> m) {
    for (final part in chunkMessage(m)) {
      link.send(connId, part);
    }
  }

  void _broadcast(Map<String, dynamic> m) {
    final parts = chunkMessage(m);
    for (final conn in _connOf.values.toList()) {
      for (final part in parts) {
        link.send(conn, part);
      }
    }
  }

  void _broadcastLobby() => _broadcast(_lobbyMessage());

  Map<String, dynamic> _lobbyMessage() => {
        't': 'lobby',
        'code': roomCode,
        'players': players.map((p) => p.toJson()).toList(),
        'presence': {for (final e in presence.entries) e.key: e.value.name},
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

  // ---- Chat ----

  int _chatSeq = 0;

  void _postChat({
    required String from,
    required String text,
    Uint8List? image,
    Uint8List? thumb,
    ChatReply? reply,
  }) {
    if (text.isEmpty && image == null) return;
    final p = players.where((x) => x.id == from).firstOrNull;
    if (p == null) return;
    final m = ChatMessage(
      id: '${roomCode.toLowerCase()}-${++_chatSeq}-${_randomKey(4)}',
      from: from,
      name: p.name,
      avatar: p.avatar,
      text: text.length > 1000 ? text.substring(0, 1000) : text,
      sentAt: DateTime.now(),
      image: image,
      thumb: thumb,
      reply: reply,
    );
    addChat(m);
    _broadcast({'t': 'chat', 'm': m.toJson()});
  }

  void _applyReaction(String playerId, String messageId, String emoji) {
    if (!chatReactions.contains(emoji)) return;
    final m = chat.where((c) => c.id == messageId).firstOrNull;
    if (m == null) return;
    toggleReaction(m, playerId, emoji);
    _broadcast({'t': 'react', 'id': m.id, 'r': m.reactions});
    notifyListeners();
  }

  @override
  void sendChat(String text, {Uint8List? image, Uint8List? thumb, ChatMessage? replyTo}) => _postChat(
        from: _hostId,
        text: text.trim(),
        image: image,
        thumb: thumb,
        reply: replyTo == null ? null : _replyRef(replyTo),
      );

  @override
  void react(String messageId, String emoji) => _applyReaction(_hostId, messageId, emoji);

  // ---- Rounds ----

  void startGame() {
    if (!canStart) return;
    final b = generateGoodBoard(
      size: settings.gridSize,
      minWordLength: settings.minWordLength,
      dictionary: dictionary,
      random: _random,
    );
    _solved = solveBoard(b, dictionary, minWordLength: settings.minWordLength);
    _submissions.clear();
    // Everyone who is connected plays; players mid-reconnect sit this one out.
    final participants =
        players.where((p) => presenceOf(p.id) != PlayerPresence.reconnecting).toList();
    for (final p in participants) {
      _submissions[p.id] = [];
    }
    _lastResults = null;
    _startMessage = {
      't': 'start',
      'board': b.toJson(),
      'settings': settings.toJson(),
      'players': participants.map((p) => p.toJson()).toList(),
    };
    _broadcast(_startMessage!);
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
    _lastResults = r;
    _startMessage = null;
    showResults(r);
    _broadcast({'t': 'results', 'results': r.toJson()});
  }

  /// The host heads back to the room. Players who are still looking at the
  /// results stay there until they tap "Back to the room" themselves.
  void backToRoom() {
    final participants = roundPlayers.map((p) => p.id).toSet();
    returnToLobby();
    for (final p in players) {
      if (p.id != _hostId && participants.contains(p.id) && _connOf.containsKey(p.id)) {
        presence[p.id] = PlayerPresence.viewingResults;
      }
    }
    _broadcast({'t': 'toLobby'});
    _broadcastLobby();
    notifyListeners();
  }

  @override
  Future<void> leave() async {
    _broadcast({'t': 'bye', 'reason': 'The host closed the game.'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _shutdown();
  }

  Future<void> _shutdown() async {
    _ping?.cancel();
    for (final t in _dropTimers.values) {
      t.cancel();
    }
    await _sub?.cancel();
    await link.close();
  }

  @override
  void dispose() {
    _ping?.cancel();
    for (final t in _dropTimers.values) {
      t.cancel();
    }
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
    required ClientLink Function() linkFactory,
    required String key,
    required String name,
    required int avatar,
  })  : _linkFactory = linkFactory, // ignore: prefer_initializing_formals
        _key = key, // ignore: prefer_initializing_formals
        _name = name, // ignore: prefer_initializing_formals
        _avatar = avatar; // ignore: prefer_initializing_formals

  /// Joins [roomCode]. Throws [LinkException] with a friendly message.
  static Future<ClientSession> join({
    required Dictionary dictionary,
    required ClientLink Function() linkFactory,
    required String roomCode,
    required String name,
    required int avatar,
    void Function()? onWaiting,
  }) async {
    final link = linkFactory();
    await link.connect(roomCode, onWaiting: onWaiting);
    final s = ClientSession._(
      dictionary: dictionary,
      roomCode: roomCode,
      link: link,
      linkFactory: linkFactory,
      key: _randomKey(),
      name: name,
      avatar: avatar,
    );
    s._attachLink(link);
    s._startPing();
    try {
      await s._sayHello(resume: false).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      s._leaving = true;
      await link.close();
      s.dispose();
      throw const LinkException(LinkErrorKind.timeout, 'I reached the host but they never let us in. Try joining again!');
    }
    return s;
  }

  ClientLink link;
  final ClientLink Function() _linkFactory;
  final String _key;
  String _name;
  int _avatar;
  String _myId = '';
  Completer<void>? _welcome;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Reassembler _assembler = Reassembler();
  Timer? _ping;
  DateTime _lastHeard = DateTime.now();
  bool _leaving = false;

  /// True while we lost the host and are trying to get back in.
  bool reconnecting = false;

  /// True once the host has gone back to the room while we were still
  /// looking at the results.
  bool hostBackInRoom = false;

  @override
  bool get isHost => false;
  @override
  String get myId => _myId;

  void _attachLink(ClientLink l) {
    link = l;
    _assembler = Reassembler();
    _sub?.cancel();
    _sub = l.messages.listen((data) {
      _lastHeard = DateTime.now();
      final full = _assembler.add(data);
      if (full != null) _onMessage(full);
    });
    l.closed.then((_) {
      if (identical(link, l)) _connectionLost();
    });
  }

  void _startPing() {
    _ping = Timer.periodic(const Duration(seconds: 5), (_) {
      if (reconnecting) return;
      _send({'t': 'ping'});
      if (DateTime.now().difference(_lastHeard) > silenceTimeout) {
        // The connection looks open but nothing comes through: start over.
        final l = link;
        _connectionLost();
        l.close();
      }
    });
  }

  Future<void> _sayHello({required bool resume}) {
    final w = _welcome = Completer<void>();
    _send({
      't': 'hello',
      'name': _name,
      'avatar': _avatar,
      'v': protocolVersion,
      'key': _key,
      if (resume) ...{
        'resume': true,
        'phase': phase.name,
        'words': [for (final w in foundOrder) foundPaths[w] ?? const <int>[]],
      },
    });
    return w.future;
  }

  void _send(Map<String, dynamic> m) {
    for (final part in chunkMessage(m)) {
      link.send(part);
    }
  }

  /// Lost the host: try to get back in for a little while before giving up.
  Future<void> _connectionLost() async {
    if (_leaving || reconnecting || _disposed || endedReason != null) return;
    reconnecting = true;
    notifyListeners();
    say('Lost the host for a moment… reconnecting!');
    final deadline = DateTime.now().add(reconnectGrace - const Duration(seconds: 5));
    while (!_leaving && !_disposed && DateTime.now().isBefore(deadline)) {
      final l = _linkFactory();
      try {
        await l.connect(roomCode).timeout(deadline.difference(DateTime.now()) + const Duration(seconds: 1));
        if (_leaving || _disposed) {
          await l.close();
          return;
        }
        _attachLink(l);
        await _sayHello(resume: true).timeout(const Duration(seconds: 8));
        reconnecting = false;
        _lastHeard = DateTime.now();
        notifyListeners();
        say("We're back!");
        return;
      } catch (_) {
        await l.close();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    reconnecting = false;
    if (!_leaving) end('Lost the connection to the host.');
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'welcome':
        _myId = m['id'] as String;
        final w = _welcome;
        if (w != null && !w.isCompleted) w.complete();
        notifyListeners();
      case 'lobby':
        players = (m['players'] as List).map((e) => PlayerInfo.fromJson(_deepMap(e))).toList();
        settings = GameSettings.fromJson(_deepMap(m['settings']));
        final pres = m['presence'];
        presence = {
          if (pres is Map)
            for (final e in pres.entries)
              '${e.key}': PlayerPresence.values.firstWhere((v) => v.name == e.value,
                  orElse: () => PlayerPresence.ready),
        };
        final inRound = m['inRound'] as bool? ?? false;
        if (!inRound) hostBackInRoom = true;
        // Only matters while we're sitting in the waiting room.
        roundInProgress = phase == SessionPhase.lobby && inRound;
        notifyListeners();
      case 'start':
        final participants = (m['players'] as List).map((e) => PlayerInfo.fromJson(_deepMap(e))).toList();
        if (!participants.any((p) => p.id == _myId)) {
          roundInProgress = true;
          notifyListeners();
          return;
        }
        roundInProgress = false;
        hostBackInRoom = false;
        beginRound(
          Board.fromJson(_deepMap(m['board'])),
          GameSettings.fromJson(_deepMap(m['settings'])),
          participants,
        );
      case 'results':
        if (!roundPlayers.any((p) => p.id == _myId) || board == null) return;
        hostBackInRoom = false;
        showResults(RoundResults.fromJson(_deepMap(m['results'])));
      case 'toLobby':
        roundInProgress = false;
        hostBackInRoom = true;
        if (phase == SessionPhase.results) {
          // Stay on the results until the player is done with them.
          notifyListeners();
        } else {
          roundPlayers = [];
          returnToLobby();
        }
      case 'chat':
        addChat(ChatMessage.fromJson(_deepMap(m['m'])));
      case 'chatHistory':
        mergeChatHistory([for (final e in m['ms'] as List) ChatMessage.fromJson(_deepMap(e))]);
      case 'react':
        final msg = chat.where((c) => c.id == m['id']).firstOrNull;
        if (msg != null) {
          msg.reactions = ChatMessage.reactionsFromJson(m['r']);
          notifyListeners();
        }
      case 'bye':
        _leaving = true;
        end(m['reason'] as String? ?? 'The host closed the game.');
        link.close();
    }
  }

  /// Done with the results: go back to the waiting room.
  void finishResults() {
    if (phase != SessionPhase.results) return;
    roundPlayers = [];
    returnToLobby();
    _send({'t': 'presence', 'state': 'lobby'});
  }

  static Map<String, dynamic> _deepMap(Object? o) => Map<String, dynamic>.from(_deep(o) as Map);
  static Object? _deep(Object? o) {
    if (o is Map) return {for (final e in o.entries) '${e.key}': _deep(e.value)};
    if (o is List) return o.map(_deep).toList();
    return o;
  }

  @override
  void updateProfile(String name, int avatar) {
    _name = name;
    _avatar = avatar;
    _send({'t': 'profile', 'name': name, 'avatar': avatar});
  }

  @override
  void sendWord(String word, List<int> path) => _send({'t': 'word', 'w': word, 'p': path});

  @override
  void sendChat(String text, {Uint8List? image, Uint8List? thumb, ChatMessage? replyTo}) {
    final t = text.trim();
    if (t.isEmpty && image == null) return;
    _send({
      't': 'chat',
      'text': t,
      if (image != null) 'img': base64Encode(image),
      if (thumb != null) 'thumb': base64Encode(thumb),
      if (replyTo != null) 'reply': _replyRef(replyTo).toJson(),
    });
  }

  @override
  void react(String messageId, String emoji) {
    // Show it right away; the host's update will confirm it.
    final m = chat.where((c) => c.id == messageId).firstOrNull;
    if (m != null) {
      toggleReaction(m, _myId, emoji);
      notifyListeners();
    }
    _send({'t': 'react', 'id': messageId, 'e': emoji});
  }

  @override
  Future<void> leave() async {
    _leaving = true;
    _send({'t': 'leave'});
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await link.close();
  }

  @override
  void dispose() {
    _leaving = true;
    _ping?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// Plays a challenge link on this device alone, then scores the round
/// together with the friends' results from the link.
class SoloSession extends GameSession {
  SoloSession({
    required super.dictionary,
    required this.challenge,
    required String name,
    required int avatar,
  }) : super(roomCode: 'SOLO') {
    players = [PlayerInfo(id: soloId, name: name, avatar: avatar, isHost: true)];
    settings = challenge.settings;
  }

  static const soloId = 'me';
  final Challenge challenge;

  @override
  bool get isHost => true;
  @override
  String get myId => soloId;

  /// Friends from the link, as players (ids f0, f1, …).
  List<PlayerInfo> get friends => [
        for (var i = 0; i < challenge.players.length; i++)
          PlayerInfo(id: 'f$i', name: challenge.players[i].name, avatar: challenge.players[i].avatar),
      ];

  void start() {
    if (phase != SessionPhase.lobby && phase != SessionPhase.results) return;
    beginRound(challenge.board, challenge.settings, [players.first]);
  }

  @override
  void sendWord(String word, List<int> path) {}

  @override
  void onBuzzer() => _after(const Duration(milliseconds: 600), _finish);

  void _finish() {
    final b = board!;
    final solved = solveBoard(b, dictionary, minWordLength: challenge.settings.minWordLength);
    final fr = friends;
    final subs = <String, List<Submission>>{
      soloId: [
        for (var i = 0; i < foundOrder.length; i++)
          Submission(word: foundOrder[i], path: foundPaths[foundOrder[i]]!, atMs: 1000 + i),
      ],
    };
    final scoreOnly = <int>[];
    for (var i = 0; i < challenge.players.length; i++) {
      final words = challenge.players[i].words;
      if (words == null) {
        scoreOnly.add(i);
        continue;
      }
      // Friends played first, so their paths are the ones shown.
      subs[fr[i].id] = [
        for (final w in words)
          if (solved[w] != null) Submission(word: w, path: solved[w]!, atMs: 0),
      ];
    }
    final scored = [players.first, for (var i = 0; i < fr.length; i++) if (!scoreOnly.contains(i)) fr[i]];
    var r = scoreRound(board: b, settings: challenge.settings, players: scored, submissions: subs, solved: solved);
    if (scoreOnly.isNotEmpty) {
      final extra = [
        for (final i in scoreOnly)
          PlayerResult(
            player: fr[i],
            words: const [],
            score: challenge.players[i].score,
            uniqueWords: const [],
          ),
      ];
      final all = [...r.players, ...extra]..sort((a, b) => b.score.compareTo(a.score));
      r = RoundResults(
        settings: r.settings,
        board: r.board,
        players: all,
        replay: r.replay,
        highlights: r.highlights,
        longest: r.longest,
        totalPossibleWords: r.totalPossibleWords,
        tieBreak: r.tieBreak,
      );
    }
    showResults(r);
  }

  @override
  void updateProfile(String name, int avatar) {
    players = [players.first.copyWith(name: name, avatar: avatar)];
    notifyListeners();
  }

  @override
  void sendChat(String text, {Uint8List? image, Uint8List? thumb, ChatMessage? replyTo}) {}

  @override
  void react(String messageId, String emoji) {}

  @override
  Future<void> leave() async {}
}
