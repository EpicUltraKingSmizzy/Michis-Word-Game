import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/path_validation.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/net/fake_link.dart';
import 'package:michis_word_game/state/session.dart';

import 'test_helpers.dart';

void main() {
  test('host and two players play a full round over a fake network', () async {
    final dict = realDictionary();
    final net = FakeNetwork();
    final host = await HostSession.create(
      dictionary: dict,
      linkFactory: () => FakeHostLink(net),
      name: 'Michi',
      avatar: 2,
      random: Random(7),
    );
    final p1 = await ClientSession.join(
        dictionary: dict,
        linkFactory: () => FakeClientLink(net, 'c1'),
        roomCode: host.roomCode,
        name: 'Ann',
        avatar: 1);
    final p2 = await ClientSession.join(
        dictionary: dict,
        linkFactory: () => FakeClientLink(net, 'c2'),
        roomCode: host.roomCode,
        name: 'Bob',
        avatar: 3);
    expect(host.players.map((p) => p.name), ['Michi', 'Ann', 'Bob']);
    expect(p1.players.length, 3);

    host.updateSettings(const GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 60));
    expect(p2.settings.durationSeconds, 60);
    p1.updateProfile('Annie', 4);
    expect(host.players[1].name, 'Annie');
    expect(p2.players[1].avatar, 4);

    host.startGame();
    expect(host.phase, SessionPhase.countdown);
    expect(p1.phase, SessionPhase.countdown);
    expect(p1.board!.tiles, host.board!.tiles);

    // Fast-forward: pretend the countdown is over.
    for (final s in [host, p1, p2]) {
      s.phase = SessionPhase.playing;
    }
    final solved = solveBoard(host.board!, dict).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final shared = solved[0], hostOnly = solved[1], annOnly = solved[2];
    expect(host.submitPath(shared.value), SubmissionResult.added);
    expect(host.submitPath(shared.value), SubmissionResult.alreadyFound);
    expect(p1.submitPath(shared.value), SubmissionResult.added);
    expect(p2.submitPath(shared.value), SubmissionResult.added);
    expect(host.submitPath(hostOnly.value), SubmissionResult.added);
    expect(p1.submitPath(annOnly.value), SubmissionResult.added);

    // A late joiner waits for the next round.
    final late = await ClientSession.join(
        dictionary: dict,
        linkFactory: () => FakeClientLink(net, 'c3'),
        roomCode: host.roomCode,
        name: 'Cat',
        avatar: 0);
    expect(late.roundInProgress, isTrue);

    for (final s in [host, p1, p2]) {
      s.phase = SessionPhase.waitingForResults;
    }
    host.onBuzzer();
    await Future<void>.delayed(resultsGrace + const Duration(milliseconds: 200));

    expect(host.phase, SessionPhase.results);
    expect(p1.phase, SessionPhase.results);
    expect(late.phase, SessionPhase.lobby);
    final r = p2.results!;
    expect(r.players.length, 3);
    final pts = shared.key.length - 2;
    expect(r.playerById('host')!.score, pts + 2 * (hostOnly.key.length - 2));
    expect(r.playerById(p1.myId)!.score, pts + 2 * (annOnly.key.length - 2));
    expect(r.playerById(p2.myId)!.score, pts);
    expect(r.replay.first.word, shared.key);
    expect(r.replay.first.finders.first, 'host');

    host.backToRoom();
    // Players stay on their results until they're done; nobody is dropped.
    expect(p1.phase, SessionPhase.results);
    expect(p1.hostBackInRoom, isTrue);
    expect(late.roundInProgress, isFalse);
    expect(host.players.length, 4);
    expect(host.presenceOf(p1.myId), PlayerPresence.viewingResults);
    expect(host.presenceOf(late.myId), PlayerPresence.ready);
    expect(host.canStart, isFalse);
    expect(host.startBlockedReason, contains('still viewing results'));
    host.startGame();
    expect(host.phase, SessionPhase.lobby, reason: 'Start is blocked');

    // Settings and chat still reach players who are on the results screen.
    host.updateSettings(const GameSettings(gridSize: 5, minWordLength: 4, durationSeconds: 90));
    expect(p1.settings.gridSize, 5);
    p1.sendChat('gg!');
    expect(host.chat.last.text, 'gg!');
    expect(p2.chat.last.text, 'gg!');
    expect(p1.presence[p2.myId], PlayerPresence.viewingResults);

    p1.finishResults();
    p2.finishResults();
    expect(p1.phase, SessionPhase.lobby);
    expect(host.canStart, isTrue);
    expect(host.players.length, 4);

    await host.leave();
    expect(p1.endedReason, isNotNull);
    for (final s in [host, p1, p2, late]) {
      s.dispose();
    }
  });

  test('dropped players get their seat back; quitters are removed', () async {
    final dict = realDictionary();
    final net = FakeNetwork();
    final host = await HostSession.create(
        dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Michi', avatar: 2, random: Random(3));
    final p1 = await ClientSession.join(
        dictionary: dict, linkFactory: () => FakeClientLink(net, 'c1'), roomCode: host.roomCode, name: 'Ann', avatar: 1);
    final p2 = await ClientSession.join(
        dictionary: dict, linkFactory: () => FakeClientLink(net, 'c2'), roomCode: host.roomCode, name: 'Bob', avatar: 3);
    final annId = p1.myId;

    // Ann's connection drops; the host keeps her seat and she reconnects.
    await p1.link.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(host.players.length, 3);
    expect(p1.reconnecting, isFalse);
    expect(p1.myId, annId);
    expect(host.presenceOf(annId), PlayerPresence.ready);
    expect(p1.endedReason, isNull);

    // Bob quits: he's removed right away and the host can start without him.
    await p2.leave();
    expect(host.players.map((p) => p.name), ['Michi', 'Ann']);
    expect(host.canStart, isTrue);

    await host.leave();
    for (final s in [host, p1, p2]) {
      s.dispose();
    }
  });

  test('chat relays text, replies, reactions, big photos, and history', () async {
    final dict = realDictionary();
    final net = FakeNetwork();
    final host = await HostSession.create(
        dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Michi', avatar: 2, random: Random(5));
    final p1 = await ClientSession.join(
        dictionary: dict, linkFactory: () => FakeClientLink(net, 'c1'), roomCode: host.roomCode, name: 'Ann', avatar: 1);
    host.sendChat('hi all');
    expect(p1.chat.single.text, 'hi all');
    expect(p1.chat.single.from, 'host');
    final photo = Uint8List.fromList(List.generate(90000, (i) => i * 7 % 256));
    p1.sendChat('look', image: photo, thumb: Uint8List.fromList([1, 2, 3]), replyTo: p1.chat.single);
    expect(host.chat.length, 2);
    expect(host.chat.last.image, photo, reason: 'reassembled from chunks');
    expect(host.chat.last.reply!.text, 'hi all');
    p1.react(host.chat.first.id, '😂');
    expect(host.chat.first.reactions['😂'], [p1.myId]);
    host.react(host.chat.first.id, '😂');
    expect(p1.chat.first.reactions['😂']!.length, 2);
    p1.react(host.chat.first.id, '😂'); // toggles off
    expect(host.chat.first.reactions['😂'], ['host']);

    final late = await ClientSession.join(
        dictionary: dict, linkFactory: () => FakeClientLink(net, 'c9'), roomCode: host.roomCode, name: 'Cat', avatar: 0);
    expect(late.chat.map((m) => m.text), ['hi all', 'look']);
    expect(late.chat.last.image, photo);
    await host.leave();
    for (final s in [host, p1, late]) {
      s.dispose();
    }
  });

  test('joining a missing room fails cleanly', () async {
    final net = FakeNetwork();
    expect(
      () => ClientSession.join(
          dictionary: realDictionary(),
          linkFactory: () => FakeClientLink(net, 'x'),
          roomCode: 'ZZZZ',
          name: 'A',
          avatar: 0),
      throwsA(anything),
    );
  });
}
