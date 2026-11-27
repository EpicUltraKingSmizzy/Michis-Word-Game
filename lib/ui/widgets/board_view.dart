import 'package:material_ui/material_ui.dart';

import '../../logic/board.dart';
import '../theme.dart';

/// How a tile is drawn. [missed] is the grey-silver used to trace words the
/// player missed at the end of a solo round.
enum TileLook { normal, selected, good, bad, dim, missed }

/// Draws a board of rounded letter tiles with an optional connector line.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.board,
    this.looks = const {},
    this.line = const [],
    this.lineColor = MwgColors.pink,
    this.gapFraction = 0.11,
  });

  final Board board;
  final Map<int, TileLook> looks;

  /// Tiles joined by the connector line, in order.
  final List<int> line;
  final Color lineColor;
  final double gapFraction;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final side = c.maxWidth;
        final cell = side / board.size;
        final gap = cell * gapFraction;
        final tile = cell - gap;
        Rect rectFor(int i) =>
            Rect.fromLTWH(board.col(i) * cell + gap / 2, board.row(i) * cell + gap / 2, tile, tile);

        return Stack(
          children: [
            for (var i = 0; i < board.length; i++)
              Positioned.fromRect(
                rect: rectFor(i),
                child: _TileBack(look: looks[i] ?? TileLook.normal, size: tile),
              ),
            if (line.length > 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _LinePainter(
                      points: line.map((i) => rectFor(i).center).toList(),
                      color: lineColor,
                      width: tile * 0.2,
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < board.length; i++)
              Positioned.fromRect(
                rect: rectFor(i),
                child: IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: tile * 0.06),
                      child: Text(
                        board.label(i),
                        style: TextStyle(
                          fontFamily: fontTile,
                          fontWeight: FontWeight.w900,
                          fontSize: board.label(i).length > 1 ? tile * 0.42 : tile * 0.55,
                          height: 1,
                          color: (looks[i] == TileLook.good || looks[i] == TileLook.missed) ? MwgColors.tile : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _TileBack extends StatelessWidget {
  const _TileBack({required this.look, required this.size});
  final TileLook look;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (face, edge, outline) = switch (look) {
      TileLook.normal => (MwgColors.tile, MwgColors.tileEdge, null),
      TileLook.selected => (MwgColors.tileSelected, MwgColors.tileSelectedEdge, MwgColors.pink),
      TileLook.good => (MwgColors.green, MwgColors.greenEdge, Colors.white),
      TileLook.bad => (const Color(0xFFB0303C), const Color(0xFF6E1520), MwgColors.orange),
      TileLook.dim => (const Color(0xFF2A0B42), const Color(0xFF1A0629), null),
      TileLook.missed => (MwgColors.silver, MwgColors.silverEdge, Colors.white),
    };
    final r = BorderRadius.circular(size * 0.22);
    final depth = size * 0.07;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(color: edge, borderRadius: r),
      padding: EdgeInsets.only(bottom: depth),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: face,
          borderRadius: r,
          border: outline == null ? null : Border.all(color: outline, width: size * 0.05),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.points, required this.color, required this.width});
  final List<Offset> points;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points || old.color != color || old.width != width;
}
