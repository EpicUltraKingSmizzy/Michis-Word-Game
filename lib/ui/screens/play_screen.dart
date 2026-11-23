import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../logic/models.dart';
import '../../logic/path_validation.dart';
import '../../state/app_state.dart';
import '../../state/session.dart';
import '../avatars.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/letter_grid.dart';
import '../widgets/mascot.dart';
import '../widgets/timer_pill.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.app, required this.session});
  final AppState app;
  final GameSession session;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  String _current = '';
  String _lastWord = '';
  SubmissionResult? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  SubmissionResult _submit(List<int> path) {
    final s = widget.session;
    final result = s.submitPath(path);
    if (result == SubmissionResult.invalidPath) return result;
    _feedbackTimer?.cancel();
    setState(() {
      _feedback = result;
      _lastWord = s.board!.wordForPath(path).toUpperCase();
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _feedback = null);
    });
    return result;
  }

  void _showFound() {
    final words = widget.session.foundOrder.reversed.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B2A6B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your words (${words.length})', style: uiText(22, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (words.isEmpty)
                const MascotBubble(text: 'Nothing yet! Drag across the letters to make a word.')
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final w in words)
                          LabelPill('${w.toUpperCase()} +${wordPoints(w)}', color: MwgColors.mint, fontSize: 15),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final board = s.board!;
    final playing = s.phase == SessionPhase.playing;
    final timesUp = s.phase == SessionPhase.waitingForResults;
    final points = s.foundWords.fold<int>(0, (sum, w) => sum + wordPoints(w));

    final (pillText, pillColor, pillTextColor) = switch (_feedback) {
      SubmissionResult.added => ('Added', MwgColors.mint, MwgColors.tile),
      SubmissionResult.tooShort => ('Too short', MwgColors.orange, Colors.white),
      SubmissionResult.alreadyFound => ('Already found', MwgColors.gold, MwgColors.tile),
      SubmissionResult.notAWord => ('Not a word', MwgColors.red, Colors.white),
      _ => ('', Colors.transparent, Colors.white),
    };
    final shownWord = _current.isNotEmpty ? _current : (_feedback != null ? _lastWord : '');

    return GradientScaffold(
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PillButton(
                    tooltip: 'Leave game',
                    onTap: () => _confirmLeave(context),
                    child: const Icon(Icons.close_rounded),
                  ),
                  const SizedBox(width: 10),
                  PillButton(
                    padding: const EdgeInsets.all(4),
                    child: AvatarCircle(avatar: widget.app.avatar, size: 32, ring: false),
                  ),
                  const SizedBox(width: 10),
                  PillButton(
                    tooltip: 'Your words',
                    onTap: _showFound,
                    child: const Icon(Icons.menu_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (s.playEnd != null)
                TimerPill(end: s.playEnd!, total: Duration(seconds: s.roundSettings.durationSeconds)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
              SizedBox(
                height: 46,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: _feedback == null
                      ? const SizedBox.shrink()
                      : LabelPill(pillText, key: ValueKey('$_feedback$_lastWord'), color: pillColor, textColor: pillTextColor, fontSize: 22),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: shownWord.isEmpty ? 0 : 1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 120, minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  decoration: BoxDecoration(
                    color: MwgColors.pill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    shownWord.isEmpty ? ' ' : shownWord,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: fontTile, fontWeight: FontWeight.w900, fontSize: 32, color: Colors.white, letterSpacing: 2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: LetterGrid(
                  key: ValueKey(board),
                  board: board,
                  enabled: playing,
                  onSubmit: _submit,
                  onPathChanged: (p) => setState(() => _current = board.wordForPath(p).toUpperCase()),
                ),
              ),
              ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                  '${s.foundWords.length} ${s.foundWords.length == 1 ? 'word' : 'words'} · '
                  '$points ${points == 1 ? 'point' : 'points'}',
                  style: uiText(18, weight: FontWeight.w600)),
              const SizedBox(height: 16),
            ],
          ),
          if (timesUp)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x99101A4A),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TimesUpBanner(),
                        const SizedBox(height: 24),
                        MascotBubble(
                            text: s.isHost ? 'Tallying up everyone\'s words…' : 'Waiting for the host to tally the scores…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2A6B),
        title: Text('Leave the game?', style: uiText(22, weight: FontWeight.w700)),
        content: Text(
            widget.session.isHost ? "You're the host, so this ends the game for everyone." : "You'll leave this room.",
            style: uiText(16, weight: FontWeight.w500)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep playing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) await widget.app.leaveSession();
  }
}

/// "Time's up!" with an hourglass.
class TimesUpBanner extends StatelessWidget {
  const TimesUpBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: MwgColors.pill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_bottom_rounded, color: MwgColors.gold, size: 38),
          const SizedBox(width: 8),
          BubbleText("Time's up!", size: 40, fill: MwgColors.gold),
        ],
      ),
    );
  }
}
