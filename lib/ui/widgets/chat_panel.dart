import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/chat.dart';
import '../../state/session.dart';
import '../avatars.dart';
import '../theme.dart';
import 'common.dart';

/// Longest side of photos sent in chat, and of their thumbnails.
const int chatPhotoSize = 800;
const int chatThumbSize = 160;

/// Shrinks a photo to at most [chatPhotoSize] px and makes a thumbnail.
/// Returns (photo, thumbnail) as JPEG, or null if it isn't an image.
(Uint8List, Uint8List)? prepareChatPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  img.Image fit(img.Image i, int max) => i.width >= i.height
      ? (i.width > max ? img.copyResize(i, width: max) : i)
      : (i.height > max ? img.copyResize(i, height: max) : i);
  final photo = img.encodeJpg(fit(upright, chatPhotoSize), quality: 72);
  final thumb = img.encodeJpg(fit(upright, chatThumbSize), quality: 60);
  return (photo, thumb);
}

/// The room chat: a messaging-app style list with photos, replies, and
/// emoji reactions (long-press a message).
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.session, this.height = 360});
  final GameSession session;
  final double height;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  ChatMessage? _replyTo;
  bool _sendingPhoto = false;

  GameSession get s => widget.session;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    s.sendChat(t, replyTo: _replyTo);
    _text.clear();
    setState(() => _replyTo = null);
  }

  Future<void> _attach() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: chatPhotoSize.toDouble(),
        maxHeight: chatPhotoSize.toDouble(),
        imageQuality: 75,
      );
      if (file == null) return;
      setState(() => _sendingPhoto = true);
      final bytes = await file.readAsBytes();
      final prepared = await compute(prepareChatPhoto, bytes);
      if (prepared == null) {
        s.say("I couldn't read that picture. Try another one!");
        return;
      }
      s.sendChat(_text.text, image: prepared.$1, thumb: prepared.$2, replyTo: _replyTo);
      _text.clear();
      if (mounted) setState(() => _replyTo = null);
    } catch (e) {
      s.say("I couldn't attach that picture. ($e)");
    } finally {
      if (mounted) setState(() => _sendingPhoto = false);
    }
  }

  Future<void> _menu(ChatMessage m) async {
    HapticFeedback.selectionClick();
    final mine = s.myId;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF241552),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in chatReactions)
                    InkResponse(
                      key: ValueKey('react-$e'),
                      onTap: () => Navigator.pop(ctx, 'react:$e'),
                      radius: 28,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (m.reactions[e]?.contains(mine) ?? false) ? const Color(0x55A6F3FF) : null,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: Colors.white),
                title: Text('Reply', style: uiText(18)),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              if (m.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white),
                  title: Text('Copy text', style: uiText(18)),
                  onTap: () => Navigator.pop(ctx, 'copy'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      s.react(m.id, action.substring(6));
    } else if (action == 'reply') {
      setState(() => _replyTo = m);
      _focus.requestFocus();
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = s.chat;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text('Chat', style: uiText(20, weight: FontWeight.w700)),
          ),
          Container(
            height: widget.height,
            decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(18)),
            child: msgs.isEmpty
                ? Center(
                    child: Text(
                      'Say hi to the room! 👋',
                      style: uiText(16, weight: FontWeight.w500, color: Colors.white60),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[msgs.length - 1 - i];
                      final prev = msgs.length - 2 - i >= 0 ? msgs[msgs.length - 2 - i] : null;
                      return _Bubble(
                        key: ValueKey(m.id),
                        message: m,
                        mine: m.from == s.myId,
                        myId: s.myId,
                        showName: prev == null || prev.from != m.from,
                        onLongPress: () => _menu(m),
                        onReact: (e) => s.react(m.id, e),
                      );
                    },
                  ),
          ),
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: const Color(0x33000000),
                borderRadius: BorderRadius.circular(14),
                border: const Border(left: BorderSide(color: MwgColors.cyan, width: 4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${_replyTo!.name}',
                          style: uiText(13, weight: FontWeight.w700, color: MwgColors.cyan),
                        ),
                        Text(
                          _replyTo!.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: uiText(14, weight: FontWeight.w500, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _RoundIcon(
                tooltip: 'Add a photo',
                icon: _sendingPhoto ? Icons.hourglass_top_rounded : Icons.add_rounded,
                onTap: _sendingPhoto ? null : _attach,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  style: uiText(17, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: uiText(17, weight: FontWeight.w500, color: Colors.white38),
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: const Color(0x33000000),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              _RoundIcon(tooltip: 'Send', icon: Icons.send_rounded, onTap: _send, color: MwgColors.mint),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.tooltip, this.color = MwgColors.cyan});
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: MwgColors.tile, size: 24),
        ),
      ),
    ),
  );
}

String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.mine,
    required this.myId,
    required this.showName,
    required this.onLongPress,
    required this.onReact,
  });
  final ChatMessage message;
  final bool mine;
  final String myId;
  final bool showName;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final bubbleColor = mine ? const Color(0xFF8B5CF6) : const Color(0xFF2B2461);
    final photo = m.image ?? m.thumb;
    final bubble = Semantics(
      container: true,
      onLongPressHint: 'React or reply',
      child: GestureDetector(
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(10),
                    border: const Border(left: BorderSide(color: MwgColors.cyan, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.reply!.name,
                        style: uiText(12, weight: FontWeight.w700, color: MwgColors.cyan),
                      ),
                      Text(
                        m.reply!.text.isEmpty && m.reply!.hasImage ? '📷 Photo' : m.reply!.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(13, weight: FontWeight.w500, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              if (photo != null)
                Padding(
                  padding: EdgeInsets.only(bottom: m.text.isEmpty ? 0 : 6),
                  child: GestureDetector(
                    onTap: () => _showPhoto(context, photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(photo, width: 230, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  ),
                ),
              if (m.text.isNotEmpty) Text(m.text, style: uiText(16, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
    final reactions = m.reactions.entries.where((e) => e.value.isNotEmpty).toList();
    final column = Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showName && !mine)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Text(
              m.name,
              style: uiText(13, weight: FontWeight.w700, color: Colors.white70),
            ),
          ),
        bubble,
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 4,
              children: [
                for (final e in reactions)
                  GestureDetector(
                    onTap: () => onReact(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: e.value.contains(myId) ? const Color(0xFF3B6FD9) : const Color(0xFF1B1446),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text('${e.key} ${e.value.length}', style: uiText(13, weight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
          child: Text(
            _time(m.sentAt),
            style: uiText(11, weight: FontWeight.w500, color: Colors.white38),
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: showName ? 8 : 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            SizedBox(width: 34, child: showName ? AvatarCircle(avatar: m.avatar, size: 30, ring: false) : null),
            const SizedBox(width: 4),
          ],
          Flexible(child: column),
        ],
      ),
    );
  }

  static void _showPhoto(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(child: Center(child: Image.memory(bytes))),
      ),
    );
  }
}
