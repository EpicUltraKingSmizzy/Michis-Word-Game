# Browser end-to-end check (local transport)

Plays a full round in headless Chrome with three tabs (host + 2 players) over
`?transport=local`, then opens the challenge link in a fourth tab. Checks the
join screen text, chat (messages, reactions, replies), the 3-2-1 countdown,
scoring tap-through, "still viewing results" presence and the Start lock, a
quitter being removed, and the challenge link round trip.

```
flutter build web --release --base-href /
# serve build/web with join/ and challenge/ copies of index.html, e.g.:
#   cp -r build/web /tmp/site && cd /tmp/site && mkdir join challenge &&
#   cp index.html join/ && cp index.html challenge/ && python3 -m http.server 8765
npm install puppeteer-core
BASE=http://localhost:8765 node local_e2e.js
```
Screenshots go to `/workspace/shots/v020`. It expects Chrome at
`/opt/google/chrome/chrome`.

# Real WebRTC multi-player check (`multijoin.js`)

Uses the real PeerJS server and WebRTC, with Playwright's WebKit (the engine
of every iPhone browser) and Firefox. Each player gets its own browser
profile, like separate phones.

```
npm install playwright && npx playwright install webkit firefox
# 1 host + 7 joiners at once, then a round:
BASE=http://localhost:8765 ENGINES=webkit,firefox N=7 MODE=simul PLAY=1 node multijoin.js
# The game-night bug: one friend joins, the host leaves for 10 s to share
# the link (its server socket gets killed), then 3 more join:
BASE=https://michiswordgame.github.io ENGINES=webkit,firefox FIRST=1 N=4 HOST_AWAY=10 AWAY_MODE=kill node multijoin.js
```
`AWAY_MODE=freeze` instead blocks the host page's JavaScript (Android-style
background freeze). Headless WebKit is given microphone permission so it
offers real local addresses instead of `.local` names it can't resolve here.
Chrome isn't used because this box's managed Chrome only allows proxied
WebRTC.
