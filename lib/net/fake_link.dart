/// In-memory links used by tests (and handy for local experiments).
library;

import 'dart:async';
import 'dart:convert';

import 'link.dart';

class FakeNetwork {
  /// With [latency], every message is delivered asynchronously after the
  /// returned delay (order per sender/receiver pair is kept, like a real data
  /// channel). Without it, delivery is synchronous.
  FakeNetwork({this.latency});
  final Duration Function()? latency;
  final Map<String, FakeHostLink> hosts = {};
  final Map<String, Future<void>> _lanes = {};

  void deliver(String lane, void Function() f) {
    final l = latency;
    if (l == null) return f();
    final prev = _lanes[lane] ?? Future<void>.value();
    _lanes[lane] = prev.then((_) => Future<void>.delayed(l(), f));
  }
}

class FakeHostLink implements HostLink {
  FakeHostLink(this.network);
  final FakeNetwork network;
  final _events = StreamController<HostEvent>.broadcast(sync: true);
  final Map<String, FakeClientLink> clients = {};
  String? code;

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> open(String roomCode) async {
    if (network.hosts.containsKey(roomCode)) {
      throw const LinkException(LinkErrorKind.roomTaken, 'taken');
    }
    code = roomCode;
    network.hosts[roomCode] = this;
  }

  void _attach(String id, FakeClientLink c) {
    clients[id] = c;
    network.deliver('up:$id', () => _events.add(ClientConnected(id)));
  }

  void fromClient(String id, Map<String, dynamic> m) {
    final copy = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
    network.deliver('up:$id', () {
      if (clients.containsKey(id)) _events.add(ClientMessage(id, copy));
    });
  }

  void clientLeft(String id) {
    if (clients.remove(id) != null) network.deliver('up:$id', () => _events.add(ClientDisconnected(id)));
  }

  @override
  void send(String connId, Map<String, dynamic> message) {
    final c = clients[connId];
    if (c == null) return;
    final copy = jsonDecode(jsonEncode(message)) as Map<String, dynamic>;
    network.deliver('down:$connId', () => c._deliver(copy));
  }

  @override
  void disconnect(String connId) => clients.remove(connId)?._drop();

  @override
  Future<void> close() async {
    network.hosts.remove(code);
    for (final c in clients.values.toList()) {
      c._drop();
    }
    clients.clear();
  }
}

class FakeClientLink implements ClientLink {
  FakeClientLink(this.network, this.id);
  final FakeNetwork network;
  final String id;
  FakeHostLink? _host;
  final _messages = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _closed = Completer<void>();

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> connect(String roomCode, {void Function()? onWaiting}) async {
    if (network.latency != null) await Future<void>.delayed(network.latency!());
    final h = network.hosts[roomCode];
    if (h == null) throw const LinkException(LinkErrorKind.roomNotFound, 'no room');
    _host = h;
    h._attach(id, this);
  }

  void _deliver(Map<String, dynamic> m) => _messages.add(m);
  void _drop() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  void send(Map<String, dynamic> message) => _host?.fromClient(id, message);

  @override
  Future<void> close() async {
    _host?.clientLeft(id);
    _drop();
  }
}
