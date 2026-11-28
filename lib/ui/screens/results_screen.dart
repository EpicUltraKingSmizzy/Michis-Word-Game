import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/board.dart';
import '../../logic/challenge.dart';
import '../../logic/longest_word.dart';
import '../../logic/missed_words.dart';
import '../../logic/models.dart';
import '../../logic/replay_order.dart';
import '../../logic/solver.dart';
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

enum _Stage { intro, replay, tieBreak, missed, highlights, longest, winner }

/// End of round: word counts, word-by-word scoring replay, (solo rounds only)
/// a replay of some words the player missed, highlights, the longest word on
/// the board, and the winner.
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

  /// A solo round: the host played alone (not a challenge link, which has
  /// the friends' results in it, and not a multiplayer room).
  bool get _isSoloRound =>
      widget.session is HostSession && r.players.length == 1 && r.players.first.player.id == myId;

  /// Words on the board the solo player didn't find (empty if not solo).
  late final List<String> _missed = _computeMissed();

  /// A path for every word on the board (filled in by [_computeMissed]).
  Map<String, List<int>> _solved = const {};

  /// The missed word being traced on the board, and whether its trace is done.
  String? _missedWord;
  bool _missedTraced = false;

  /// How many missed words have been revealed in the list so far.
  int _missedShown = 0;

  /// "Skip" during the missed-words replay: ends it and reveals every word.
  bool _skipMissed = false;
  final _skipMissedSignal = Completer<void>();

  /// The replay is over: the words can be tapped to see them on the board.
  bool _missedDone = false;

  /// Bumped on every tap of a word, so tapping the same word replays it.
  int _missedTapCount = 0;

  /// True when every 3-5 letter word was found, so [_missed] holds longer ones.
  bool _allShortFound = false;

  /// Show the missed-words page: solo rounds with missed words, and every
  /// solo "Longest word only" round (with nothing better, Michi congratulates).
  bool get _showMissedPage => _isSoloRound && (_missed.isNotEmpty || r.settings.longestOnly);

  List<String> _computeMissed() {
    if (!_isSoloRound) return const [];
    final solved = _solved = solveBoard(r.board, widget.session.dictionary, minWordLength: r.settings.minWordLength);
    if (r.settings.longestOnly) {
      // Only words that would have beaten the counted word, best first. The
      // longest word isn't held back here: longer words are the point.
      return pickBetterMissedWords(solved: solved.keys, counted: r.players.first.countedWord);
    }
    final found = r.players.first.words.map((w) => w.toLowerCase()).toSet();
    _allShortFound = !solved.keys.any((w) =>
        w.length >= MissedWordsTuning.shortMin && w.length <= MissedWordsTuning.shortMax && !found.contains(w));
    return pickMissedWords(
      solved: solved.keys,
      found: found,
      // The longest word(s) have their own reveal later.
      exclude: r.longest?.allLongest ?? const [],
      seed: missedWordsSeed(r.board.tiles),
    );
  }
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
    if (!_skipMissedSignal.isCompleted) _skipMissedSignal.complete();
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

  /// Pauses the missed-words replay. False if it should stop.
  Future<bool> _waitMissed(int ms) async {
    if (_skipMissed || _disposed) return false;
    await Future.any([Future<void>.delayed(Duration(milliseconds: ms)), _skipMissedSignal.future]);
    return mounted && !_skipMissed && !_disposed;
  }

  /// Skip button during the missed-words replay.
  void _skipMissedReplay() {
    if (_missedDone) return;
    setState(() => _skipMissed = true);
    if (!_skipMissedSignal.isCompleted) _skipMissedSignal.complete();
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
    if (r.tieBreak != null) {
      setState(() => _stage = _Stage.tieBreak);
      await _tieBreakAnim();
      if (!await _waitTap()) return;
      if (!mounted) return;
    }
    if (_showMissedPage) {
      setState(() => _stage = _Stage.missed);
      await _missedReplay();
      if (_disposed || !mounted) return;
      setState(() {
        _missedDone = true;
        _missedShown = _missed.length;
        _missedWord = null;
      });
      // Now the words can be tapped, so this page moves on with its own
      // Continue button (even after a Skip).
      if (!await _waitTap()) return;
      if (!mounted) return;
    }
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

  /// Traces each missed word on the board, letter by letter, with the same
  /// timing as the scoring replay (no points). Returns early when skipped.
  Future<void> _missedReplay() async {
    // Let Michi's bubble pop up before the first word.
    if (!await _waitMissed(900)) return;
    for (var i = 0; i < _missed.length; i++) {
      final w = _missed[i];
      setState(() {
        _missedWord = w;
        _missedTraced = false;
        _missedShown = i + 1;
      });
      final step = replayStepDuration(WordEntry(word: w, path: _solved[w]!, finders: [myId]));
      if (!await _waitMissed(step.inMilliseconds - 400)) return;
      setState(() => _missedTraced = true);
      if (!await _waitMissed(400)) return;
    }
  }

  /// Tie-breaker: how many letters have been scored, and whether it's over.
  int _tbLetters = 0;
  bool _tbDone = false;

  Future<bool> _pause(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return mounted && !_disposed;
  }

  /// Shows the tied words, then scores their letters one column at a time
  /// (or says "Same Word!"), then the result.
  Future<void> _tieBreakAnim() async {
    final tb = r.tieBreak!;
    if (!await _pause(1200)) return;
    if (!tb.sameWord) {
      final longest = tb.words.map((w) => w.length).reduce(max);
      for (var i = 0; i < longest; i++) {
        setState(() => _tbLetters = i + 1);
        HapticFeedback.selectionClick();
        if (!await _pause(420)) return;
      }
      if (!await _pause(400)) return;
    }
    setState(() => _tbDone = true);
    if (tb.winnerIds.contains(myId)) HapticFeedback.heavyImpact();
  }

  /// Tapping a word in the missed list (after the replay) traces it again.
  void _showMissed(String w) {
    if (!_missedDone) return;
    HapticFeedback.selectionClick();
    setState(() {
      _missedWord = w;
      _missedTraced = false;
      _missedTapCount++;
    });
    final tap = _missedTapCount;
    final step = replayStepDuration(WordEntry(word: w, path: _solved[w]!, finders: [myId]));
    Future<void>.delayed(Duration(milliseconds: step.inMilliseconds - 400), () {
      if (mounted && !_disposed && tap == _missedTapCount) setState(() => _missedTraced = true);
    });
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
      _Stage.tieBreak => _tieBreak(),
      _Stage.missed => _missedWords(),
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
                    if (_stage == _Stage.missed && !_missedDone && _missed.isNotEmpty)
                      PillButton(
                        key: const ValueKey('skip-missed'),
                        tooltip: 'Skip the missed words',
                        onTap: _skipMissedReplay,
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Skip'),
                          Icon(Icons.fast_forward_rounded),
                        ]),
                      ),
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
                  // On the missed-words page taps pick words; it has a Continue button.
                  onTap: _tapWait == null || _stage == _Stage.missed ? null : _advance,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: KeyedSubtree(key: ValueKey('stage-${_stage.name}'), child: body),
                  ),
                ),
              ),
              if (_tapWait != null && _stage == _Stage.missed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: ChunkyButton(
                    key: const ValueKey('missed-continue'),
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    height: 52,
                    fontSize: 22,
                    onPressed: _advance,
                  ),
                )
              else if (_tapWait != null)
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
                          color: e.isDoubled ? MwgColors.gold : MwgColors.mint, fontSize: 22),
                      if (e.isDoubled) ...[
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
          _RulesPanel(longestOnly: r.settings.longestOnly),
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

  // ---- Stage: tie-breaker ("Longest word only") ----
  Widget _tieBreak() {
    final tb = r.tieBreak!;
    final tiedScore = r.playerById(tb.playerIds.first)?.score ?? 0;
    final names = [for (final id in tb.winnerIds) r.playerById(id)?.player.name ?? '?'];
    final String result;
    if (tb.sameWord) {
      result = "It's still a tie!";
    } else if (names.length == 1) {
      result = '${names.first} wins the tie-breaker!';
    } else {
      result = 'Still a tie! ${names.join(' & ')} share the win.';
    }
    return LayoutBuilder(builder: (context, c) {
      final longest = tb.words.map((w) => w.length).reduce(max);
      // Card: 16 screen padding + 14 card padding on each side.
      final avail = c.maxWidth - 60;
      final tile = ((avail - (longest - 1) * 4) / longest).clamp(14.0, 40.0);
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BubbleText('Tie-breaker!', size: 36, fill: MwgColors.gold),
              const SizedBox(height: 6),
              Text(
                'Tied on $tiedScore ${tiedScore == 1 ? 'point' : 'points'}. The letters decide it!',
                textAlign: TextAlign.center,
                style: uiText(16, weight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < tb.playerIds.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TieBreakCard(
                    key: ValueKey('tb-${tb.playerIds[i]}'),
                    player: r.playerById(tb.playerIds[i])?.player,
                    word: tb.words[i],
                    tile: tile,
                    scored: tb.sameWord ? 0 : _tbLetters,
                    showTotal: !tb.sameWord,
                    winner: _tbDone && !tb.sameWord && tb.winnerIds.contains(tb.playerIds[i]),
                    isMe: tb.playerIds[i] == myId,
                  ),
                ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                child: !_tbDone
                    ? const SizedBox(height: 10)
                    : Column(
                        key: const ValueKey('tb-result'),
                        children: [
                          if (tb.sameWord) BubbleText('Same Word!', size: 34, fill: MwgColors.pink),
                          const SizedBox(height: 6),
                          BubbleText(result, size: 24, fill: Colors.white),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---- Stage: words the solo player missed, traced on the board ----
  Widget _missedWords() {
    final n = _missed.length;
    final words = n == 1 ? '1 word' : '$n words';
    final counted = r.players.first.countedWord;
    final String text;
    if (r.settings.longestOnly) {
      text = n == 0
          ? 'You found the best word on the board! Nothing could beat ${counted?.toUpperCase() ?? 'it'}. Amazing!'
          : 'Here ${n == 1 ? 'is' : 'are'} $words you missed! '
              '${counted == null ? 'Any of them would have scored.' : '${n == 1 ? 'It' : 'Each one'} would have beaten ${counted.toUpperCase()}.'}';
    } else {
      text = _allShortFound
          ? 'You found every short word! Here ${n == 1 ? 'is 1 longer word' : 'are $n longer words'} you missed!'
          : 'Here ${n == 1 ? 'is' : 'are'} $words you missed!';
    }
    final w = _missedWord;
    return LayoutBuilder(builder: (context, c) {
      final gridSide = min(c.maxWidth - 120, c.maxHeight * 0.42).clamp(160.0, 340.0);
      // On tall screens keep the board exactly where it was during scoring;
      // on short ones give that space to the word list.
      final roomy = c.maxHeight >= 600;
      return Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Michi pops up with the speech bubble.
            child: TweenAnimationBuilder<double>(
              key: const ValueKey('missed-bubble'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Opacity(
                opacity: v.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, 40 * (1 - v)),
                  child: Transform.scale(scale: 0.7 + 0.3 * v, alignment: Alignment.bottomLeft, child: child),
                ),
              ),
              child: MascotBubble(text: text, faceSize: 64),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Wrap(
                    key: const ValueKey('missed-list'),
                    alignment: WrapAlignment.center,
                    spacing: roomy ? 8 : 6,
                    runSpacing: roomy ? 8 : 6,
                    children: [
                      for (var i = 0; i < _missedShown && i < n; i++)
                        _MissedChip(
                          key: ValueKey('missed-chip-${_missed[i]}'),
                          word: _missed[i],
                          active: _missed[i] == w,
                          small: !roomy,
                          onTap: _missedDone ? () => _showMissed(_missed[i]) : null,
                        ),
                    ],
                  ),
                  if (_missedDone && n > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      w == null ? 'Tap a word to see it on the board' : 'Tap another word to see where it was',
                      textAlign: TextAlign.center,
                      style: uiText(14, weight: FontWeight.w600, color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: gridSide,
            child: w == null
                ? BoardView(board: r.board, looks: const {}, line: const [])
                : _TracePath(
                    key: ValueKey('missed-trace-$w-$_missedTapCount'),
                    board: r.board,
                    path: _solved[w]!,
                    done: _missedTraced,
                    look: TileLook.missed,
                    doneLook: TileLook.missed,
                    lineColor: MwgColors.silverLine,
                    doneLineColor: MwgColors.silverLine,
                    duration: Duration(
                        milliseconds: ((replayStepDuration(WordEntry(word: w, path: _solved[w]!, finders: [myId]))
                                        .inMilliseconds -
                                    400) *
                                0.8)
                            .round()),
                  ),
          ),
          const SizedBox(height: 10),
          if (roomy) ...[
            // Keeps the board where it was during the scoring replay.
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _RulesPanel(longestOnly: r.settings.longestOnly),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    });
  }

  // ---- Stage: highlights ----
  Widget _highlights() {
    final rec = _record;
    final s = r.settings;
    final items = <Widget>[
      if (rec != null && rec.newOverallBest)
        _Starburst(text: 'Personal best!', sub: '${r.playerById(myId)?.score ?? 0} points (was ${rec.previousBest})')
      else if (rec != null && rec.newConfigBest)
        _Starburst(
            text: 'Personal best!',
            sub: 'on ${s.gridLabel} · ${s.durationLabel}${s.longestOnly ? ' · Longest word only' : ''}'),
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
    final winnerIds = {for (final w in winners) w.player.id};
    // By score; a tie-breaker's winners go ahead of the players they beat.
    final ranked = List.of(r.players)
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return (winnerIds.contains(b.player.id) ? 1 : 0).compareTo(winnerIds.contains(a.player.id) ? 1 : 0);
      });
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
    String? lastKey;
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
            final key = '${p.score}/${winnerIds.contains(p.player.id)}';
            if (key != lastKey) place = i + 1;
            lastKey = key;
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
                      leftExtra: r.settings.longestOnly && p.countedWord != null
                          ? p.countedWord!.toUpperCase()
                          : '${p.wordCount} ${p.wordCount == 1 ? 'word' : 'words'}',
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

/// A missed word in the list above the board. It pops in when revealed and
/// stands out while it is the one shown on the board.
class _MissedChip extends StatelessWidget {
  const _MissedChip({super.key, required this.word, required this.active, this.small = false, this.onTap});
  final String word;
  final bool active;

  /// Smaller text and padding for short screens.
  final bool small;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
      ),
      child: Semantics(
        button: onTap != null,
        label: word,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: active ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 3 : 5),
              decoration: BoxDecoration(
                color: active ? MwgColors.silverLine : MwgColors.silver,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? Colors.white : MwgColors.tile, width: active ? 3 : 2.5),
                boxShadow: active ? const [BoxShadow(color: Color(0x66FFFFFF), blurRadius: 10)] : null,
              ),
              child: Text(word.toUpperCase(), style: uiText(small ? 15 : 18, weight: FontWeight.w700, color: MwgColors.tile)),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tied player's word in the tie-breaker, letters separated. The first
/// [scored] letters show their points, with a running total.
class _TieBreakCard extends StatelessWidget {
  const _TieBreakCard({
    super.key,
    required this.player,
    required this.word,
    required this.tile,
    required this.scored,
    required this.showTotal,
    required this.winner,
    required this.isMe,
  });
  final PlayerInfo? player;
  final String word;
  final double tile;
  final int scored;
  final bool showTotal;
  final bool winner;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final letters = word.toUpperCase().split('');
    final total = [for (var i = 0; i < letters.length && i < scored; i++) letterScoreOf(letters[i])]
        .fold(0, (a, b) => a + b);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: winner ? const Color(0xAA2E8A5A) : (isMe ? const Color(0xAA3B2A8C) : MwgColors.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: winner ? MwgColors.gold : (isMe ? MwgColors.cyan : MwgColors.cardBorder), width: 3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AvatarCircle(avatar: player?.avatar ?? 0, size: 34, ring: false),
              const SizedBox(width: 8),
              Expanded(
                child: Text(player?.name ?? '?',
                    overflow: TextOverflow.ellipsis, style: uiText(18, weight: FontWeight.w700)),
              ),
              if (winner) const Icon(Icons.emoji_events_rounded, color: MwgColors.gold),
              if (showTotal)
                Container(
                  key: ValueKey('tb-total-${player?.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: MwgColors.gold,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MwgColors.tile, width: 2.5),
                  ),
                  child: Text('$total', style: uiText(18, weight: FontWeight.w700, color: MwgColors.tile)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < letters.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: tile,
                      height: tile,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < scored ? MwgColors.tileSelected : MwgColors.tile,
                        borderRadius: BorderRadius.circular(tile * 0.22),
                        border: Border.all(color: i < scored ? MwgColors.pink : MwgColors.tileEdge, width: 2),
                      ),
                      child: Text(letters[i],
                          style: TextStyle(
                              fontFamily: fontTile,
                              fontWeight: FontWeight.w900,
                              fontSize: tile * 0.55,
                              height: 1,
                              color: Colors.white)),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 20,
                      child: i < scored
                          ? TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              builder: (_, v, child) => Transform.scale(scale: v, child: child),
                              child: Text('${letterScoreOf(letters[i])}',
                                  style: uiText(15, weight: FontWeight.w700, color: MwgColors.gold)),
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RulesPanel extends StatelessWidget {
  const _RulesPanel({this.longestOnly = false});
  final bool longestOnly;

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
          if (longestOnly) row('Only your longest word', 'counts'),
          row('3-letter words', '1 point'),
          row('Every extra letter', '+1 point'),
          if (!longestOnly) row('Unique words', 'DOUBLE points x2'),
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
  const _TracePath({
    super.key,
    required this.board,
    required this.path,
    required this.duration,
    required this.done,
    this.look = TileLook.selected,
    this.doneLook = TileLook.good,
    this.lineColor = MwgColors.pink,
    this.doneLineColor = Colors.white,
  });
  final Board board;
  final List<int> path;
  final Duration duration;
  final bool done;

  /// Tile look and line colour while tracing, and once the word is done.
  final TileLook look;
  final TileLook doneLook;
  final Color lineColor;
  final Color doneLineColor;

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
          looks: {for (final t in shown) t: done ? doneLook : look},
          line: shown,
          lineColor: done ? doneLineColor : lineColor,
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
