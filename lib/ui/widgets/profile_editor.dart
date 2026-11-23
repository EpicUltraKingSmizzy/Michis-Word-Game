import 'package:material_ui/material_ui.dart';

import '../avatars.dart';
import '../theme.dart';
import 'common.dart';

/// Shows the player's avatar and name with an edit button.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.name, required this.avatar, required this.onEdit, this.caption});
  final String name;
  final int avatar;
  final VoidCallback onEdit;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            AvatarCircle(avatar: avatar, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caption ?? 'You', style: uiText(14, weight: FontWeight.w500, color: Colors.white70)),
                  Text(name, overflow: TextOverflow.ellipsis, style: uiText(24, weight: FontWeight.w700)),
                ],
              ),
            ),
            const PillButton(
              tooltip: 'Edit name and avatar',
              padding: EdgeInsets.all(10),
              child: Icon(Icons.edit_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to change name and avatar. Returns null if cancelled.
Future<(String, int)?> showProfileEditor(BuildContext context, {required String name, required int avatar}) {
  return showDialog<(String, int)>(
    context: context,
    builder: (_) => _ProfileDialog(name: name, avatar: avatar),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.name, required this.avatar});
  final String name;
  final int avatar;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _controller = TextEditingController(text: widget.name);
  late int _avatar = widget.avatar;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, (_controller.text.trim(), _avatar));

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B2A6B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your player', style: uiText(24, weight: FontWeight.w700)),
              const SizedBox(height: 14),
              AvatarCircle(avatar: _avatar, size: 84),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                maxLength: 16,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.words,
                style: uiText(22, weight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Your name',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0x33000000),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < avatarStyles.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _avatar = i),
                      child: Semantics(
                        label: avatarStyles[i].label,
                        selected: i == _avatar,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 120),
                          scale: i == _avatar ? 1.15 : 1,
                          child: Opacity(
                            opacity: i == _avatar ? 1 : 0.7,
                            child: AvatarCircle(avatar: i, size: 48, ring: i == _avatar),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ChunkyButton(label: 'Save', onPressed: _save, height: 54, fontSize: 22),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: uiText(16, color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
