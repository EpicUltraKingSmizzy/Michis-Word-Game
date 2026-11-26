import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/board.dart';
import '../../logic/challenge.dart';
import '../../logic/models.dart';
import '../../logic/replay_order.dart';
import '../../platform/share.dart';
import '../../state/app_state.dart';
import '../../state/profile_store.dart';
import '../../state/session.dart';
import '../avatars.dart';
import '../theme.dart';
import '../widgets/board_view.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import 'play_screen.dart' show TimesUpBanner;

enum _Stage { intro, replay, highlights, longest, winner }

/// End of round: word counts, word-by-word scoring replay, highlights, the
/// longest word on the board, and the winner.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.app, required this.session, required this.results});
  final AppState app;
  final GameSession session;
  final RoundResults results;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  _Stage _stage = _Stage.intro;
  final Map<String, int> _shown = {};
  WordEntry? _entry;
  bool _awarded = false;

  /// The screen is gone; stop everything.
  bool _disposed = false;

  /// "Skip" was pressed: jump past the scoring animation only. The pages
  /// after it (highlights, longest word, winner) are still tapped through.
  bool _skipScoring = false;

  /// Challenge friends whose link only carried a score (no words): their
  /// score can't be replayed word by word, so it shows "???" until scoring
  /// is over.
  late final Set<String> _scoreOnly = {
    if (widget.session is SoloSession)
      for (final p in r.players)
        if (p.player.id != myId && p.words.isEmpty && p.score > 0) p.player.id,
  };
  bool _scoringDone = false;
  final _skipSignal = Completer<void>();
  PersonalRecord? _record;
  final _confetti = ConfettiController(duration: const Duration(seconds: 4));

  RoundResults get r => widget.results;
  String get myId => widget.session.myId;

  @override
  void initState() {
    super.initState();
    for (final p in r.players) {
      _shown[p.player.id] = 0;
    }
    final mine = r.playerById(myId);
    final store = widget.app.store;
    if (mine != null && store != null) {
      store.recordScore(r.settings, mine.score).then((rec) {
        if (mounted) setState(() => _record = rec);
      });
    }
    _run();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_skipSignal.isCompleted) _skipSignal.complete();
    _confetti.dispose();
    super.dispose();
  }

  /// Pauses the scoring animation. False if it should stop (skipped or the
  /// screen went away).
  Future<bool> _wait(int ms) async {
    if (_skipScoring || _disposed) return false;
    await Future.any([Future<void>.delayed(Duration(milliseconds: ms)), _skipSignal.future]);
    return mounted && !_skipScoring && !_disposed;
  }

  Completer<void>? _tapWait;

  /// Waits for the player to tap before moving on (so the highlights, the
  /// longest word, and so on don't fly past).
  Future<bool> _waitTap() async {
    if (_disposed || !mounted) return false;
    final c = _tapWait = Completer<void>();
    setState(() {});
    await c.future;
    if (identical(_tapWait, c)) _tapWait = null;
    if (mounted) setState(() {});
    return mounted && !_disposed;
  }

  /// Skip button: ends the scoring animation and shows the final scores.
  void _skipToEndOfScoring() {
    if (_scoringDone) return;
    setState(() => _skipScoring = true);
    if (!_skipSignal.isCompleted) _skipSignal.complete();
  }

  void _advance() {
    final c = _tapWait;
    if (c != null && !c.isCompleted) {
      HapticFeedback.selectionClick();
      c.complete();
    }
  }

  Future<void> _run() async {
    await _scoring();
    if (_disposed || !mounted) return;
    final skipped = _skipScoring;
    setState(() {
      _scoringDone = true;
      _entry = null;
      for (final p in r.players) {
        _shown[p.player.id] = p.score;
      }
      _stage = _Stage.replay;
    });
    // From here on, players tap through at their own pace. After a skip the
    // final scores are on screen already, so go straight on.
    if (!skipped && !await _waitTap()) return;
    if (!mounted) return;
    setState(() => _stage = _Stage.highlights);
    if (!await _waitTap()) return;
    if (r.longest != null) {
      setState(() => _stage = _Stage.longest);
      if (!await _waitTap()) return;
    }
    _finish();
  }

  /// Time's up + word counts, then the word-by-word replay. Returns early
  /// when skipped.
  Future<void> _scoring() async {
    if (!await _wait(2600)) return;
    setState(() => _stage = _Stage.replay);
    if (!await _wait(400)) return;
    for (final e in r.replay) {
      setState(() {
        _entry = e;
        _awarded = false;
      });
      final hold = replayStepDuration(e).inMilliseconds - 400;
      if (!await _wait(hold)) return;
      setState(() {
        _awarded = true;
        for (final f in e.finders) {
          _shown[f] = (_shown[f] ?? 0) + e.pointsEach;
        }
      });
      if (e.finders.contains(myId)) HapticFeedback.mediumImpact();
      if (!await _wait(400)) return;
    }
    if (r.replay.isEmpty) await _wait(1500);
  }

  void _finish() {
    final c = _tapWait;
    _tapWait = null;
    if (c != null && !c.isCompleted) c.complete();
    if (!mounted || _stage == _Stage.winner) return;
    setState(() {
      for (final p in r.players) {
        _shown[p.player.id] = p.score;
      }
      _stage = _Stage.winner;
    });
    _confetti.play();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_stage) {
      _Stage.intro => _intro(),
      _Stage.replay => _replay(),
      _Stage.highlights => _highlights(),
      _Stage.longest => _longest(),
      _Stage.winner => _winner(),
    };
    return GradientScaffold(
      gradient: resultsGradient,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    PillButton(
                      tooltip: 'Leave room',
                      onTap: widget.app.leaveSession,
                      child: const Icon(Icons.close_rounded),
                    ),
                    const Spacer(),
                    if (!_scoringDone)
                      PillButton(
                        key: const ValueKey('skip-scoring'),
                        tooltip: 'Skip the scoring',
                        onTap: _skipToEndOfScoring,
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Skip'),
                          Icon(Icons.fast_forward_rounded),
                        ]),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _tapWait == null ? null : _advance,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: KeyedSubtree(key: ValueKey('stage-${_stage.name}'), child: body),
                  ),
                ),
              ),
              if (_tapWait != null)
                GestureDetector(
                  onTap: _advance,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    child: _TapHint(),
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              emissionFrequency: 0.06,
              gravity: 0.25,
              colors: const [MwgColors.mint, MwgColors.gold, MwgColors.pink, MwgColors.cyan, Colors.white],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Stage: Time's up + word counts ----
  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Center(child: TimesUpBanner()),
        const SizedBox(height: 18),
        for (final p in r.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlayerBanner(
              player: p.player,
              isMe: p.player.id == myId,
              right: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_scoreOnly.contains(p.player.id) ? '?' : '${p.wordCount}',
                      style: uiText(30, weight: FontWeight.w700)),
                  Text(p.wordCount == 1 ? 'word' : 'words', style: uiText(14, color: Colors.white70)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---- Stage: word-by-word replay ----
  Widget _replay() {
    final e = _entry;
    final leader = _leaderId();
    return LayoutBuilder(builder: (context, c) {
      final gridSide = min(c.maxWidth - 120, c.maxHeight * 0.42).clamp(160.0, 340.0);
      return Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in r.players)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PlayerBanner(
                      compact: true,
                      player: p.player,
                      isMe: p.player.id == myId,
                      crown: p.player.id == leader,
                      flash: _awarded && e != null && e.finders.contains(p.player.id),
                      right: _ScoreBadge(
                        score: _shown[p.player.id] ?? 0,
                        hidden: !_scoringDone && _scoreOnly.contains(p.player.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: e == null
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LabelPill('${e.word.toUpperCase()} +${e.pointsEach}',
                          color: e.isUnique ? MwgColors.gold : MwgColors.mint, fontSize: 22),
                      if (e.isUnique) ...[
                        const SizedBox(width: 8),
                        LabelPill('x2 UNIQUE', color: MwgColors.pink, fontSize: 14),
                      ],
                      const SizedBox(width: 8),
                      for (final f in e.finders.take(4))
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: AvatarCircle(avatar: r.playerById(f)?.player.avatar ?? 0, size: 28, ring: false),
                        ),
                    ],
                  ),
          ),
          SizedBox(
            width: gridSide,
            child: e == null
                ? BoardView(board: r.board, looks: const {}, line: const [])
                : _TracePath(
                    key: ValueKey('trace-${e.word}'),
                    board: r.board,
                    path: e.path,
                    done: _awarded,
                    // Spell the word out during the first part of the step,
                    // so scoring takes no extra time.
                    duration: Duration(
                        milliseconds: ((replayStepDuration(e).inMilliseconds - 400) * 0.8).round()),
                  ),
          ),
          const SizedBox(height: 10),
          const _RulesPanel(),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  String? _leaderId() {
    if (_shown.isEmpty) return null;
    final top = _shown.values.reduce(max);
    if (top == 0) return null;
    final ids = _shown.keys.where((k) => _shown[k] == top).toList();
    return ids.length == 1 ? ids.first : null;
  }

  // ---- Stage: highlights ----
  Widget _highlights() {
    final rec = _record;
    final s = r.settings;
    final items = <Widget>[
      if (rec != null && rec.newOverallBest)
        _Starburst(text: 'Personal best!', sub: '${r.playerById(myId)?.score ?? 0} points (was ${rec.previousBest})')
      else if (rec != null && rec.newConfigBest)
        _Starburst(text: 'Personal best!', sub: 'on ${s.gridLabel} · ${s.durationLabel}'),
      for (final h in r.highlights.where((h) => h.kind == HighlightKind.group)) _Ribbon(highlight: h),
      for (final h in r.highlights.where((h) => h.kind == HighlightKind.player))
        _HighlightCard(highlight: h, mine: h.playerIds.contains(myId), avatars: [
          for (final id in h.playerIds.take(4)) r.playerById(id)?.player.avatar ?? 0,
        ]),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const MascotBubble(text: "Let's look at the highlights!"),
        const SizedBox(height: 14),
        for (var i = 0; i < items.length; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 350 + i * 250),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Opacity(
              opacity: v.clamp(0, 1),
              child: Transform.translate(offset: Offset(0, 30 * (1 - v)), child: child),
            ),
            child: Padding(padding: const EdgeInsets.only(bottom: 10), child: items[i]),
          ),
      ],
    );
  }

  // ---- Stage: longest word on the board ----
  Widget _longest() {
    final l = r.longest!;
    final String text;
    if (l.allFound) {
      final names = l.foundBy.map((id) => r.playerById(id)?.player.name ?? '?').toList();
      final who = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
      text = l.allLongest.length == 1
          ? 'Wow! $who found the longest word on the board: ${l.word.toUpperCase()}!'
          : 'Wow! $who found every one of the longest words: ${l.allLongest.map((w) => w.toUpperCase()).join(', ')}!';
    } else {
      text = 'The longest word on the board was ${l.word.toUpperCase()} (${l.word.length} letters)! '
          'There were ${r.totalPossibleWords} words hiding in this grid.';
    }
    return LayoutBuilder(builder: (context, c) {
      final side = min(c.maxWidth - 64, c.maxHeight * 0.55).clamp(160.0, 360.0);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MascotBubble(text: text, faceSize: 64),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: side,
              child: _AnimatedPath(board: r, path: l.path),
            ),
          ),
          const SizedBox(height: 14),
          Center(child: LabelPill(l.word.toUpperCase(), color: MwgColors.gold, fontSize: 26)),
        ],
      );
    });
  }

  /// Shares a link to this exact board, options, and everyone's results.
  Future<void> _challenge(BuildContext context) async {
    final dict = widget.session.dictionary;
    final url = challengeUrl(Challenge.fromResults(r, fromId: myId), dict);
    debugPrint('[challenge] $url');
    final shared = await shareOrCopy(context,
        text: "Can you beat my score in Michi's Word Game?\n$url", subject: "Michi's Word Game challenge");
    if (!shared) widget.app.say('Challenge link copied! Paste it to a friend.');
  }

  // ---- Stage: winner ----
  Widget _winner() {
    final winners = r.winners;
    final ranked = List.of(r.players)..sort((a, b) => b.score.compareTo(a.score));
    final phrases = ['Voluminous victory', 'Wonderful wordsmithing', 'Legendary lexicon', 'Spectacular spelling'];
    final phrase = phrases[r.board.tiles.join().hashCode.abs() % phrases.length];
    final title = winners.isEmpty
        ? 'Round over!'
        : winners.length == 1
            ? '$phrase, ${winners.first.player.name}!'
            : "It's a tie between ${winners.map((w) => w.player.name).join(' & ')}!";
    final session = widget.session;
    final host = session.players.where((p) => p.isHost).firstOrNull?.name ?? 'the host';
    var place = 0;
    int? lastScore;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF7AD9), Color(0xFF8B5CF6)]),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Column(
            children: [
              if (winners.length == 1) AvatarCircle(avatar: winners.first.player.avatar, size: 76),
              const SizedBox(height: 8),
              BubbleText(title, size: 30, fill: MwgColors.gold),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < ranked.length; i++)
          Builder(builder: (_) {
            final p = ranked[i];
            if (p.score != lastScore) place = i + 1;
            lastScore = p.score;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: BubbleText(placeLabel(place),
                        size: place <= 2 ? 34 : 26,
                        fill: place == 1 ? MwgColors.gold : Colors.white,
                        stroke: MwgColors.tile),
                  ),
                  Expanded(
                    child: _PlayerBanner(
                      compact: true,
                      player: p.player,
                      isMe: p.player.id == myId,
                      right: _ScoreBadge(score: p.score),
                      leftExtra: '${p.wordCount} ${p.wordCount == 1 ? 'word' : 'words'}',
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Challenge a friend',
          icon: Icons.emoji_events_rounded,
          color: MwgColors.gold,
          onPressed: () => _challenge(context),
        ),
        const SizedBox(height: 12),
        if (session is HostSession)
          ChunkyButton(label: 'Back to the room', icon: Icons.replay_rounded, onPressed: session.backToRoom)
        else if (session is ClientSession && session.hostBackInRoom)
          ChunkyButton(label: 'Back to the room', icon: Icons.replay_rounded, onPressed: session.finishResults)
        else if (session is ClientSession)
          MascotBubble(text: 'Great game! Waiting for $host to head back to the room…')
        else
          ChunkyButton(label: 'Done', icon: Icons.home_rounded, onPressed: widget.app.leaveSession),
      ],
    );
  }
}

class _PlayerBanner extends StatelessWidget {
  const _PlayerBanner({
    required this.player,
    required this.right,
    this.isMe = false,
    this.compact = false,
    this.crown = false,
    this.flash = false,
    this.leftExtra,
  });
  final PlayerInfo player;
  final Widget right;
  final bool isMe;
  final bool compact;
  final bool crown;
  final bool flash;
  final String? leftExtra;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 58.0 : 84.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: flash ? const Color(0xFF2E8A5A) : (isMe ? const Color(0xFF3B2A8C) : const Color(0x66000000)),
        borderRadius: BorderRadius.circular(h / 2.4),
        border: Border.all(color: isMe ? MwgColors.cyan : Colors.white24, width: 2.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name,
                    overflow: TextOverflow.ellipsis,
                    style: uiText(compact ? 17 : 20, weight: FontWeight.w700)),
                if (leftExtra != null)
                  Text(leftExtra!, style: uiText(13, weight: FontWeight.w500, color: Colors.white70)),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarCircle(avatar: player.avatar, size: compact ? 42 : 60),
              if (crown)
                const Positioned(
                  top: -14,
                  left: 0,
                  right: 0,
                  child: Icon(Icons.emoji_events_rounded, color: MwgColors.gold, size: 22),
                ),
            ],
          ),
          Expanded(child: Align(alignment: Alignment.centerRight, child: right)),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, this.hidden = false});
  final int score;

  /// Shows "???" instead of the number.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(a), child: c),
      child: Container(
        key: ValueKey(hidden ? -1 : score),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: MwgColors.gold,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MwgColors.tile, width: 2.5),
        ),
        child: Text(hidden ? '???' : '$score', style: uiText(20, weight: FontWeight.w700, color: MwgColors.tile)),
      ),
    );
  }
}

class _RulesPanel extends StatelessWidget {
  const _RulesPanel();

  @override
  Widget build(BuildContext context) {
    Widget row(String a, String b) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a, style: uiText(13, weight: FontWeight.w500, color: Colors.white70)),
            Text(b, style: uiText(13, weight: FontWeight.w700)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: const Color(0x44000000), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          row('3-letter words', '1 point'),
          row('Every extra letter', '+1 point'),
          row('Unique words', 'DOUBLE points x2'),
        ]),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.highlight});
  final Highlight highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MwgColors.ribbon,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0F6B37), width: 3),
      ),
      child: Column(
        children: [
          BubbleText(highlight.title, size: 22, stroke: const Color(0xFF0F6B37)),
          const SizedBox(height: 4),
          Text(highlight.detail, textAlign: TextAlign.center, style: uiText(15, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight, required this.mine, required this.avatars});
  final Highlight highlight;
  final bool mine;
  final List<int> avatars;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      color: mine ? const Color(0xAA3B2A8C) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 40,
            child: Stack(
              children: [
                for (var i = 0; i < avatars.length; i++)
                  Positioned(left: i * 10.0, child: AvatarCircle(avatar: avatars[i], size: 36, ring: true)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(highlight.title, style: uiText(18, weight: FontWeight.w700, color: MwgColors.gold)),
                Text(highlight.detail, style: uiText(15, weight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Starburst extends StatelessWidget {
  const _Starburst({required this.text, required this.sub});
  final String text;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 230,
        height: 230,
        child: CustomPaint(
          painter: _StarPainter(),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BubbleText(text, size: 26, fill: Colors.white, stroke: const Color(0xFFB45309)),
                  const SizedBox(height: 4),
                  Text(sub, textAlign: TextAlign.center, style: uiText(13, weight: FontWeight.w700, color: MwgColors.tile)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2, inner = outer * 0.78;
    const points = 16;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final a = -pi / 2 + i * pi / points;
      final p = c + Offset(cos(a) * r, sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = MwgColors.gold);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFB45309)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TapHint extends StatefulWidget {
  @override
  State<_TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<_TapHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x55000000),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white38),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tap to continue', style: uiText(17, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Icon(Icons.touch_app_rounded, color: Colors.white),
            ],
          ),
        ),
      );
}

/// Spells a word out on the grid tile by tile over [duration], then turns
/// green once the points are awarded ([done]).
class _TracePath extends StatelessWidget {
  const _TracePath({super.key, required this.board, required this.path, required this.duration, required this.done});
  final Board board;
  final List<int> path;
  final Duration duration;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      builder: (_, v, _) {
        final n = done ? path.length : (v * path.length).ceil().clamp(1, path.length);
        final shown = path.sublist(0, n);
        return BoardView(
          board: board,
          looks: {for (final t in shown) t: done ? TileLook.good : TileLook.selected},
          line: shown,
          lineColor: done ? Colors.white : MwgColors.pink,
        );
      },
    );
  }
}

/// Traces a path one tile at a time.
class _AnimatedPath extends StatelessWidget {
  const _AnimatedPath({required this.board, required this.path});
  final RoundResults board;
  final List<int> path;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 * path.length),
      builder: (_, v, _) {
        final n = (v * path.length).ceil().clamp(1, path.length);
        final shown = path.sublist(0, n);
        final done = n == path.length && v >= 1;
        return BoardView(
          board: board.board,
          looks: {for (final t in shown) t: done ? TileLook.good : TileLook.selected},
          line: shown,
          lineColor: done ? Colors.white : MwgColors.pink,
        );
      },
    );
  }
}
