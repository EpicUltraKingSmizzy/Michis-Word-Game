/// Transport-agnostic connection interfaces. The game talks to these, so the
/// session logic can be tested with an in-memory fake.
library;

import 'dart:async';

/// Something went wrong opening or joining a room. [message] is friendly text
/// the mascot can say.
class LinkException implements Exception {
  const LinkException(this.kind, this.message);
  final LinkErrorKind kind;
  final String message;
  @override
  String toString() => 'LinkException($kind): $message';
}

enum LinkErrorKind { roomTaken, roomNotFound, network, timeout }

sealed class HostEvent {
  const HostEvent(this.connId);
  final String connId;
}

class ClientConnected extends HostEvent {
  const ClientConnected(super.connId);
}

class ClientMessage extends HostEvent {
  const ClientMessage(super.connId, this.data);
  final Map<String, dynamic> data;
}

class ClientDisconnected extends HostEvent {
  const ClientDisconnected(super.connId);
}

/// The host side: accepts player connections for a room code.
abstract class HostLink {
  /// Registers the room. Throws [LinkException] (e.g. [LinkErrorKind.roomTaken]).
  Future<void> open(String roomCode);
  Stream<HostEvent> get events;
  void send(String connId, Map<String, dynamic> message);
  void disconnect(String connId);
  Future<void> close();
}

/// A player's connection to a host.
abstract class ClientLink {
  /// Connects to the host of [roomCode]. Throws [LinkException].
  Future<void> connect(String roomCode);
  Stream<Map<String, dynamic>> get messages;

  /// Fires once when the connection to the host is lost.
  Future<void> get closed;
  void send(Map<String, dynamic> message);
  Future<void> close();
}
