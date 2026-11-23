/// In-memory links used by tests (and handy for local experiments).
library;

import 'dart:async';
import 'dart:convert';

import 'link.dart';

class FakeNetwork {
  final Map<String, FakeHostLink> hosts = {};
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
    _events.add(ClientConnected(id));
  }

  void fromClient(String id, Map<String, dynamic> m) =>
      _events.add(ClientMessage(id, jsonDecode(jsonEncode(m)) as Map<String, dynamic>));

  void clientLeft(String id) {
    if (clients.remove(id) != null) _events.add(ClientDisconnected(id));
  }

  @override
  void send(String connId, Map<String, dynamic> message) =>
      clients[connId]?._deliver(jsonDecode(jsonEncode(message)) as Map<String, dynamic>);

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
  Future<void> connect(String roomCode) async {
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
