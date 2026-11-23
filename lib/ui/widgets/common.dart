import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Full-screen gradient with content limited to a phone-ish width.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({super.key, required this.child, this.gradient = gameGradient});
  final Widget child;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Small dark-purple pill used in the top bar.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.child, this.onTap, this.tooltip, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: MwgColors.pill,
      shape: const StadiumBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: IconTheme(
            data: const IconThemeData(color: Colors.white, size: 22),
            child: DefaultTextStyle(style: uiText(16), child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Big chunky button with a dark outline and a pressed-down effect.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = MwgColors.mint,
    this.textColor = MwgColors.tile,
    this.icon,
    this.height = 64,
    this.fontSize = 26,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final double height;
  final double fontSize;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? widget.color : widget.color.withValues(alpha: 0.45);
    const depth = 6.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          height: widget.height + depth,
          child: Stack(
            children: [
              Positioned.fill(
                top: depth,
                child: Container(
                  decoration: BoxDecoration(
                    color: MwgColors.tile,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                left: 0,
                right: 0,
                top: _down ? depth : 0,
                height: widget.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: MwgColors.tile, width: 3.5),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: widget.textColor, size: widget.fontSize * 1.1),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: uiText(widget.fontSize, weight: FontWeight.w700, color: widget.textColor),
                        ),
                      ),
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
}

/// Translucent dark-blue rounded card.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? MwgColors.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: MwgColors.cardBorder, width: 1.5),
      ),
      child: child,
    );
  }
}

/// Big bubble letters: white fill with a thick dark outline.
class BubbleText extends StatelessWidget {
  const BubbleText(this.text, {super.key, this.size = 48, this.fill = Colors.white, this.stroke = MwgColors.tile, this.strokeWidth});
  final String text;
  final double size;
  final Color fill;
  final Color stroke;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final sw = strokeWidth ?? size * 0.16;
    final style = TextStyle(fontFamily: fontUi, fontWeight: FontWeight.w700, fontSize: size, height: 1.05);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(text,
            textAlign: TextAlign.center,
            style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = sw
                  ..strokeJoin = StrokeJoin.round
                  ..color = stroke)),
        Text(text, textAlign: TextAlign.center, style: style.copyWith(color: fill)),
      ],
    );
  }
}

/// Rounded label pill (e.g. "Added", "Too short", "RAD +1").
class LabelPill extends StatelessWidget {
  const LabelPill(this.text, {super.key, required this.color, this.textColor = MwgColors.tile, this.fontSize = 18});
  final String text;
  final Color color;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.9, vertical: fontSize * 0.3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MwgColors.tile, width: 2.5),
      ),
      child: Text(text, style: uiText(fontSize, weight: FontWeight.w700, color: textColor)),
    );
  }
}

String placeLabel(int place) => switch (place) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${place}th',
    };
