import 'dart:ui' show PathMetric;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Dark pill with an hourglass and MM:SS. The white outline drains as the
/// round runs out.
class TimerPill extends StatefulWidget {
  const TimerPill({super.key, required this.end, required this.total});
  final DateTime end;
  final Duration total;

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}))..start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.end.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    final fraction = widget.total.inMilliseconds == 0
        ? 0.0
        : (left.inMilliseconds / widget.total.inMilliseconds).clamp(0.0, 1.0);
    final secs = (left.inMilliseconds / 1000).ceil();
    final label = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final urgent = secs <= 10;
    return CustomPaint(
      foregroundPainter: _DrainPainter(fraction, urgent ? MwgColors.orange : Colors.white),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: const ShapeDecoration(color: MwgColors.pill, shape: StadiumBorder()),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_bottom_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 6),
            Text(label,
                style: uiText(24, weight: FontWeight.w700)
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

class _DrainPainter extends CustomPainter {
  _DrainPainter(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (fraction <= 0) return;
    final r = size.height / 2;
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    // Start at top-centre and run clockwise.
    final full = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: Radius.circular(r - 1.5))
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r - 1.5))
      ..lineTo(rect.center.dx, rect.top);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final PathMetric m in full.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * fraction), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrainPainter old) => old.fraction != fraction || old.color != color;
}
