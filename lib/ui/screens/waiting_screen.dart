import 'package:material_ui/material_ui.dart';

import '../../state/app_state.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/player_list.dart';
import '../widgets/profile_editor.dart';

/// A player's waiting room between rounds.
class WaitingScreen extends StatelessWidget {
  const WaitingScreen({super.key, required this.app, required this.session});
  final AppState app;
  final GameSession session;

  Future<void> _edit(BuildContext context) async {
    final r = await showProfileEditor(context, name: app.name, avatar: app.avatar);
    if (r != null) await app.updateProfile(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final host = session.players.where((p) => p.isHost).firstOrNull;
    final hostName = host?.name ?? 'the host';
    return GradientScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              PillButton(
                tooltip: 'Leave room',
                onTap: app.leaveSession,
                child: const Icon(Icons.logout_rounded),
              ),
              const Spacer(),
              PillButton(child: Text('Room ${session.roomCode}')),
            ],
          ),
          const SizedBox(height: 18),
          MascotBubble(
            faceSize: 64,
            text: session.roundInProgress
                ? "A round is already underway. Hang tight, you'll be in the next one!"
                : "You're in! Waiting for $hostName to start the game…",
          ),
          const SizedBox(height: 16),
          ProfileCard(name: app.name, avatar: app.avatar, onEdit: () => _edit(context)),
          const SizedBox(height: 14),
          SettingsSummary(settings: session.settings),
          const SizedBox(height: 14),
          PlayerList(players: session.players, myId: session.myId, onEditMe: () => _edit(context)),
          const SizedBox(height: 18),
          Center(
            child: Text('Get your fingers ready!',
                style: uiText(16, weight: FontWeight.w500, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
