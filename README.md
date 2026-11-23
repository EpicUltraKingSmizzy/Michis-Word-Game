# Michi's Word Game

A multiplayer word-grid party game for phones and the web, built with Flutter
(Android, iOS, web). One person hosts on their phone or computer. Everyone else
joins on their own device by scanning a QR code, and you all race to find words
in the same grid of letters.

**Play on the web:** https://michiswordgame.github.io

## How it plays

- **Grid:** 4x4 (Classic), 5x5 (Big), or 6x6 (Super Big), rolled from
  Boggle-style dice with a `Qu` tile. Boards are re-rolled until they have a
  decent number of words.
- **Words:** drag across neighbouring tiles in any of the 8 directions without
  reusing a tile, then let go to submit. The shortest allowed word is 3, 4, or 5
  letters (host's choice).
- **Round length:** 60 to 180 seconds, in 30-second steps.
- **Scoring:** points = letters - 2 (3 letters = 1 point, 4 = 2, ...). Everyone
  who finds a word scores it. A word found by only one player scores **double**.
  American and British spellings (color/colour) count as separate words.
- **Results:** word counts, then a word-by-word replay on a mini grid. Shared
  words come first, then unique words ordered to keep the lead swapping. After
  that come highlights (personal best, most words, longest word, photo
  finish, ...), the longest word on the board, and a confetti winner. Then
  everyone goes back to the room for the next round.
- **Feel:** haptics only, no sound: a tick per tile, a thump for a valid word,
  and a buzz when you score on the results screen.

## Multiplayer

- The host's device runs the game. Players connect straight to it (a star
  topology), so the host is the source of truth for the board, timer, and
  scores.
- Phones find each other through the free public **PeerJS** server
  (`0.peerjs.com`) using the [`peerdart`](https://pub.dev/packages/peerdart)
  client. After that, traffic flows over **WebRTC data channels**. ICE uses
  Google's public STUN server (`stun:stun.l.google.com:19302`) plus PeerJS's
  free public TURN relay as a best-effort fallback.
- Room codes are 4 letters. The host registers the PeerJS id `mwg-<code>`.
- Invite link / QR code: `https://michiswordgame.github.io/join?code=ABCD`.
  On a phone with the app installed, the link opens the app (App Links /
  Universal Links). Otherwise it opens the web version, which joins
  automatically.
- Known limits: STUN-only connections can fail on some mobile-data or strict
  school/work networks. The public PeerJS server has no uptime guarantee. When
  a connection fails, Michi explains it in a speech bubble.
- **Testing on one computer:** open the web build with `?transport=local` in
  two tabs of the same browser (e.g. `/?transport=local` to host and
  `/join?code=ABCD&transport=local` to join). This skips WebRTC and uses a
  `BroadcastChannel`. Add `?debug=1` to log PeerJS traffic in the console.

## Dictionary

`assets/dict/words.txt.gz` is SCOWL size 70, American + British, lowercase a-z,
3+ letters (125,427 words). Rebuild it with `tool/build_dictionary.py`.
`assets/dict/blocklist.txt` lists 87 slurs that are removed when the game
loads. Profanity and sexual words are intentionally kept.

## Customizing

- **Mascot:** `assets/mascot.jpg` is the full illustration, and
  `assets/mascot_face.png` is the round face used on the splash screen and in
  every speech bubble. Replace that file to change the mascot. Keep it square
  with a transparent background outside the circle.
- **App icon:** `assets/icon/app_icon.png` (1024px) plus adaptive Android
  layers, made by `tool/make_icon.py`. After changing them, run
  `dart run flutter_launcher_icons`.

## Project layout

```
lib/logic/   pure game logic (board, dice, trie, solver, path validation,
             scoring, replay order, highlights, room codes): unit tested
lib/net/     transport interfaces, PeerJS link, local (tab) link, fake link
lib/state/   app state, host/player sessions, profile + personal bests
lib/ui/      theme, widgets, screens
test/        unit tests, plus a full host + 2 players session over a fake link
```

Run `flutter analyze`, `flutter test`, then `flutter run` (or
`flutter build web --release --base-href /`).

## Deployment

### Web (GitHub Pages)

`.github/workflows/deploy-web.yml` runs on every push to `main`. It analyzes,
tests, builds the web app, adds `404.html` and `join/index.html` (so
`/join?code=...` works), `.nojekyll`, and the `web_hosting/.well-known` files,
then pushes everything to
[`MichisWordGame/MichisWordGame.github.io`](https://github.com/MichisWordGame/MichisWordGame.github.io)
with an SSH deploy key. Pages serves that repo's `main` branch root.

Setup (one time):
1. In the MichisWordGame organization, allow deploy keys: **Settings → Code,
   planning, and automation → Repository → Deploy keys → Enable**.
2. Add the public key as a **write** deploy key on the org repo
   (`gh api -X POST repos/MichisWordGame/MichisWordGame.github.io/keys -f title=... -f key=... -F read_only=false`).
3. The matching private key is the `PAGES_DEPLOY_KEY` Actions secret in this
   repo (already set).

### App links: what you need to fill in

- **iOS (Universal Links):** in
  `web_hosting/.well-known/apple-app-site-association`, replace `APPLE_TEAM_ID`
  with your Apple Developer Team ID (bundle id
  `io.github.michiswordgame.michisWordGame`). The entitlement
  (`applinks:michiswordgame.github.io`) is already in
  `ios/Runner/Runner.entitlements`.
- **Android (App Links):** `web_hosting/.well-known/assetlinks.json` currently
  lists the interim debug key that signs the v0.1.x APKs (the same key is in
  the `ANDROID_KEYSTORE_*` secrets so tag builds match). When you switch to
  your own key, it must list
  the SHA-256 fingerprint of the key that signs your APK
  (`keytool -list -v -keystore your.keystore`), plus the Play App Signing key
  if you publish on Google Play. The intent filter for
  `https://michiswordgame.github.io/join` is already in `AndroidManifest.xml`.

### Android APK releases

Push a tag like `v0.2.0` and `.github/workflows/android-release.yml` builds a
release APK and attaches it to the GitHub release. To sign with your own key,
add these repo secrets: `ANDROID_KEYSTORE_B64` (base64 of the keystore),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
Locally, create `android/key.properties` with `storeFile`, `storePassword`,
`keyAlias`, and `keyPassword`. Without a key, release builds are signed with a
debug key. They're fine for testing, but Android won't let you upgrade them
to an APK signed with a different key.

## Licenses

Code: GPL-3.0 (see `LICENSE`). Fonts: Fredoka and Montserrat (SIL OFL 1.1, see
`assets/fonts/`). Word list: SCOWL (see http://wordlist.aspell.net, permissive
license).
