import 'package:material_ui/material_ui.dart';

import '../../state/app_state.dart';
import '../../state/session.dart';
import '../avatars.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/player_list.dart';
import '../widgets/profile_editor.dart';

/// Opened from a "Challenge a friend" link: who sent it, the options, and
/// the scores to beat, then a solo round on the same board.
class ChallengeScreen extends StatelessWidget {
  const ChallengeScreen({super.key, required this.app, required this.session});
  final AppState app;
  final SoloSession session;

  Future<void> _edit(BuildContext context) async {
    final r = await showProfileEditor(context, name: app.name, avatar: app.avatar);
    if (r != null) await app.updateProfile(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final c = session.challenge;
    final from = c.from?.name ?? 'A friend';
    final ranked = List.of(c.players)..sort((a, b) => b.score.compareTo(a.score));
    return GradientScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            PillButton(
              tooltip: 'Back',
              onTap: app.leaveSession,
              child: const Icon(Icons.arrow_back_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          MascotBubble(
            faceSize: 64,
            text: '$from challenged you! Play the exact same grid and see if you can beat '
                '${c.players.length == 1 ? 'their score' : 'everyone'}.',
          ),
          const SizedBox(height: 16),
          SettingsSummary(settings: c.settings),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scores to beat', style: uiText(20, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final p in ranked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        AvatarCircle(avatar: p.avatar, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, overflow: TextOverflow.ellipsis, style: uiText(19)),
                              Text('${p.wordCount} ${p.wordCount == 1 ? 'word' : 'words'}',
                                  style: uiText(13, weight: FontWeight.w500, color: Colors.white70)),
                            ],
                          ),
                        ),
                        LabelPill('${p.score}', color: MwgColors.gold, fontSize: 20),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ProfileCard(name: app.name, avatar: app.avatar, onEdit: () => _edit(context)),
          const SizedBox(height: 18),
          ChunkyButton(label: 'Play', icon: Icons.play_arrow_rounded, onPressed: session.start),
        ],
      ),
    );
  }
}
