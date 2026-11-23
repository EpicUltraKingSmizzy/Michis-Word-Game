import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'link.dart';

const bool localLinkSupported = true;

HostLink createLocalHostLink() => _LocalHostLink();
ClientLink createLocalClientLink() => _LocalClientLink();

String _rid() => List.generate(10, (_) => Random().nextInt(36).toRadixString(36)).join();

web.BroadcastChannel _channel(String code) => web.BroadcastChannel('mwg-local-$code');

void _post(web.BroadcastChannel ch, Map<String, dynamic> m) => ch.postMessage(jsonEncode(m).toJS);

Map<String, dynamic>? _read(web.MessageEvent e) {
  final d = e.data;
  if (d == null || !d.isA<JSString>()) return null;
  return jsonDecode((d as JSString).toDart) as Map<String, dynamic>;
}

class _LocalHostLink implements HostLink {
  web.BroadcastChannel? _ch;
  final _events = StreamController<HostEvent>.broadcast();
  final Set<String> _clients = {};

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> open(String roomCode) async {
    final ch = _channel(roomCode);
    _ch = ch;
    ch.onmessage = ((web.MessageEvent e) {
      final m = _read(e);
      if (m == null || m['to'] != 'host') return;
      final from = m['from'] as String;
      switch (m['kind']) {
        case 'connect':
          _clients.add(from);
          _post(ch, {'kind': 'accept', 'to': from});
          _events.add(ClientConnected(from));
        case 'msg':
          if (_clients.contains(from)) {
            _events.add(ClientMessage(from, Map<String, dynamic>.from(m['data'] as Map)));
          }
        case 'bye':
          if (_clients.remove(from)) _events.add(ClientDisconnected(from));
      }
    }).toJS;
  }

  @override
  void send(String connId, Map<String, dynamic> message) {
    final ch = _ch;
    if (ch != null && _clients.contains(connId)) {
      _post(ch, {'kind': 'msg', 'to': connId, 'data': message});
    }
  }

  @override
  void disconnect(String connId) {
    if (_clients.remove(connId)) _post(_ch!, {'kind': 'bye', 'to': connId});
  }

  @override
  Future<void> close() async {
    final ch = _ch;
    if (ch == null) return;
    for (final c in _clients) {
      _post(ch, {'kind': 'bye', 'to': c});
    }
    _clients.clear();
    ch.close();
    _ch = null;
  }
}

class _LocalClientLink implements ClientLink {
  final String _id = 'local-${_rid()}';
  web.BroadcastChannel? _ch;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _closed = Completer<void>();

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> connect(String roomCode) async {
    final ch = _channel(roomCode);
    _ch = ch;
    final accepted = Completer<void>();
    ch.onmessage = ((web.MessageEvent e) {
      final m = _read(e);
      if (m == null || m['to'] != _id) return;
      switch (m['kind']) {
        case 'accept':
          if (!accepted.isCompleted) accepted.complete();
        case 'msg':
          _messages.add(Map<String, dynamic>.from(m['data'] as Map));
        case 'bye':
          if (!_closed.isCompleted) _closed.complete();
      }
    }).toJS;
    _post(ch, {'kind': 'connect', 'from': _id, 'to': 'host'});
    try {
      await accepted.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      ch.close();
      throw LinkException(LinkErrorKind.roomNotFound, 'No local game with the code $roomCode is open in this browser.');
    }
  }

  @override
  void send(Map<String, dynamic> message) {
    final ch = _ch;
    if (ch != null) _post(ch, {'kind': 'msg', 'from': _id, 'to': 'host', 'data': message});
  }

  @override
  Future<void> close() async {
    final ch = _ch;
    if (ch != null) {
      _post(ch, {'kind': 'bye', 'from': _id, 'to': 'host'});
      ch.close();
      _ch = null;
    }
    if (!_closed.isCompleted) _closed.complete();
  }
}
