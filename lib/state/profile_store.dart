import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/models.dart';
import '../ui/avatars.dart';

/// The player's name, avatar, and personal records, saved on this device.
class ProfileStore {
  ProfileStore._(this._prefs);

  static Future<ProfileStore> load() async =>
      ProfileStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kName = 'name';
  static const _kAvatar = 'avatar';
  static const _kBest = 'best_score';

  static const _funNames = [
    'Wordy', 'Speller', 'Lexi', 'Scrabbles', 'Vowelina', 'Captain Q', 'Syllabob', 'Letterbug',
  ];

  String get name {
    final n = _prefs.getString(_kName);
    if (n != null && n.trim().isNotEmpty) return n;
    final r = Random();
    final generated = '${_funNames[r.nextInt(_funNames.length)]} ${r.nextInt(90) + 10}';
    _prefs.setString(_kName, generated);
    return generated;
  }

  int get avatar {
    final a = _prefs.getInt(_kAvatar);
    if (a != null) return a % avatarStyles.length;
    final generated = Random().nextInt(avatarStyles.length);
    _prefs.setInt(_kAvatar, generated);
    return generated;
  }

  Future<void> save({required String name, required int avatar}) async {
    await _prefs.setString(_kName, name.trim().isEmpty ? this.name : name.trim());
    await _prefs.setInt(_kAvatar, avatar);
  }

  String _configKey(GameSettings s) =>
      'best_${s.gridSize}_${s.durationSeconds}_${s.minWordLength}';

  /// Records a round score. Returns which records it beat.
  Future<PersonalRecord> recordScore(GameSettings settings, int score) async {
    final prevBest = _prefs.getInt(_kBest);
    final prevConfig = _prefs.getInt(_configKey(settings));
    final overall = score > 0 && (prevBest == null || score > prevBest);
    final config = score > 0 && (prevConfig == null || score > prevConfig);
    if (overall) await _prefs.setInt(_kBest, score);
    if (config) await _prefs.setInt(_configKey(settings), score);
    return PersonalRecord(
      newOverallBest: overall && prevBest != null,
      newConfigBest: config && prevConfig != null,
      firstGame: prevBest == null,
      previousBest: prevBest,
    );
  }
}

class PersonalRecord {
  const PersonalRecord({
    required this.newOverallBest,
    required this.newConfigBest,
    required this.firstGame,
    this.previousBest,
  });
  final bool newOverallBest;
  final bool newConfigBest;
  final bool firstGame;
  final int? previousBest;
}
