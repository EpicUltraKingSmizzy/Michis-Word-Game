/// Lobby chat messages.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The emoji players can react with.
const List<String> chatReactions = ['❤️', '😂', '😮', '😢', '👍', '👎'];

/// How many recent messages a player gets when they join.
const int chatHistoryLimit = 50;

/// In the history sent to new players, only this many of the most recent
/// photos are sent full size; older ones arrive as thumbnails.
const int chatHistoryFullImages = 6;

/// A short quote of the message being replied to.
class ChatReply {
  const ChatReply({required this.id, required this.name, required this.text, this.hasImage = false});

  factory ChatReply.fromJson(Map<String, dynamic> j) => ChatReply(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        text: j['text'] as String? ?? '',
        hasImage: j['img'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String text;
  final bool hasImage;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'text': text, 'img': hasImage};
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.from,
    required this.name,
    required this.avatar,
    required this.text,
    required this.sentAt,
    this.image,
    this.thumb,
    this.reply,
    Map<String, List<String>>? reactions,
  }) : reactions = reactions ?? {};

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        from: j['from'] as String,
        name: j['name'] as String? ?? 'Player',
        avatar: (j['avatar'] as num?)?.toInt() ?? 0,
        text: j['text'] as String? ?? '',
        sentAt: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num?)?.toInt() ?? 0),
        image: _bytes(j['img']),
        thumb: _bytes(j['thumb']),
        reply: j['reply'] == null ? null : ChatReply.fromJson(Map<String, dynamic>.from(j['reply'] as Map)),
        reactions: reactionsFromJson(j['r']),
      );

  final String id;

  /// Player id of the sender.
  final String from;
  final String name;
  final int avatar;
  final String text;
  final DateTime sentAt;

  /// JPEG photo (about 800px), if any. May be missing for old history
  /// entries, in which case [thumb] is shown.
  final Uint8List? image;
  final Uint8List? thumb;
  final ChatReply? reply;

  /// Emoji -> ids of players who reacted with it.
  Map<String, List<String>> reactions;

  bool get hasImage => image != null || thumb != null;

  /// Short text for reply quotes and notifications.
  String get snippet {
    final t = text.trim();
    if (t.isEmpty) return hasImage ? '📷 Photo' : '';
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }

  Map<String, dynamic> toJson({bool includeImage = true}) => {
        'id': id,
        'from': from,
        'name': name,
        'avatar': avatar,
        'text': text,
        'ts': sentAt.millisecondsSinceEpoch,
        if (includeImage && image != null) 'img': base64Encode(image!),
        if (thumb != null) 'thumb': base64Encode(thumb!),
        if (reply != null) 'reply': reply!.toJson(),
        if (reactions.isNotEmpty) 'r': reactions,
      };

  static Uint8List? _bytes(Object? o) => o is String && o.isNotEmpty ? base64Decode(o) : null;

  static Map<String, List<String>> reactionsFromJson(Object? o) {
    if (o is! Map) return {};
    return {
      for (final e in o.entries)
        if (e.value is List && (e.value as List).isNotEmpty) '${e.key}': (e.value as List).map((x) => '$x').toList(),
    };
  }
}

/// Toggles [playerId]'s [emoji] reaction on [m]. A player has at most one
/// reaction per message: picking a new emoji replaces the old one.
void toggleReaction(ChatMessage m, String playerId, String emoji) {
  final had = m.reactions[emoji]?.contains(playerId) ?? false;
  for (final list in m.reactions.values) {
    list.remove(playerId);
  }
  if (!had) m.reactions.putIfAbsent(emoji, () => []).add(playerId);
  m.reactions.removeWhere((_, v) => v.isEmpty);
}

/// History for a new player: the last [chatHistoryLimit] messages, with only
/// the newest [chatHistoryFullImages] photos sent full size.
List<Map<String, dynamic>> chatHistoryJson(List<ChatMessage> chat) {
  final recent = chat.length > chatHistoryLimit ? chat.sublist(chat.length - chatHistoryLimit) : chat;
  var fullLeft = chatHistoryFullImages;
  final out = <Map<String, dynamic>>[];
  for (final m in recent.reversed) {
    final full = m.image != null && fullLeft > 0;
    if (full) fullLeft--;
    out.add(m.toJson(includeImage: full || m.thumb == null));
  }
  return out.reversed.toList();
}
