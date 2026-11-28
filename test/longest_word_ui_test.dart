// Widget tests for "Longest word only": the host option, the banner above
// the grid, the tie-breaker page and the missed words in this mode.
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/longest_word.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/scoring.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/net/fake_link.dart';
import 'package:michis_word_game/state/app_state.dart';
import 'package:michis_word_game/state/session.dart';
import 'package:michis_word_game/ui/screens/host_screen.dart';
import 'package:michis_word_game/ui/screens/play_screen.dart';
import 'package:michis_word_game/ui/screens/results_screen.dart';

import 'test_helpers.dart';

final dict = realDictionary();
const lwSettings = GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 60, longestOnly: true);

Future<HostSession> makeHost(WidgetTester tester) async => (await tester.runAsync(() => HostSession.create(
      dictionary: dict,
      linkFactory: () => FakeHostLink(FakeNetwork()),
      name: 'Me',
      avatar: 2,
      random: Random(3),
    )))!;

Finder stage(String name) => find.byKey(ValueKey('stage-$name'));

Future<void> tapThrough(WidgetTester tester) async {
  await tester.tap(find.text('Tap to continue'), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> cleanUp(WidgetTester tester, HostSession host) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(host.leave);
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
  testWidgets('host screen: "Longest word only" replaces the length options, with a hint', (tester) async {
    final host = await makeHost(tester);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: ListenableBuilder(listenable: host, builder: (_, _) => HostScreen(app: AppState(), session: host)))));
    expect(find.text('Longest word only'), findsOneWidget);
    expect(find.byKey(const ValueKey('longest-only-hint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('longest-only')));
    await tester.pump();
    expect(host.settings.longestOnly, isTrue);
    expect(host.settings.minWordLength, 3);
    expect(find.text('Only your longest word will count towards your score.'), findsOneWidget);
    await tester.tap(find.text('4 letters'));
    await tester.pump();
    expect(host.settings.longestOnly, isFalse);
    expect(host.settings.minWordLength, 4);
    expect(find.byKey(const ValueKey('longest-only-hint')), findsNothing);
    await cleanUp(tester, host);
  });

  testWidgets('play screen: the current longest word shows above the grid', (tester) async {
    final host = await makeHost(tester);
    host.updateSettings(lwSettings);
    host.startGame();
    host.phase = SessionPhase.playing;
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(
        home: ListenableBuilder(listenable: host, builder: (_, _) => PlayScreen(app: AppState(), session: host))));
    expect(find.text('Find a word!'), findsOneWidget);
    final solved = solveBoard(host.board!, dict);
    final words = solved.keys.toList()..sort((a, b) => a.length.compareTo(b.length));
    host.submitPath(solved[words.first]!);
    host.submitPath(solved[words.last]!);
    await tester.pump(const Duration(milliseconds: 400));
    final best = pickCountedWord(host.foundOrder)!;
    expect(best, words.last);
    expect(find.text('${best.toUpperCase()}  +${wordPoints(best)}'), findsOneWidget);
    expect(find.textContaining('${wordPoints(best)} point'), findsOneWidget, reason: 'only the counted word scores');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 90)); // let the round's timers finish
    await cleanUp(tester, host);
  });

  Future<(HostSession, RoundResults)> tiedRound(WidgetTester tester, {required bool sameWord}) async {
    final host = await makeHost(tester);
    final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: Random(11));
    final solved = solveBoard(b, dict);
    // Two words of the same length, with different letter scores.
    final byLen = <int, List<String>>{};
    for (final w in solved.keys) {
      byLen.putIfAbsent(w.length, () => []).add(w);
    }
    final pair = byLen.values.firstWhere((ws) => ws.map(letterScore).toSet().length > 1).toList()
      ..sort((a, b) => letterScore(a).compareTo(letterScore(b)));
    final mine = pair.first, theirs = sameWord ? pair.first : pair.last;
    const friend = PlayerInfo(id: 'f', name: 'Kai', avatar: 3);
    final r = scoreRound(
      board: b,
      settings: lwSettings,
      players: [host.players.first, friend],
      submissions: {
        host.myId: [Submission(word: mine, path: solved[mine]!, atMs: 1)],
        'f': [Submission(word: theirs, path: solved[theirs]!, atMs: 2)],
      },
      solved: solved,
    );
    return (host, r);
  }

  testWidgets('tie-breaker: letters are scored one by one and the higher total wins', (tester) async {
    final (host, r) = await tiedRound(tester, sameWord: false);
    expect(r.tieBreak, isNotNull);
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(app: AppState(), session: host, results: r)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(stage('tieBreak'), findsOneWidget);
    expect(find.text('Tie-breaker!'), findsWidgets);
    for (var i = 0; i < 40 && find.text('Tap to continue').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Kai wins the tie-breaker!'), findsWidgets);
    expect(find.text('Same Word!'), findsNothing);
    final total = tester.widget<Text>(
        find.descendant(of: find.byKey(const ValueKey('tb-total-f')), matching: find.byType(Text)));
    expect(total.data, '${letterScore(r.tieBreak!.words[1])}');
    await tapThrough(tester);
    expect(stage('highlights'), findsOneWidget, reason: 'not solo, so no missed words');
    await cleanUp(tester, host);
  });

  testWidgets('tie-breaker: the same word says "Same Word!" and stays a tie', (tester) async {
    final (host, r) = await tiedRound(tester, sameWord: true);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(app: AppState(), session: host, results: r)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Same Word!'), findsWidgets);
    expect(find.text("It's still a tie!"), findsWidgets);
    expect(tester.takeException(), isNull);
    await cleanUp(tester, host);
  });

  Future<(HostSession, RoundResults, Map<String, List<int>>)> soloLw(WidgetTester tester, String Function(List<String>) pick) async {
    final host = await makeHost(tester);
    final b = generateGoodBoard(size: 4, minWordLength: 3, dictionary: dict, random: Random(11));
    final solved = solveBoard(b, dict);
    final w = pick(solved.keys.toList());
    final r = scoreRound(
      board: b,
      settings: lwSettings,
      players: host.players,
      submissions: {
        host.myId: [Submission(word: w, path: solved[w]!, atMs: 1)],
      },
      solved: solved,
    );
    return (host, r, solved);
  }

  testWidgets('solo: missed words are only better words, best first', (tester) async {
    final (host, r, solved) = await soloLw(tester, (ws) => ws.firstWhere((w) => w.length == 4));
    final counted = r.players.first.countedWord!;
    final expected = pickBetterMissedWords(solved: solved.keys, counted: counted);
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(app: AppState(), session: host, results: r)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(stage('missed'), findsOneWidget);
    expect(find.textContaining('Here are ${expected.length} words you missed!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-missed')));
    await tester.pump(const Duration(milliseconds: 500));
    for (final w in expected) {
      expect(find.byKey(ValueKey('missed-chip-$w')), findsOneWidget);
      expect(compareWordStrength(w, counted), greaterThan(0));
    }
    await cleanUp(tester, host);
  });

  testWidgets('solo: finding the best word gets a congratulation', (tester) async {
    final (host, r, _) = await soloLw(tester, (ws) {
      final sorted = List.of(ws)..sort((a, b) => compareWordStrength(b, a));
      return sorted.first;
    });
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(app: AppState(), session: host, results: r)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('skip-scoring')));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(stage('missed'), findsOneWidget);
    expect(find.textContaining('You found the best word on the board!'), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-missed')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('missed-continue')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(stage('highlights'), findsOneWidget);
    await cleanUp(tester, host);
  });
}
