import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/session.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../theme.dart';

/// Big bubbly 3… 2… 1… before the grid appears.
class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key, required this.session});
  final GameSession session;

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}))..start();
  int _lastShown = -1;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.session.countdownStart ?? DateTime.now();
    final elapsed = DateTime.now().difference(start).inMilliseconds.clamp(0, 2999);
    final n = 3 - elapsed ~/ 1000;
    final t = (elapsed % 1000) / 1000;
    if (n != _lastShown) {
      _lastShown = n;
      HapticFeedback.mediumImpact();
    }
    final scale = Curves.elasticOut.transform((t * 1.6).clamp(0, 1)) * (1 - 0.15 * t);
    final colors = [MwgColors.mint, MwgColors.gold, MwgColors.pink];
    return GradientScaffold(
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: MascotBubble(text: 'Get ready to find some words!'),
          ),
          Expanded(
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: BubbleText('$n', size: 180, fill: colors[(3 - n) % 3], strokeWidth: 22),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
