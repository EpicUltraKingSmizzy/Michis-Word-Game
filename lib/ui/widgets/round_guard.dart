import 'package:material_ui/material_ui.dart';

import '../../platform/round_guard.dart' as guard;
import '../../state/app_state.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'common.dart';

/// Asks before leaving a round, then leaves the session the normal way (a
/// host ends the game for everyone; a player leaves the room; a challenge
/// goes back to the start).
Future<bool> confirmQuitRound(BuildContext context, AppState app, GameSession session) async {
  final msg = switch (session) {
    HostSession() => "You're the host, so this ends the game for everyone.",
    SoloSession() => 'Your score for this challenge will be lost.',
    _ => "You'll leave this room. The others keep playing.",
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1B2A6B),
      title: Text('Quit this game?', style: uiText(22, weight: FontWeight.w700)),
      content: Text(msg, style: uiText(16, weight: FontWeight.w500)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep playing')),
        TextButton(
          key: const ValueKey('confirm-quit'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Quit'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await app.leaveSession();
  return true;
}

/// Wraps the countdown and play screens. While [active]:
/// - system back (Android back gesture, browser back / iOS edge swipe) opens
///   the quit dialog instead of leaving,
/// - the platform protections in `platform/round_guard.dart` are on,
/// - a "Quit" button sits in the top-left corner.
class RoundGuard extends StatefulWidget {
  const RoundGuard({super.key, required this.active, required this.app, this.session, required this.child});
  final bool active;
  final AppState app;
  final GameSession? session;
  final Widget child;

  @override
  State<RoundGuard> createState() => _RoundGuardState();
}

class _RoundGuardState extends State<RoundGuard> {
  /// The guard currently in charge. When the app swaps one RoundGuard for
  /// another, the new one starts before the old one is disposed, so only the
  /// current one may switch the protections off.
  static _RoundGuardState? _current;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _current = this;
    guard.setBackHandler(_onBrowserBack);
    guard.setRoundActive(widget.active);
  }

  void _onBrowserBack() {
    if (mounted && widget.active && widget.session != null) _ask();
  }

  @override
  void didUpdateWidget(RoundGuard old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active && _current == this) guard.setRoundActive(widget.active);
  }

  @override
  void dispose() {
    if (_current == this) {
      _current = null;
      guard.setBackHandler(null);
      guard.setRoundActive(false);
    }
    super.dispose();
  }

  Future<void> _ask() async {
    final s = widget.session;
    if (_asking || s == null || !mounted) return;
    _asking = true;
    try {
      await confirmQuitRound(context, widget.app, s);
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active && widget.session != null;
    return PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && active) _ask();
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (active)
            Positioned(
              left: 12,
              top: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PillButton(
                    key: const ValueKey('quit-round'),
                    tooltip: 'Quit game',
                    onTap: _ask,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.close_rounded),
                      SizedBox(width: 4),
                      Text('Quit'),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
