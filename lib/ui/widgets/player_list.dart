import 'package:material_ui/material_ui.dart';

import '../../logic/models.dart';
import '../avatars.dart';
import '../theme.dart';
import 'common.dart';

/// Everyone in the room, with names and avatars.
class PlayerList extends StatelessWidget {
  const PlayerList({super.key, required this.players, required this.myId, this.onEditMe});
  final List<PlayerInfo> players;
  final String myId;
  final VoidCallback? onEditMe;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Players (${players.length})', style: uiText(20, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final p in players)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: p.id == myId ? onEditMe : null,
                child: Row(
                  children: [
                    AvatarCircle(avatar: p.avatar, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(19, weight: FontWeight.w600),
                      ),
                    ),
                    if (p.isHost) LabelPill('Host', color: MwgColors.gold, fontSize: 13),
                    if (p.id == myId) ...[
                      const SizedBox(width: 6),
                      LabelPill('You', color: MwgColors.mint, fontSize: 13),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact read-only summary of the host's options.
class SettingsSummary extends StatelessWidget {
  const SettingsSummary({super.key, required this.settings});
  final GameSettings settings;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String top, String bottom) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(icon, color: MwgColors.cyan),
                Text(top, style: uiText(20, weight: FontWeight.w700)),
                Text(bottom, style: uiText(13, weight: FontWeight.w500, color: Colors.white70)),
              ],
            ),
          ),
        );
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Host's options", style: uiText(18, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              chip(Icons.grid_view_rounded, settings.gridLabel, settings.gridName),
              const SizedBox(width: 8),
              chip(Icons.short_text_rounded, '${settings.minWordLength}+', 'letters'),
              const SizedBox(width: 8),
              chip(Icons.hourglass_bottom_rounded, settings.durationLabel, 'minutes'),
            ],
          ),
        ],
      ),
    );
  }
}
