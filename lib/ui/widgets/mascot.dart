import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Path to the mascot's round face. Swap the file to change the mascot.
const String mascotFaceAsset = 'assets/mascot_face.png';

/// Michi's face in a white ring.
class MascotFace extends StatelessWidget {
  const MascotFace({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFBFE3FA),
        border: Border.all(color: Colors.white, width: size * 0.05),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: ClipOval(
        child: Image.asset(
          mascotFaceAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.face, size: size * 0.7, color: MwgColors.tile),
        ),
      ),
    );
  }
}

/// A system message: a speech bubble coming from Michi's face.
class MascotBubble extends StatelessWidget {
  const MascotBubble({
    super.key,
    required this.text,
    this.faceSize = 56,
    this.child,
    this.bubbleColor = Colors.white,
    this.textColor = MwgColors.tile,
    this.fontSize = 17,
  });

  final String text;
  final double faceSize;
  final Widget? child;
  final Color bubbleColor;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MascotFace(size: faceSize),
        Flexible(
          child: CustomPaint(
            painter: _BubblePainter(bubbleColor),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: uiText(fontSize, weight: FontWeight.w600, color: textColor)),
                  if (child != null) ...[const SizedBox(height: 8), child!],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const tail = 12.0;
    final body = RRect.fromLTRBR(tail, 0, size.width, size.height, const Radius.circular(20));
    final tailPath = Path()
      ..moveTo(tail + 2, size.height - 26)
      ..lineTo(0, size.height - 6)
      ..lineTo(tail + 18, size.height - 10)
      ..close();
    final path = Path.combine(PathOperation.union, Path()..addRRect(body), tailPath);
    canvas.drawShadow(path, Colors.black54, 4, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = MwgColors.tile
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.color != color;
}
