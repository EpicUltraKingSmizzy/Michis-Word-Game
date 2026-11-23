import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/dictionary.dart';
import '../logic/models.dart';
import '../logic/room_code.dart';
import '../logic/word_list.dart';
import '../net/link.dart';
import '../net/peer_link.dart';
import 'profile_store.dart';
import 'session.dart';

enum AppScreen { splash, join }

/// Top-level app state: profile, dictionary, and the current room.
class AppState extends ChangeNotifier {
  AppState({
    HostLink Function()? hostLinkFactory,
    ClientLink Function()? clientLinkFactory,
  })  : _hostLinkFactory = hostLinkFactory ?? PeerHostLink.new,
        _clientLinkFactory = clientLinkFactory ?? PeerClientLink.new;

  final HostLink Function() _hostLinkFactory;
  final ClientLink Function() _clientLinkFactory;

  ProfileStore? _store;
  Dictionary? dictionary;
  String? loadError;

  String name = '';
  int avatar = 0;

  AppScreen screen = AppScreen.splash;
  GameSession? session;
  StreamSubscription<String>? _sessionSays;
  bool busy = false;

  /// Room code from a join link, waiting for the dictionary to finish loading.
  String? pendingJoinCode;

  /// Code to prefill on the join screen.
  String joinCodeDraft = '';

  GameSettings lastSettings = const GameSettings();

  final _mascot = StreamController<String>.broadcast();
  Stream<String> get mascotMessages => _mascot.stream;
  void say(String text) {
    debugPrint('[Michi] $text');
    _mascot.add(text);
  }

  bool get ready => dictionary != null && _store != null;

  Future<void> init({Future<Dictionary> Function()? loadDictionary}) async {
    _store = await ProfileStore.load();
    name = _store!.name;
    avatar = _store!.avatar;
    notifyListeners();
    try {
      dictionary = await (loadDictionary ?? _loadBundledDictionary)();
    } catch (e) {
      loadError = 'I lost my dictionary! ($e)';
    }
    notifyListeners();
    final code = pendingJoinCode;
    if (code != null && ready) {
      pendingJoinCode = null;
      unawaited(joinGame(code));
    }
  }

  static Future<Dictionary> _loadBundledDictionary() async {
    final words = await rootBundle.load('assets/dict/words.txt.gz');
    final blocked = await rootBundle.loadString('assets/dict/blocklist.txt');
    return compute(_buildDictionary, (words.buffer.asUint8List(), blocked));
  }

  static Dictionary _buildDictionary((Uint8List, String) input) =>
      dictionaryFromAssets(input.$1, input.$2);

  ProfileStore? get store => _store;

  Future<void> updateProfile(String newName, int newAvatar) async {
    name = newName.trim().isEmpty ? name : newName.trim();
    if (name.length > 16) name = name.substring(0, 16);
    avatar = newAvatar;
    await _store?.save(name: name, avatar: avatar);
    session?.updateProfile(name, avatar);
    notifyListeners();
  }

  void showJoin([String code = '']) {
    joinCodeDraft = code;
    screen = AppScreen.join;
    notifyListeners();
  }

  void showSplash() {
    screen = AppScreen.splash;
    notifyListeners();
  }

  /// Called for app links and the web URL (…/join?code=ABCD).
  void handleLink(Uri uri) {
    final code = roomCodeFromUri(uri);
    if (code == null) return;
    if (session != null) {
      if (session!.roomCode != code) {
        say('Leave this game first, then open the new invite link.');
      }
      return;
    }
    if (!ready) {
      pendingJoinCode = code;
      return;
    }
    unawaited(joinGame(code));
  }

  Future<void> hostGame() async {
    if (busy || !ready) return;
    busy = true;
    notifyListeners();
    try {
      final s = await HostSession.create(
        dictionary: dictionary!,
        linkFactory: _hostLinkFactory,
        name: name,
        avatar: avatar,
        settings: lastSettings,
      );
      _attach(s);
    } on LinkException catch (e) {
      say(e.message);
    } catch (e) {
      say("Something went wrong opening the room. Try again! ($e)");
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> joinGame(String rawCode) async {
    if (busy || !ready || session != null) return;
    final code = normalizeRoomCode(rawCode);
    if (!isValidRoomCode(code)) {
      say('Room codes are $roomCodeLength letters, like ABCD. Check the code and try again!');
      return;
    }
    busy = true;
    joinCodeDraft = code;
    notifyListeners();
    try {
      final s = await ClientSession.join(
        dictionary: dictionary!,
        linkFactory: _clientLinkFactory,
        roomCode: code,
        name: name,
        avatar: avatar,
      );
      _attach(s);
    } on LinkException catch (e) {
      screen = AppScreen.join;
      say(e.message);
    } catch (e) {
      screen = AppScreen.join;
      say("I couldn't join that game. Try again! ($e)");
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _attach(GameSession s) {
    session = s;
    _sessionSays = s.mascotMessages.listen(say);
    s.addListener(_onSession);
    notifyListeners();
  }

  void _onSession() {
    final s = session;
    if (s == null) return;
    if (s is HostSession) lastSettings = s.settings;
    final reason = s.endedReason;
    if (reason != null) {
      _detach();
      screen = AppScreen.splash;
      say(reason);
    }
    notifyListeners();
  }

  void _detach() {
    final s = session;
    session = null;
    _sessionSays?.cancel();
    if (s != null) {
      s.removeListener(_onSession);
      // Let any frame using it finish first.
      scheduleMicrotask(s.dispose);
    }
  }

  Future<void> leaveSession() async {
    final s = session;
    if (s == null) return;
    _detach();
    screen = AppScreen.splash;
    notifyListeners();
    await s.leave();
  }
}
