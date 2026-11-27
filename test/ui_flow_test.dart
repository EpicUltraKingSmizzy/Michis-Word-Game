// Widget tests for the end-of-game pages, hidden challenge scores, and the
// in-round Quit button.
import 'dart:math';

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/challenge.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/scoring.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/main.dart';
import 'package:michis_word_game/net/fake_link.dart';
import 'package:michis_word_game/state/app_state.dart';
import 'package:michis_word_game/state/session.dart';
import 'package:michis_word_game/ui/screens/challenge_screen.dart';
import 'package:michis_word_game/ui/screens/results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

final dict = realDictionary();

Challenge makeChallenge({bool withWords = true, int seed = 4}) {
  final rng = Random(seed);
  const s = GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 60);
  final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: rng);
  final words = (solveBoard(b, dict).keys.toList()..sort()).take(6).toList();
  return Challenge(settings: s, board: b, players: [
    ChallengePlayer(
      name: 'Rival',
      avatar: 1,
      score: words.fold(0, (a, w) => a + wordPoints(w)),
      wordCount: words.length,
      words: withWords ? words : null,
    ),
  ]);
}

/// Plays a solo challenge round (finding one word) and returns its results.
Future<(SoloSession, RoundResults)> playChallenge(WidgetTester tester, Challenge c) async {
  final s = SoloSession(dictionary: dict, challenge: c, name: 'Me', avatar: 2);
  s.start();
  s.phase = SessionPhase.playing;
  final solved = solveBoard(c.board, dict).entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  s.submitPath(solved.first.value);
  s.phase = SessionPhase.waitingForResults;
  s.onBuzzer();
  await tester.pump(const Duration(seconds: 1));
  expect(s.phase, SessionPhase.results);
  return (s, s.results!);
}

Future<void> pumpResults(WidgetTester tester, GameSession s, RoundResults r) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(MaterialApp(home: ResultsScreen(app: AppState(), session: s, results: r)));
}

Finder stage(String name) => find.byKey(ValueKey('stage-$name'));

Future<void> tapThrough(WidgetTester tester) async {
  await tester.tap(find.text('Tap to continue'), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> loadFonts() async {
  final fams = {
    'Fredoka': ['Medium', 'SemiBold', 'Bold'],
    'Montserrat': ['ExtraBold', 'Black'],
  };
  for (final e in fams.entries) {
    final l = FontLoader(e.key);
    for (final w in e.value) {
      final bytes = File('assets/fonts/${e.key}-$w.ttf').readAsBytesSync();
      l.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await l.load();
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('Skip only skips the scoring; the other pages are still tapped through', (tester) async {
    final (s, r) = await playChallenge(tester, makeChallenge());
    await pumpResults(tester, s, r);
    await tester.pump(const Duration(seconds: 3)); // into the replay
    expect(stage('replay'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 500));
    // Not straight to the winner: the highlights page, waiting for a tap.
    expect(stage('highlights'), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-scoring')), findsNothing);
    expect(find.text('Tap to continue'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(stage('highlights'), findsOneWidget, reason: 'waits for the player');
    await tapThrough(tester);
    if (r.longest != null) {
      expect(stage('longest'), findsOneWidget);
      await tapThrough(tester);
    }
    expect(stage('winner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('solo round: missed words page comes after scoring, before the highlights', (tester) async {
    final host = (await tester.runAsync(() => HostSession.create(
          dictionary: dict,
          linkFactory: () => FakeHostLink(FakeNetwork()),
          name: 'Me',
          avatar: 2,
          random: Random(3),
        )))!;
    final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: Random(11));
    final solved = solveBoard(b, dict);
    final mine = (solved.keys.toList()..sort()).take(3).toList();
    const settings = GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 60);
    final r = scoreRound(
      board: b,
      settings: settings,
      players: host.players,
      submissions: {
        host.myId: [for (var i = 0; i < mine.length; i++) Submission(word: mine[i], path: solved[mine[i]]!, atMs: i)],
      },
      solved: solved,
    );
    await pumpResults(tester, host, r);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(seconds: 3));
    expect(stage('missed'), findsOneWidget);
    expect(find.byKey(const ValueKey('missed-words')), findsOneWidget);
    for (final w in mine) {
      expect(find.text(w.toUpperCase()), findsNothing, reason: 'found words are not "missed"');
    }
    expect(find.text(r.longest!.word.toUpperCase()), findsNothing, reason: 'longest word has its own page');
    await tapThrough(tester);
    expect(stage('highlights'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(host.leave);
  });

  testWidgets('Skip during "Time\'s up" also lands on the highlights', (tester) async {
    final (s, r) = await playChallenge(tester, makeChallenge(seed: 9));
    await pumpResults(tester, s, r);
    await tester.pump(const Duration(milliseconds: 300));
    expect(stage('intro'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(stage('highlights'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('without Skip, the replay ends on the final scores and waits for a tap', (tester) async {
    final (s, r) = await playChallenge(tester, makeChallenge(seed: 5));
    await pumpResults(tester, s, r);
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 80 && find.text('Tap to continue').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(stage('replay'), findsOneWidget);
    await tapThrough(tester);
    expect(stage('highlights'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('challenge intro shows the rival score as ???', (tester) async {
    final c = makeChallenge();
    final s = SoloSession(dictionary: dict, challenge: c, name: 'Me', avatar: 2);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(MaterialApp(home: Material(child: ChallengeScreen(app: AppState(), session: s))));
    expect(find.text('???'), findsOneWidget);
    expect(find.text('${c.players.first.score}'), findsNothing);
    expect(find.textContaining('${c.players.first.wordCount} words'), findsNothing);
  });

  testWidgets('challenge scores count up during scoring, like a game together', (tester) async {
    final c = makeChallenge();
    final (s, r) = await playChallenge(tester, c);
    final rival = r.players.firstWhere((p) => p.player.name == 'Rival');
    await pumpResults(tester, s, r);
    await tester.pump(const Duration(seconds: 3));
    expect(stage('replay'), findsOneWidget);
    // Starts from 0, never shows the final number up front.
    expect(find.text('${rival.score}'), findsNothing);
    for (var i = 0; i < 120 && find.text('Tap to continue').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('${rival.score}'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a score-only challenge (no word list) shows ??? until scoring ends', (tester) async {
    final c = makeChallenge(withWords: false);
    final (s, r) = await playChallenge(tester, c);
    await pumpResults(tester, s, r);
    await tester.pump(const Duration(seconds: 3));
    expect(stage('replay'), findsOneWidget);
    expect(find.text('???'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2)); // let the old page fade out
    expect(stage('highlights'), findsOneWidget);
    expect(find.text('???'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Quit button during a round asks first, then leaves', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await tester.runAsync(() => app.init(loadDictionary: () async => dict));
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MichisWordGame(app: app));
    app.startChallenge(encodeChallenge(makeChallenge(), dict));
    await tester.pump(const Duration(milliseconds: 500));
    final s = app.session as SoloSession;
    expect(find.byKey(const ValueKey('quit-round')), findsNothing, reason: 'no Quit in the lobby');
    s.start();
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.phase, SessionPhase.countdown);
    expect(find.byKey(const ValueKey('quit-round')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(s.phase, SessionPhase.playing);

    // "Keep playing" keeps the round.
    await tester.tap(find.byKey(const ValueKey('quit-round')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Quit this game?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.session, same(s));

    // System back (Android back, browser back) also asks instead of leaving.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Quit this game?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-quit')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.session, isNull);
    expect(find.byKey(const ValueKey('quit-round')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}
