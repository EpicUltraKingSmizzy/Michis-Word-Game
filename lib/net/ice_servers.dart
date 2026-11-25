/// Which STUN/TURN servers WebRTC uses to connect players to the host.
///
/// Background: phones usually can't talk to each other directly. STUN lets a
/// phone learn its public address so a direct path can be punched through the
/// router. That works on most home Wi-Fi, but not when a phone is on mobile
/// data behind a carrier NAT, or on Wi-Fi that isolates devices. Then the
/// only way through is a TURN *relay*.
///
/// The PeerJS project's free relay (eu-0/us-0.turn.peerjs.com), which the app
/// used until 0.2.0, was shut down in 2025: those names no longer even
/// resolve. Free no-signup relays don't exist anymore, so a relay has to come
/// from an account (e.g. Metered's free 20 GB/month "Open Relay" plan, or
/// Cloudflare Realtime TURN). To avoid baking secrets into the app, the relay
/// list is read at startup from a small JSON file on the website:
///
///   https://michiswordgame.github.io/ice.json
///
/// Supported shapes:
///   {"iceServers": [{"urls": "turn:...", "username": "...", "credential": "..."}]}
///   {"credentialsUrl": "https://YOUR-APP.metered.live/api/v1/turn/credentials?apiKey=..."}
///     (the URL must return a JSON list of iceServers, as Metered's API does)
///
/// Both can be combined. Build with `--dart-define=MWG_ICE_URL=...` to read
/// a different file. `?ice=relay` in the web URL forces relay-only, to test a
/// TURN setup.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Free public STUN servers (no account needed). Several, so one being down
/// or blocked doesn't matter.
const List<Map<String, dynamic>> stunServers = [
  {
    'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
  },
  {'urls': 'stun:stun.cloudflare.com:3478'},
];

const String _iceUrl = String.fromEnvironment(
  'MWG_ICE_URL',
  defaultValue: 'https://michiswordgame.github.io/ice.json',
);

/// Relay-only mode, for testing a TURN setup (`?ice=relay` on the web).
bool forceRelay = false;

List<Map<String, dynamic>> _relays = const [];
Future<void>? _loading;

/// TURN servers loaded from the website (empty if none configured).
List<Map<String, dynamic>> get relayServers => _relays;

/// Starts loading the relay list. Safe to call more than once.
Future<void> loadIceServers({http.Client? client}) {
  return _loading ??= _load(client ?? http.Client());
}

/// Waits (briefly) for the relay list, so the first connection can use it.
Future<void> iceServersReady({Duration wait = const Duration(seconds: 3)}) async {
  try {
    await loadIceServers().timeout(wait);
  } catch (_) {}
}

Future<void> _load(http.Client client) async {
  try {
    final res = await client
        .get(Uri.parse(_iceUrl).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch ~/ 60000}'}))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return;
    final relays = <Map<String, dynamic>>[];
    final body = jsonDecode(res.body);
    if (body is Map) {
      relays.addAll(parseIceServers(body['iceServers']));
      final cred = body['credentialsUrl'];
      if (cred is String && cred.startsWith('https://')) {
        final r2 = await client.get(Uri.parse(cred)).timeout(const Duration(seconds: 4));
        if (r2.statusCode == 200) {
          final b2 = jsonDecode(r2.body);
          relays.addAll(parseIceServers(b2 is Map ? b2['iceServers'] : b2));
        }
      }
    }
    _relays = relays;
    if (kDebugMode || relays.isNotEmpty) {
      debugPrint('[ice] ${relays.length} relay server entr${relays.length == 1 ? 'y' : 'ies'} loaded');
    }
  } catch (e) {
    debugPrint('[ice] no relay list: $e');
  }
}

/// Keeps only well-formed STUN/TURN entries.
List<Map<String, dynamic>> parseIceServers(Object? raw) {
  final list = raw is List ? raw : (raw is Map ? [raw] : const []);
  final out = <Map<String, dynamic>>[];
  for (final e in list) {
    if (e is! Map) continue;
    final urls = e['urls'] ?? e['url'];
    final urlList = urls is String ? [urls] : (urls is List ? urls.whereType<String>().toList() : <String>[]);
    final good = urlList.where((u) => u.startsWith('turn:') || u.startsWith('turns:') || u.startsWith('stun:')).toList();
    if (good.isEmpty) continue;
    out.add({
      'urls': good.length == 1 ? good.first : good,
      if (e['username'] is String) 'username': e['username'],
      if (e['credential'] is String) 'credential': e['credential'],
    });
  }
  return out;
}

/// The RTCPeerConnection config for a new connection.
Map<String, dynamic> currentIceConfig() => {
      'iceServers': [...stunServers, ..._relays],
      'sdpSemantics': 'unified-plan',
      if (forceRelay) 'iceTransportPolicy': 'relay',
    };

@visibleForTesting
void resetIceServersForTest() {
  _loading = null;
  _relays = const [];
  forceRelay = false;
}
