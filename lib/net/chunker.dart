/// Splits big messages (photos, long results) into small pieces, because
/// WebRTC data channels can't reliably carry one huge message.
library;

import 'dart:convert';
import 'dart:math';

/// Largest piece of JSON text sent in one data channel message.
const int maxChunkChars = 12000;

final _rng = Random();

/// Returns [message] as-is if it's small, or as a list of `chunk` messages.
List<Map<String, dynamic>> chunkMessage(Map<String, dynamic> message, {int limit = maxChunkChars}) {
  final text = jsonEncode(message);
  if (text.length <= limit) return [message];
  final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 30).toRadixString(36)}';
  final n = (text.length / limit).ceil();
  return [
    for (var i = 0; i < n; i++)
      {'t': 'chunk', 'cid': id, 'i': i, 'n': n, 'd': text.substring(i * limit, min(text.length, (i + 1) * limit))},
  ];
}

/// Collects `chunk` messages back into the original message.
class Reassembler {
  final Map<String, List<String?>> _parts = {};

  /// Feeds one incoming message. Returns the full message when one is
  /// complete (ordinary messages come straight back), otherwise null.
  Map<String, dynamic>? add(Map<String, dynamic> m) {
    if (m['t'] != 'chunk') return m;
    final id = m['cid'], i = m['i'], n = m['n'], d = m['d'];
    if (id is! String || i is! num || n is! num || d is! String || n > 2000) return null;
    final parts = _parts.putIfAbsent(id, () => List<String?>.filled(n.toInt(), null));
    if (i < 0 || i >= parts.length) return null;
    parts[i.toInt()] = d;
    if (parts.any((p) => p == null)) {
      if (_parts.length > 50) _parts.remove(_parts.keys.first); // drop stale partials
      return null;
    }
    _parts.remove(id);
    final decoded = jsonDecode(parts.join());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }
}
