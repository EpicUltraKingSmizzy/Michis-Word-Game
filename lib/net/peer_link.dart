/// PeerJS (via `peerdart`) implementation of the links.
///
/// Matchmaking goes through the free public PeerJS server (0.peerjs.com).
/// After that, players talk to the host directly over WebRTC data channels.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCIceConnectionState;
import 'package:peerdart/peerdart.dart';

import '../logic/room_code.dart';
import 'ice_servers.dart';
import 'link.dart';

/// Set to true (e.g. with `?debug=1` on the web) to log PeerJS traffic.
bool verbosePeerLogs = false;

/// How long a player keeps trying to reach a host before giving up. Long
/// enough for a host who switched apps to send the invite to come back.
const Duration joinPatience = Duration(minutes: 2);

PeerOptions _options({String? token}) => PeerOptions(
      config: currentIceConfig(),
      token: token,
      debug: verbosePeerLogs ? LogLevel.All : (kDebugMode ? LogLevel.Errors : LogLevel.Disabled),
    );

String _randomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
}

class PeerHostLink implements HostLink {
  /// Every Peer object this room has used. The newest one is registered with
  /// the matchmaking server; older ones only keep their existing player
  /// connections alive, so they are kept until the room closes.
  final List<Peer> _peers = [];
  final _events = StreamController<HostEvent>.broadcast();
  final _conns = <String, DataConnection>{};
  final _subs = <StreamSubscription<dynamic>>[];
  bool _closed = false;
  String? _code;
  bool _reregistering = false;

  /// Sent with every registration of this room. The PeerJS server lets a
  /// client with the same id AND token take over a stale registration, so
  /// coming back from the background reclaims the room id at once.
  final String _token = _randomId();
  Timer? _watchdog;

  Peer? get _peer => _peers.isEmpty ? null : _peers.last;

  /// True while the room is registered with the matchmaking server, so new
  /// players can find it.
  bool get registered => _peer?.open ?? false;

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> open(String roomCode) async {
    _code = roomCode;
    await iceServersReady();
    try {
      await _register().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await close();
      throw const LinkException(LinkErrorKind.timeout,
          'The matchmaking server is taking too long. Try again in a moment!');
    } catch (_) {
      await close();
      rethrow;
    }
    // If the server connection drops (phone in another app, network change),
    // register again with the same id so join links keep working.
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _ensureRegistered());
  }

  /// Creates a Peer for the room id and waits for the server to accept it.
  Future<void> _register() {
    final peer = Peer(id: hostPeerId(_code!), options: _options(token: _token));
    _peers.add(peer);
    final ready = Completer<void>();
    _subs.add(peer.on<dynamic>('open').listen((_) {
      if (!ready.isCompleted) ready.complete();
    }));
    _subs.add(peer.on<dynamic>('error').listen((err) {
      final text = '$err';
      if (!ready.isCompleted) {
        ready.completeError(text.contains('taken')
            ? const LinkException(LinkErrorKind.roomTaken, 'That room code is taken.')
            : const LinkException(LinkErrorKind.network,
                "I couldn't reach the matchmaking server. Check your internet and try again!"));
      } else {
        _soon();
      }
    }));
    _subs.add(peer.on<dynamic>('disconnected').listen((_) => _soon()));
    _subs.add(peer.on<DataConnection>('connection').listen(_accept));
    return ready.future;
  }

  void _soon() => Future<void>.delayed(const Duration(milliseconds: 800), _ensureRegistered);

  /// Registers a fresh Peer with the same id if the current one lost the
  /// server. (peerdart's own `reconnect()` can't recover a closed socket.)
  Future<void> _ensureRegistered({bool force = false}) async {
    if (_closed || _reregistering || _code == null) return;
    final current = _peer;
    if (!force && current != null && _alive(current)) return;
    _reregistering = true;
    try {
      // Close the old server socket (its player connections stay open).
      try {
        current?.disconnect();
      } catch (_) {}
      for (var attempt = 0; !_closed; attempt++) {
        try {
          await _register().timeout(const Duration(seconds: 12));
          if (verbosePeerLogs) debugPrint('[peer] room $_code registered again');
          return;
        } catch (e) {
          // "Taken" means the server still remembers our old socket; it
          // forgets it within a minute. Keep trying with a gentle backoff.
          final failed = _peers.removeLast();
          try {
            failed.dispose();
          } catch (_) {}
          if (verbosePeerLogs) debugPrint('[peer] re-register failed: $e');
          await Future<void>.delayed(Duration(seconds: min(2 + attempt, 8)));
        }
      }
    } finally {
      _reregistering = false;
    }
  }

  /// Whether [p] still has (or is still opening) its server connection.
  /// Checks the socket itself: before the 0.2.1 peerdart patch a dropped
  /// socket left `open == true` forever, which silently locked new players
  /// out of the room.
  static bool _alive(Peer p) {
    if (p.destroyed || p.disconnected) return false;
    try {
      return p.socket.isOpen;
    } catch (_) {
      return p.open;
    }
  }

  /// Call when the app comes back to the foreground. After a long time away
  /// the server socket may look alive but be dead, so register again.
  void appResumed(Duration away) {
    if (_closed) return;
    // Phones often kill or freeze a background tab's server socket without
    // telling us, so register again after any real absence. Thanks to the
    // fixed token this is quick and doesn't disturb connected players.
    unawaited(_ensureRegistered(force: away > const Duration(seconds: 3) && !_reregistering));
  }

  void _accept(DataConnection conn) {
    final id = '${conn.peer}/${conn.connectionId}';
    _conns[id] = conn;
    var announced = false;
    void announce() {
      if (announced) return;
      announced = true;
      _events.add(ClientConnected(id));
    }

    _subs.add(conn.on<dynamic>('open').listen((_) => announce()));
    _subs.add(conn.on<dynamic>('data').listen((data) {
      announce();
      if (data is Map) {
        _events.add(ClientMessage(id, Map<String, dynamic>.from(data)));
      }
    }));
    _subs.add(conn.on<dynamic>('close').listen((_) {
      if (_conns.remove(id) != null) _events.add(ClientDisconnected(id));
    }));
    if (conn.open) announce();
  }

  @override
  void send(String connId, Map<String, dynamic> message) {
    final c = _conns[connId];
    if (c != null && c.open) c.send(message);
  }

  @override
  void disconnect(String connId) {
    final c = _conns.remove(connId);
    try {
      c?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _closed = true;
    _watchdog?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final c in _conns.values) {
      try {
        c.dispose();
      } catch (_) {}
    }
    _conns.clear();
    for (final p in _peers) {
      try {
        p.dispose();
      } catch (_) {}
    }
    _peers.clear();
  }
}

class PeerClientLink implements ClientLink {
  Peer? _peer;
  DataConnection? _conn;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _closed = Completer<void>();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _closing = false;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> connect(String roomCode, {void Function()? onWaiting}) async {
    await iceServersReady();
    final peer = Peer(id: '${peerIdPrefix}p-${_randomId()}', options: _options());
    _peer = peer;
    final ready = Completer<void>();
    final serverOpen = Completer<void>();
    // Each try opens a data connection to the host and gives it a few
    // seconds. A host whose app is in the background can't answer, so keep
    // trying until [joinPatience] runs out.
    final deadline = DateTime.now().add(joinPatience);
    var attempt = 0;
    var waitingShown = false;
    LinkException? lastError;
    // Set when the host answered but no network path between the two phones
    // worked (ICE stuck in "checking" or "failed").
    var noPath = false;

    void fail(LinkException e) {
      if (!ready.isCompleted) ready.completeError(e);
    }

    _subs.add(peer.on<dynamic>('error').listen((err) {
      // After we're in, losing the matchmaking server doesn't matter: the
      // data channel to the host keeps working.
      if (ready.isCompleted) return;
      final text = '$err';
      if (text.contains('Could not connect to peer')) {
        // Host not registered right now; the retry loop handles it.
        lastError = LinkException(LinkErrorKind.roomNotFound,
            "I couldn't find a game with the code $roomCode. Double-check the code, and make sure the host still has the game open!");
      } else if (!serverOpen.isCompleted || peer.disconnected || peer.destroyed) {
        fail(const LinkException(LinkErrorKind.network,
            "I couldn't connect to the game. Check your internet and try again!"));
      }
    }));
    _subs.add(peer.on<dynamic>('open').listen((_) {
      if (!serverOpen.isCompleted) serverOpen.complete();
    }));

    Future<bool> tryOnce() async {
      attempt++;
      final opened = Completer<bool>();
      final conn = peer.connect(hostPeerId(roomCode),
          options: PeerConnectOption(reliable: true, serialization: SerializationType.JSON));
      RTCIceConnectionState? ice;
      final subs = <StreamSubscription<dynamic>>[
        conn.on<RTCIceConnectionState?>('iceStateChanged').listen((st) {
          ice = st;
          if (verbosePeerLogs) debugPrint('[peer] join attempt $attempt ICE: $st');
        }),
        conn.on<dynamic>('open').listen((_) {
          if (!opened.isCompleted) opened.complete(true);
        }),
        conn.on<dynamic>('data').listen((data) {
          if (data is Map) _messages.add(Map<String, dynamic>.from(data));
        }),
        conn.on<dynamic>('close').listen((_) {
          if (!opened.isCompleted) {
            opened.complete(false);
          } else if (ready.isCompleted) {
            _markClosed();
          }
        }),
      ];
      final gaveUp = ready.future.then((_) => false, onError: (_) => false);
      var ok = await Future.any([
        opened.future,
        Future<bool>.delayed(Duration(seconds: attempt == 1 ? 10 : 7), () => false),
        gaveUp,
      ]);
      // The host answered and the phones are still trying network paths
      // (relays can take a few seconds): give it more time.
      if (!ok && !ready.isCompleted &&
          (ice == RTCIceConnectionState.RTCIceConnectionStateChecking ||
              ice == RTCIceConnectionState.RTCIceConnectionStateConnected ||
              ice == RTCIceConnectionState.RTCIceConnectionStateCompleted)) {
        ok = await Future.any([
          opened.future,
          Future<bool>.delayed(const Duration(seconds: 10), () => false),
          gaveUp,
        ]);
      }
      if (!ok &&
          (ice == RTCIceConnectionState.RTCIceConnectionStateChecking ||
              ice == RTCIceConnectionState.RTCIceConnectionStateFailed)) {
        noPath = true;
      }
      if (ok && !ready.isCompleted) {
        _conn = conn;
        _subs.addAll(subs);
        return true;
      }
      for (final sub in subs) {
        await sub.cancel();
      }
      try {
        conn.dispose();
      } catch (_) {}
      return false;
    }

    () async {
      try {
        await serverOpen.future.timeout(const Duration(seconds: 15));
      } catch (_) {
        fail(const LinkException(LinkErrorKind.network,
            "I couldn't reach the matchmaking server. Check your internet and try again!"));
        return;
      }
      while (!ready.isCompleted && !_closing) {
        if (await tryOnce()) {
          if (!ready.isCompleted) ready.complete();
          return;
        }
        if (ready.isCompleted || _closing) return;
        if (DateTime.now().isAfter(deadline)) {
          fail(noPath
              ? const LinkException(LinkErrorKind.network,
                  "I found the game, but your phone and the host's phone couldn't connect to each other. This usually happens on mobile data or on Wi-Fi that keeps devices apart. Try putting both phones on the same Wi-Fi, or switch the host to mobile data, and join again!")
              : lastError ??
              LinkException(LinkErrorKind.timeout,
                  "I couldn't reach the game $roomCode. Make sure the host has the game open. Some networks (like mobile data or school Wi-Fi) block direct connections, so trying another network can help too!"));
          return;
        }
        if (!waitingShown) {
          waitingShown = true;
          onWaiting?.call();
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      fail(const LinkException(LinkErrorKind.network, 'Stopped joining.'));
    }();

    try {
      await ready.future;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  void _markClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  void send(Map<String, dynamic> message) {
    final c = _conn;
    if (c != null && c.open) c.send(message);
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      _conn?.dispose();
    } catch (_) {}
    try {
      _peer?.dispose();
    } catch (_) {}
    _markClosed();
  }
}
