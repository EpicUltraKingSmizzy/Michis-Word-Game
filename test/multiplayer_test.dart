// Many players joining one room at once, over a fake network that delivers
// messages asynchronously with random delays (like real data channels).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michis_word_game/logic/models.dart';
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/net/fake_link.dart';
import 'package:michis_word_game/net/ice_servers.dart';
import 'package:michis_word_game/state/session.dart';

import 'test_helpers.dart';

Future<void> settle([int ms = 300]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final dict = realDictionary();

  FakeNetwork jitteryNet(int seed) {
    final r = Random(seed);
    return FakeNetwork(latency: () => Duration(milliseconds: r.nextInt(25)));
  }

  Future<ClientSession> join(FakeNetwork net, HostSession host, int i, {String? name}) => ClientSession.join(
        dictionary: dict,
        linkFactory: () => FakeClientLink(net, 'conn$i'),
        roomCode: host.roomCode,
        // Same name on purpose for some players: names aren't identities.
        name: name ?? 'Speller ${i % 3}',
        avatar: i % 4,
      );

  Future<void> playRound(HostSession host, List<ClientSession> clients) async {
    host.updateSettings(const GameSettings(gridSize: 4, minWordLength: 3, durationSeconds: 60));
    await settle();
    host.startGame();
    await settle();
    final all = <GameSession>[host, ...clients];
    for (final s in all) {
      expect(s.phase, SessionPhase.countdown, reason: '${s.myId} got the start');
      expect(s.board!.tiles, host.board!.tiles);
      s.phase = SessionPhase.playing;
    }
    final words = solveBoard(host.board!, dict).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    expect(words.length, greaterThan(all.length));
    // Everyone finds the first word; player i also finds word i+1 alone.
    for (var i = 0; i < all.length; i++) {
      all[i].submitPath(words.first.value);
      all[i].submitPath(words[i + 1].value);
    }
    await settle();
    for (final s in all) {
      s.phase = SessionPhase.waitingForResults;
    }
    host.onBuzzer();
    await Future<void>.delayed(resultsGrace + const Duration(milliseconds: 500));
    for (final s in all) {
      expect(s.phase, SessionPhase.results, reason: '${s.myId} got results');
      expect(s.results!.players.length, all.length);
    }
    for (var i = 0; i < all.length; i++) {
      final mine = host.results!.playerById(all[i].myId)!;
      expect(mine.score, greaterThan(0), reason: 'player $i scored');
    }
  }

  for (final n in [5, 8]) {
    test('$n players join at the same moment and play a round', () async {
      final net = jitteryNet(n);
      final host = await HostSession.create(
          dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Host', avatar: 0, random: Random(3));
      final clients = await Future.wait([for (var i = 1; i < n; i++) join(net, host, i)]);
      await settle();
      expect(host.players.length, n);
      expect(host.players.map((p) => p.id).toSet().length, n, reason: 'unique ids even with equal names');
      for (final c in clients) {
        expect(c.players.length, n, reason: 'every player sees everyone');
      }
      await playRound(host, clients);
      for (final s in [host, ...clients]) {
        s.dispose();
      }
    });
  }

  test('8 players join one after another while the lobby is busy', () async {
    final net = jitteryNet(42);
    final host = await HostSession.create(
        dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Host', avatar: 0, random: Random(5));
    final clients = <ClientSession>[];
    for (var i = 1; i < 8; i++) {
      clients.add(await join(net, host, i));
      // Chat and settings traffic going on while people arrive.
      clients.first.sendChat('hi $i');
      host.updateSettings(GameSettings(gridSize: 4 + i % 2, minWordLength: 3, durationSeconds: 60));
      await settle(50);
    }
    await settle();
    expect(host.players.length, 8);
    expect(clients.last.chat.length, greaterThanOrEqualTo(1));
    for (final c in clients) {
      expect(c.players.length, 8);
    }
    await playRound(host, clients);
    for (final s in [host, ...clients]) {
      s.dispose();
    }
  });

  test("a player who drops and comes back doesn't knock anyone else out", () async {
    final net = jitteryNet(9);
    final host = await HostSession.create(
        dictionary: dict, linkFactory: () => FakeHostLink(net), name: 'Host', avatar: 0, random: Random(1));
    final clients = await Future.wait([for (var i = 1; i < 5; i++) join(net, host, i)]);
    await settle();
    expect(host.players.length, 5);
    // Player 2's connection drops while player 5 joins.
    await clients[1].link.close();
    final p5 = await join(net, host, 5);
    await settle(400);
    expect(host.players.length, 6);
    expect(host.players.map((p) => p.id), containsAll([for (final c in [...clients, p5]) c.myId]));
    for (final s in [host, ...clients, p5]) {
      s.dispose();
    }
  });

  group('ICE servers', () {
    test('keeps only valid STUN/TURN entries', () {
      final parsed = parseIceServers([
        {'urls': 'turn:relay.example.com:3478', 'username': 'u', 'credential': 'p'},
        {'urls': ['turns:relay.example.com:443?transport=tcp', 'https://nope']},
        {'url': 'stun:stun.example.com'},
        {'urls': 'http://bad'},
        'junk',
      ]);
      expect(parsed.length, 3);
      expect(parsed[0]['username'], 'u');
      expect(parsed[1]['urls'], 'turns:relay.example.com:443?transport=tcp');
    });

    test('the default config has STUN and no dead PeerJS relay', () {
      resetIceServersForTest();
      final cfg = currentIceConfig();
      final urls = (cfg['iceServers'] as List).expand((e) {
        final u = (e as Map)['urls'];
        return u is List ? u : [u];
      }).toList();
      expect(urls.any((u) => '$u'.startsWith('stun:')), isTrue);
      expect(urls.any((u) => '$u'.contains('peerjs.com')), isFalse);
      expect(cfg.containsKey('iceTransportPolicy'), isFalse);
      forceRelay = true;
      expect(currentIceConfig()['iceTransportPolicy'], 'relay');
      resetIceServersForTest();
    });
  });
}
