/// PeerJS (via `peerdart`) implementation of the links.
///
/// Matchmaking goes through the free public PeerJS server (0.peerjs.com).
/// After that, players talk to the host directly over WebRTC data channels.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:peerdart/peerdart.dart';

import '../logic/room_code.dart';
import 'link.dart';

/// ICE servers: Google's public STUN, plus the PeerJS project's free public
/// TURN relay as a best-effort fallback for strict networks.
const Map<String, dynamic> iceConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': [
        'turn:eu-0.turn.peerjs.com:3478',
        'turn:us-0.turn.peerjs.com:3478',
      ],
      'username': 'peerjs',
      'credential': 'peerjsp',
    },
  ],
  'sdpSemantics': 'unified-plan',
};

PeerOptions _options() => PeerOptions(
      config: iceConfig,
      debug: kDebugMode ? LogLevel.Errors : LogLevel.Disabled,
    );

String _randomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
}

class PeerHostLink implements HostLink {
  Peer? _peer;
  final _events = StreamController<HostEvent>.broadcast();
  final _conns = <String, DataConnection>{};
  final _subs = <StreamSubscription<dynamic>>[];
  bool _closed = false;

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> open(String roomCode) async {
    final peer = Peer(id: hostPeerId(roomCode), options: _options());
    _peer = peer;
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
      } else if (!_closed && peer.disconnected && !peer.destroyed) {
        // Lost the matchmaking server; existing players stay connected.
        // Try to re-register so late arrivals can still join.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (!_closed && peer.disconnected && !peer.destroyed) {
            try {
              peer.reconnect();
            } catch (_) {}
          }
        });
      }
    }));
    _subs.add(peer.on<DataConnection>('connection').listen(_accept));
    try {
      await ready.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await close();
      throw const LinkException(LinkErrorKind.timeout,
          'The matchmaking server is taking too long. Try again in a moment!');
    } catch (_) {
      _disposePeer();
      rethrow;
    }
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

  void _disposePeer() {
    try {
      _peer?.dispose();
    } catch (_) {}
    _peer = null;
  }

  @override
  Future<void> close() async {
    _closed = true;
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
    _disposePeer();
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
  Future<void> connect(String roomCode) async {
    final peer = Peer(id: '${peerIdPrefix}p-${_randomId()}', options: _options());
    _peer = peer;
    final ready = Completer<void>();

    void fail(LinkException e) {
      if (!ready.isCompleted) ready.completeError(e);
    }

    _subs.add(peer.on<dynamic>('error').listen((err) {
      // After we're in, losing the matchmaking server doesn't matter: the
      // data channel to the host keeps working.
      if (ready.isCompleted) return;
      final text = '$err';
      if (text.contains('Could not connect to peer')) {
        fail(LinkException(LinkErrorKind.roomNotFound,
            "I couldn't find a game with the code $roomCode. Double-check the code, and make sure the host still has the game open!"));
      } else {
        fail(const LinkException(LinkErrorKind.network,
            "I couldn't connect to the game. Check your internet and try again!"));
      }
    }));

    _subs.add(peer.on<dynamic>('open').listen((_) {
      final conn = peer.connect(hostPeerId(roomCode),
          options: PeerConnectOption(reliable: true, serialization: SerializationType.JSON));
      _conn = conn;
      _subs.add(conn.on<dynamic>('open').listen((_) {
        if (!ready.isCompleted) ready.complete();
      }));
      _subs.add(conn.on<dynamic>('data').listen((data) {
        if (data is Map) _messages.add(Map<String, dynamic>.from(data));
      }));
      _subs.add(conn.on<dynamic>('close').listen((_) {
        fail(const LinkException(LinkErrorKind.network,
            "The connection to the host dropped before we got in. Try again!"));
        _markClosed();
      }));
    }));

    try {
      await ready.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      await close();
      throw LinkException(LinkErrorKind.timeout,
          "I couldn't reach the game $roomCode. Some networks (like mobile data or school Wi-Fi) block direct connections. Try another network, or check the code!");
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
