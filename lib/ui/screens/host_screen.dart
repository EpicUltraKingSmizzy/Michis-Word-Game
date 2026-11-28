import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../logic/models.dart';
import '../../logic/room_code.dart';
import '../../platform/share.dart';
import '../../state/app_state.dart';
import '../../state/session.dart';
import '../avatars.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/chat_panel.dart';
import '../widgets/player_list.dart';
import '../widgets/profile_editor.dart';

/// The host's room: invite (QR + share), options, players, and Start.
class HostScreen extends StatelessWidget {
  const HostScreen({super.key, required this.app, required this.session});
  final AppState app;
  final HostSession session;

  Future<void> _edit(BuildContext context) async {
    final r = await showProfileEditor(context, name: app.name, avatar: app.avatar);
    if (r != null) await app.updateProfile(r.$1, r.$2);
  }

  Future<void> _share(BuildContext context) async {
    final url = joinUrl(session.roomCode);
    final shared = await shareOrCopy(context,
        text: "Come play Michi's Word Game with me!\n$url", subject: "Join my Michi's Word Game");
    if (!shared) app.say('Invite link copied! Paste it to your friends.');
  }

  @override
  Widget build(BuildContext context) {
    final s = session.settings;
    return GradientScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              PillButton(
                tooltip: 'Close room',
                onTap: () => _confirmLeave(context),
                child: const Icon(Icons.close_rounded),
              ),
              const Spacer(),
              PillButton(
                onTap: () => _edit(context),
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AvatarCircle(avatar: app.avatar, size: 30, ring: false),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(app.name, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InviteCard(code: session.roomCode, onShare: () => _share(context)),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grid Size', style: uiText(20, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final g in GameSettings.gridSizes) ...[
                      Expanded(
                        child: _GridSizeTile(
                          settings: s.copyWith(gridSize: g),
                          selected: s.gridSize == g,
                          onTap: () => session.updateSettings(s.copyWith(gridSize: g)),
                        ),
                      ),
                      if (g != GameSettings.gridSizes.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Text('Shortest Word', style: uiText(20, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final m in GameSettings.minWordLengths) ...[
                      Expanded(
                        child: _ChoiceChip(
                          label: '$m letters',
                          selected: !s.longestOnly && s.minWordLength == m,
                          // Picking a length turns "Longest word only" off.
                          onTap: () => session.updateSettings(s.copyWith(minWordLength: m, longestOnly: false)),
                        ),
                      ),
                      if (m != GameSettings.minWordLengths.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _ChoiceChip(
                  key: const ValueKey('longest-only'),
                  label: 'Longest word only',
                  selected: s.longestOnly,
                  // Any word of 3+ letters can be found in this mode.
                  onTap: () => session.updateSettings(s.copyWith(longestOnly: true, minWordLength: 3)),
                ),
                if (s.longestOnly) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Only your longest word will count towards your score.',
                    key: const ValueKey('longest-only-hint'),
                    textAlign: TextAlign.center,
                    style: uiText(15, weight: FontWeight.w600, color: MwgColors.gold),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('Game Duration', style: uiText(20, weight: FontWeight.w700)),
                    const Spacer(),
                    LabelPill(s.durationLabel, color: MwgColors.cyan, fontSize: 18),
                  ],
                ),
                Slider(
                  value: s.durationSeconds.toDouble(),
                  min: GameSettings.minDuration.toDouble(),
                  max: GameSettings.maxDuration.toDouble(),
                  divisions: (GameSettings.maxDuration - GameSettings.minDuration) ~/ GameSettings.durationStep,
                  label: s.durationLabel,
                  onChanged: (v) => session.updateSettings(s.copyWith(durationSeconds: v.round())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PlayerList(
            players: session.players,
            myId: session.myId,
            presence: session.presence,
            onEditMe: () => _edit(context),
          ),
          const SizedBox(height: 14),
          if (session.players.length < 2)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: MascotBubble(text: 'Waiting for friends to scan the code… or start a solo round to warm up!'),
            ),
          ChunkyButton(
            label: 'Start Game',
            icon: Icons.play_arrow_rounded,
            onPressed: session.canStart ? session.startGame : null,
          ),
          if (session.startBlockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Waiting: ${session.startBlockedReason}',
                textAlign: TextAlign.center,
                style: uiText(15, weight: FontWeight.w600, color: MwgColors.gold),
              ),
            ),
          const SizedBox(height: 18),
          ChatPanel(session: session),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A6B),
        title: Text('Close the room?', style: uiText(22, weight: FontWeight.w700)),
        content: Text('Everyone in the room will be sent home.', style: uiText(16, weight: FontWeight.w500)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close room')),
        ],
      ),
    );
    if (ok == true) await app.leaveSession();
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code, required this.onShare});
  final String code;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          Text('Scan to join!', style: uiText(22, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: MwgColors.tile, width: 4),
            ),
            child: QrImageView(
              data: joinUrl(code),
              size: 200,
              padding: EdgeInsets.zero,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: MwgColors.tile),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square, color: MwgColors.tile),
            ),
          ),
          const SizedBox(height: 12),
          Text('Room code', style: uiText(14, weight: FontWeight.w500, color: Colors.white70)),
          Text(code, style: uiText(42, weight: FontWeight.w700).copyWith(letterSpacing: 8)),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'Share invite link',
            icon: Icons.ios_share_rounded,
            color: MwgColors.cyan,
            height: 52,
            fontSize: 20,
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

class _GridSizeTile extends StatelessWidget {
  const _GridSizeTile({required this.settings, required this.selected, required this.onTap});
  final GameSettings settings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 86,
        decoration: BoxDecoration(
          color: selected ? MwgColors.ribbon : const Color(0x33000000),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(settings.gridLabel, style: uiText(26, weight: FontWeight.w700)),
            Text(settings.gridName, style: uiText(14, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? MwgColors.ribbon : const Color(0x33000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
        ),
        child: Text(label, style: uiText(17, weight: FontWeight.w700)),
      ),
    );
  }
}
