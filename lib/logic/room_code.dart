/// Room codes, PeerJS ids, and join links.
library;

import 'dart:math';

const String peerIdPrefix = 'mwg-';
const String webOrigin = 'https://michiswordgame.github.io';

/// Letters that are hard to confuse when read aloud or typed.
const String roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const int roomCodeLength = 4;

String generateRoomCode([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
      roomCodeLength, (_) => roomCodeAlphabet[rng.nextInt(roomCodeAlphabet.length)]).join();
}

/// Uppercases and strips anything that cannot be part of a code.
String normalizeRoomCode(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

bool isValidRoomCode(String code) =>
    code.length == roomCodeLength &&
    code.split('').every((c) => roomCodeAlphabet.contains(c));

String hostPeerId(String code) => '$peerIdPrefix${code.toLowerCase()}';

String joinUrl(String code) => '$webOrigin/join?code=$code';

/// Extracts a room code from a join link (app link or web URL), if any.
String? roomCodeFromUri(Uri uri) {
  final raw = uri.queryParameters['code'];
  if (raw == null) return null;
  final code = normalizeRoomCode(raw);
  return isValidRoomCode(code) ? code : null;
}
