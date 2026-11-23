Files in this folder are copied to the root of https://michiswordgame.github.io
by the deploy workflow, next to the Flutter web build.

- `.well-known/apple-app-site-association`: lets iPhones open invite links in
  the app. Replace `APPLE_TEAM_ID` with your Apple Developer Team ID.
- `.well-known/assetlinks.json`: lets Android open invite links in the app.
  `sha256_cert_fingerprints` must list the SHA-256 of the certificate that
  signs the APK/AAB you ship (and the Play App Signing key if you use Play).
