import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/board.dart';
import '../../logic/path_validation.dart';
import 'board_view.dart';

/// The playable grid: drag across neighbouring tiles, release to submit.
class LetterGrid extends StatefulWidget {
  const LetterGrid({
    super.key,
    required this.board,
    required this.onSubmit,
    this.onPathChanged,
    this.enabled = true,
  });

  final Board board;
  final SubmissionResult Function(List<int> path) onSubmit;
  final ValueChanged<List<int>>? onPathChanged;
  final bool enabled;

  @override
  State<LetterGrid> createState() => _LetterGridState();
}

class _LetterGridState extends State<LetterGrid> {
  final List<int> _path = [];
  int? _pointer;
  List<int> _flash = const [];
  SubmissionResult? _flashKind;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  int? _hit(Offset p, double side) {
    final n = widget.board.size;
    final cell = side / n;
    final col = (p.dx / cell).floor();
    final row = (p.dy / cell).floor();
    if (col < 0 || row < 0 || col >= n || row >= n) return null;
    final center = Offset((col + 0.5) * cell, (row + 0.5) * cell);
    // Only count the middle of a tile so diagonal drags don't clip corners.
    if ((p - center).distance > cell * 0.42) return null;
    return row * n + col;
  }

  void _touch(Offset p, double side) {
    final t = _hit(p, side);
    if (t == null) return;
    if (_path.isNotEmpty && t == _path.last) return;
    if (_path.length >= 2 && t == _path[_path.length - 2]) {
      setState(() => _path.removeLast());
      HapticFeedback.selectionClick();
      widget.onPathChanged?.call(List.of(_path));
      return;
    }
    if (!canExtendPath(widget.board, _path, t)) return;
    setState(() {
      _flash = const [];
      _flashKind = null;
      _path.add(t);
    });
    HapticFeedback.lightImpact();
    widget.onPathChanged?.call(List.of(_path));
  }

  void _release() {
    _pointer = null;
    if (_path.isEmpty) return;
    final path = List.of(_path);
    final result = widget.onSubmit(path);
    if (result == SubmissionResult.added) HapticFeedback.heavyImpact();
    _flashTimer?.cancel();
    setState(() {
      _path.clear();
      _flash = path;
      _flashKind = result;
    });
    widget.onPathChanged?.call(const []);
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() {
          _flash = const [];
          _flashKind = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final looks = <int, TileLook>{};
    List<int> line = _path;
    if (_path.isNotEmpty) {
      for (final t in _path) {
        looks[t] = TileLook.selected;
      }
    } else if (_flash.isNotEmpty) {
      line = _flash;
      switch (_flashKind) {
        case SubmissionResult.added:
          for (final t in _flash) {
            looks[t] = TileLook.good;
          }
        case SubmissionResult.tooShort:
          for (final t in _flash) {
            looks[t] = TileLook.selected;
          }
          looks[_flash.first] = TileLook.bad;
        default:
          for (final t in _flash) {
            looks[t] = TileLook.selected;
          }
      }
    }
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final side = c.maxWidth;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (!widget.enabled || _pointer != null) return;
            _pointer = e.pointer;
            _path.clear();
            _touch(e.localPosition, side);
          },
          onPointerMove: (e) {
            if (e.pointer != _pointer || !widget.enabled) return;
            _touch(e.localPosition, side);
          },
          onPointerUp: (e) {
            if (e.pointer == _pointer) _release();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pointer) _release();
          },
          child: BoardView(
            board: widget.board,
            looks: looks,
            line: line,
            lineColor: _flashKind == SubmissionResult.added && _path.isEmpty
                ? Colors.white
                : const Color(0xFFFFC2EC),
          ),
        );
      }),
    );
  }
}
