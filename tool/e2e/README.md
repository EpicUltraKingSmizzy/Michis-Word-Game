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
