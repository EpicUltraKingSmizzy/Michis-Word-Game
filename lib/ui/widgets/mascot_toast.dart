import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'mascot.dart';

/// Shows system messages as speech bubbles from Michi at the bottom of the
/// screen, one at a time.
class MascotToastHost extends StatefulWidget {
  const MascotToastHost({super.key, required this.messages, required this.child});
  final Stream<String> messages;
  final Widget child;

  @override
  State<MascotToastHost> createState() => _MascotToastHostState();
}

class _MascotToastHostState extends State<MascotToastHost> {
  final List<String> _queue = [];
  String? _current;
  Timer? _timer;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.messages.listen((m) {
      if (_current == m || _queue.contains(m)) return;
      _queue.add(m);
      _next();
    });
  }

  void _next() {
    if (_current != null || _queue.isEmpty) return;
    final m = _queue.removeAt(0);
    setState(() => _current = m);
    final ms = (2200 + m.length * 45).clamp(2500, 7000);
    _timer = Timer(Duration(milliseconds: ms), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _current = null);
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _next();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) => SlideTransition(
                    position: Tween(begin: const Offset(0, 1.2), end: Offset.zero).animate(a),
                    child: FadeTransition(opacity: a, child: c),
                  ),
                  child: _current == null
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          key: ValueKey(_current),
                          onTap: _dismiss,
                          child: Material(
                            type: MaterialType.transparency,
                            child: MascotBubble(text: _current!),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
