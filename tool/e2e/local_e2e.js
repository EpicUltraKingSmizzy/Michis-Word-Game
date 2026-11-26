// v0.2.0 local-transport checks: chat, countdown, scoring trace, tap-through,
// presence (players still on results), challenge link round trip.
const puppeteer = require('puppeteer-core');
const BASE = process.env.BASE || 'http://localhost:8765';
const Q = 'transport=local';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const DIR = '/workspace/shots/v020';
const shot = async (p, n) => { await p.bringToFront(); await sleep(400); await p.screenshot({ path: `${DIR}/${n}.png` }); };
const results = [];
const check = (name, ok, extra = '') => { results.push([name, ok]); console.log((ok ? 'PASS ' : 'FAIL ') + name + (extra ? ' :: ' + extra : '')); };
let challengeUrl = null;

async function semantics(page) {
  await page.evaluate(() => { const el = document.querySelector('flt-semantics-placeholder'); if (el) el.click(); });
  await sleep(600);
}
async function texts(page) {
  return page.evaluate(() => Array.from(document.querySelectorAll('flt-semantics, [aria-label], span'))
    .map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean));
}
const allText = async p => { await p.bringToFront(); await sleep(250); return (await texts(p)).join(' \n '); };
async function clickText(page, re, { last = false } = {}) {
  await page.bringToFront(); await sleep(300);
  const ok = await page.evaluate((src, last) => {
    const re = new RegExp(src);
    const els = Array.from(document.querySelectorAll('flt-semantics')).filter(e => re.test((e.getAttribute('aria-label') || e.textContent || '').trim()) && (e.getAttribute('role') === 'button' || e.getAttribute('flt-tappable') !== null));
    const el = last ? els[els.length - 1] : els[0];
    if (!el) return false;
    el.click();
    return true;
  }, re.source, last);
  if (!ok) throw new Error('No button ' + re);
}
async function rectOf(page, re) {
  return page.evaluate((src) => {
    const re = new RegExp(src);
    const els = Array.from(document.querySelectorAll('flt-semantics')).filter(e => re.test((e.getAttribute('aria-label') || e.textContent || '').trim()));
    const el = els.find(e => !e.querySelector('flt-semantics')) || els[0];
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, l: r.left, t: r.top, w: r.width, h: r.height };
  }, re.source);
}
async function waitFor(page, re, secs = 30) {
  for (let i = 0; i < secs * 2; i++) { if (re.test(await allText(page))) return true; await sleep(500); }
  return false;
}
async function scrollTo(page, re) {
  await page.bringToFront(); await sleep(300);
  for (let i = 0; i < 30; i++) {
    const r = await rectOf(page, re);
    if (r && r.y > 60 && r.y < 780) return r;
    await page.mouse.move(195, 420);
    await page.mouse.wheel({ deltaY: r && r.y < 60 ? -250 : 250 });
    await sleep(250);
  }
  return rectOf(page, re);
}
async function typeChat(page, text) {
  await scrollTo(page, /Say hi|Chat/);
  for (let i = 0; i < 12; i++) { await page.mouse.move(195, 420); await page.mouse.wheel({ deltaY: 300 }); await sleep(120); }
  await sleep(400);
  const r = await page.evaluate(() => { const e = document.querySelector('textarea[aria-label="Message"], input[aria-label="Message"]'); if (!e) return null; const b = e.getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2 }; });
  if (!r) throw new Error('no Message field');
  await page.mouse.click(r.x, r.y);
  await sleep(500);
  await page.keyboard.type(text, { delay: 20 });
  await sleep(200);
  await page.keyboard.press('Enter');
  await sleep(600);
}
const touchDrag = async (page, pts) => {
  const cdp = await page.createCDPSession();
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: pts[0][0], y: pts[0][1] }] });
  let [px, py] = pts[0];
  for (const [x, y] of pts.slice(1)) {
    for (let k = 1; k <= 8; k++) { await sleep(12); await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: px + (x - px) * k / 8, y: py + (y - py) * k / 8 }] }); }
    [px, py] = [x, y];
  }
  await sleep(50);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
};

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/opt/google/chrome/chrome', headless: 'new', protocolTimeout: 120000,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--user-data-dir=/tmp/pp-' + Date.now()],
  });
  const ctx = browser.defaultBrowserContext();
  const mk = async (name) => {
    const page = await ctx.newPage();
    await page.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true });
    page.on('pageerror', e => console.log(name, 'pageerror:', e.message));
    page.on('console', m => {
      const t = m.text();
      const c = t.match(/\[challenge\] (\S+)/);
      if (c) challengeUrl = c[1];
      if (/Michi\]|challenge|rror/.test(t)) console.log(name, 'console:', t.slice(0, 200));
    });
    return page;
  };

  // ---- Host opens a room ----
  const host = await mk('HOST');
  await host.goto(`${BASE}/?${Q}`, { waitUntil: 'networkidle0' });
  await sleep(4000); await semantics(host);
  await clickText(host, /Host Game/);
  let code = null;
  for (let i = 0; i < 30 && !code; i++) { await sleep(500); const m = (await allText(host)).match(/Room code\s*\n?\s*([A-Z]{4})/); if (m) code = m[1]; }
  if (!code) { const m = (await allText(host)).match(/\b([A-Z]{4})\b/g); console.log('codes?', m); }
  check('host opened room', !!code, code);
  // Shortest round: 60s (slider all the way left).
  await host.evaluate(() => document.querySelector('input[role=slider]')?.focus());
  for (let i = 0; i < 5; i++) { await host.keyboard.press('ArrowLeft'); await sleep(200); }
  await sleep(500);
  check('duration set to 1:00', /1:00/.test(await allText(host)));

  // ---- Join screen text ----
  const p1 = await mk('P1');
  await p1.goto(`${BASE}/?${Q}`, { waitUntil: 'networkidle0' });
  await sleep(4000); await semantics(p1);
  await clickText(p1, /Join Game/); await sleep(1200);
  const jt = await allText(p1);
  check('join help text', jt.includes("Scan the host's QR code or type in the room code below!"));
  check('room code label', /Room code/.test(jt) && !/Or type the room code/.test(jt));
  check('scan button on web', /Scan QR code/.test(jt));
  await shot(p1, 'join_screen');

  // ---- Players join via link ----
  await p1.goto(`${BASE}/join?code=${code}&${Q}`, { waitUntil: 'networkidle0' });
  await sleep(3000); await semantics(p1);
  check('P1 joined', await waitFor(p1, /Waiting for|You're in/, 20));
  const p2 = await mk('P2');
  await p2.goto(`${BASE}/join?code=${code}&${Q}`, { waitUntil: 'networkidle0' });
  await sleep(3000); await semantics(p2);
  check('P2 joined', await waitFor(p2, /Waiting for|You're in/, 20));

  // ---- Chat ----
  await p1.bringToFront();
  await typeChat(p1, 'hello from p1');
  await scrollTo(host, /Say hi|Chat/);
  for (let i = 0; i < 12; i++) { await host.mouse.move(195, 420); await host.mouse.wheel({ deltaY: 300 }); await sleep(100); }
  check('host sees P1 chat', await waitFor(host, /hello from p1/, 10));
  check('P2 sees P1 chat', await waitFor(p2, /hello from p1/, 10));
  await host.bringToFront();
  await typeChat(host, 'welcome all');
  check('P1 sees host chat', await waitFor(p1, /welcome all/, 10));
  // Long-press P2's copy of P1's message and react.
  await p2.bringToFront();
  const bub = await scrollTo(p2, /hello from p1/);
  if (bub) {
    const cdp = await p2.createCDPSession();
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: bub.x, y: bub.y }] });
    await sleep(900);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await sleep(900);
    await shot(p2, 'chat_menu');
    const r = await rectOf(p2, /😂/);
    console.log('emoji rect', JSON.stringify(r));
    if (r) { const c2 = await p2.createCDPSession(); await c2.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: r.x, y: r.y }] }); await sleep(80); await c2.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); }
    await sleep(800);
  }
  await host.bringToFront();
  for (let i = 0; i < 12; i++) { await host.mouse.move(195, 420); await host.mouse.wheel({ deltaY: 300 }); await sleep(100); }
  check('reaction reaches host', await waitFor(host, /😂 1/, 8));
  await shot(host, 'host_chat');
  await shot(p2, 'p2_chat');

  // Reply: long-press -> Reply -> send; the quote shows in the bubble.
  {
    const b2 = await scrollTo(p2, /welcome all/);
    const cdp = await p2.createCDPSession();
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: b2.x, y: b2.y }] });
    await sleep(900);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await sleep(900);
    await clickText(p2, /^Reply$/);
    await sleep(600);
    check('reply preview above input', /Replying to/.test(await allText(p2)));
    await p2.keyboard.type('thanks host', { delay: 20 });
    await p2.keyboard.press('Enter');
    await sleep(1000);
    await shot(p2, 'p2_reply');
    await host.bringToFront();
    for (let i = 0; i < 12; i++) { await host.mouse.move(195, 420); await host.mouse.wheel({ deltaY: 300 }); await sleep(100); }
    const t = await allText(host);
    check('host sees reply with quote', /thanks host/.test(t) && /welcome all[\s\S]*welcome all|welcome all[\s\S]*thanks host/.test(t));
    await shot(host, 'host_reply');
  }
  if (process.env.QUICK) { await shot(p2, 'p2_after_react'); await browser.close(); process.exit(0); }
  // ---- Start + countdown ----
  await host.bringToFront();
  await scrollTo(host, /Start Game/);
  await clickText(host, /Start Game/);
  await p1.bringToFront();
  const seen = new Set();
  const t0 = Date.now();
  while (Date.now() - t0 < 3400) {
    const t = await texts(p1);
    for (const n of ['3', '2', '1']) if (t.includes(n)) seen.add(n);
    await sleep(120);
  }
  check('countdown shows 3, 2, 1', seen.has('3') && seen.has('2') && seen.has('1'), [...seen].join(','));

  // ---- Play a few words ----
  await sleep(800);
  await p1.bringToFront(); await sleep(500);
  const leaves = await p1.evaluate(() => Array.from(document.querySelectorAll('flt-semantics')).filter(e => !e.querySelector('flt-semantics')).map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()));
  const tiles = leaves.filter(t => /^([A-Z]|Qu)$/.test(t));
  const n = Math.round(Math.sqrt(tiles.length));
  const words = new Set(require('zlib').gunzipSync(require('fs').readFileSync('/workspace/Michis-Word-Game/assets/dict/words.txt.gz')).toString().split('\n'));
  const adj = (a, b) => a !== b && Math.abs((a / n | 0) - (b / n | 0)) <= 1 && Math.abs(a % n - b % n) <= 1;
  const list = []; const seenW = new Set();
  for (let a = 0; a < n * n; a++) for (let b = 0; b < n * n; b++) for (let c = 0; c < n * n; c++) for (let d = -1; d < n * n; d++) {
    if (!adj(a, b) || !adj(b, c) || a === c) continue;
    if (d >= 0 && (!adj(c, d) || d === a || d === b)) continue;
    const path = d >= 0 ? [a, b, c, d] : [a, b, c];
    const w = path.map(i => tiles[i]).join('').toLowerCase();
    if (words.has(w) && !seenW.has(w)) { seenW.add(w); list.push(path); }
  }
  console.log('board', tiles.join(''), 'words', list.length);
  const rects = await p1.evaluate(() => Array.from(document.querySelectorAll('flt-semantics')).filter(e => /^([A-Z]|Qu)$/.test((e.textContent || '').trim()) && !e.querySelector('flt-semantics')).map(e => { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; }));
  for (const path of list.slice(0, 6)) { await touchDrag(p1, path.map(i => rects[i])); await sleep(300); }
  await p2.bringToFront();
  for (const path of list.slice(4, 8)) { await touchDrag(p2, path.map(i => rects[i])); await sleep(300); }
  await host.bringToFront();
  for (const path of list.slice(7, 12)) { await touchDrag(host, path.map(i => rects[i])); await sleep(300); }

  // ---- Results ----
  await p1.bringToFront();
  check('round ended', await waitFor(p1, /Time's up/i, 75));
  await sleep(3000);
  for (let i = 0; i < 12; i++) { await p1.screenshot({ path: `${DIR}/replay_${i}.png` }); await sleep(60); }
  // Tap-through: wait for the hint, then tap.
  check('tap hint after scoring', await waitFor(p1, /Tap to continue/, 40));
  await shot(p1, 'p1_scores_done');
  await sleep(2500);
  check('waits for tap (no auto-advance)', !/highlights/.test(await allText(p1)));
  await clickText(p1, /Tap to continue/);
  check('tap -> highlights', await waitFor(p1, /highlights/, 5));
  await shot(p1, 'p1_highlights');

  // Host skips to the end and goes back to the room while P1/P2 are on results.
  await host.bringToFront();
  try { await clickText(host, /Skip/); } catch (_) {}
  await sleep(1500);
  check('host: Skip lands on highlights, not the winner', /Tap to continue/.test(await allText(host)) && !/Back to the room/.test(await allText(host)));
  for (let i = 0; i < 4 && !/Back to the room/.test(await allText(host)); i++) { try { await clickText(host, /Tap to continue/); } catch (_) {} await sleep(900); }
  await clickText(host, /Back to the room/);
  await sleep(1500);
  await scrollTo(host, /Start Game/);
  const ht = await allText(host);
  check('host: players shown viewing results', /Still viewing results/.test(ht));
  check('host: start blocked with reason', /Waiting: .*still viewing results/.test(ht));
  check('host: no disconnect message', !/left the room|lost their connection/.test(ht));
  await scrollTo(host, /Still viewing results/);
  await shot(host, 'host_waiting_for_results');
  // Settings + chat while players are on results.
  await clickText(host, /5 letters/);
  await typeChat(host, 'next round soon');
  // P1 taps through to the end.
  await p1.bringToFront();
  for (let i = 0; i < 4; i++) { try { await clickText(p1, /Tap to continue/); } catch (_) {} await sleep(700); }
  check('P1 reaches winner screen', await waitFor(p1, /Challenge a friend/, 10));
  await shot(p1, 'p1_winner');
  await clickText(p1, /Challenge a friend/);
  await sleep(1500);
  check('challenge link generated', !!challengeUrl, challengeUrl && challengeUrl.length + ' chars');
  await clickText(p1, /Back to the room/);
  await sleep(1200);
  const p1t = await allText(p1);
  check('P1 back in room sees new settings', /5\+/.test(p1t));
  check('P1 sees chat sent while on results', /next round soon/.test(p1t));
  await scrollTo(host, /Start Game/);
  check('host still blocked by P2', /Waiting: .*still viewing results/.test(await allText(host)));
  await p2.bringToFront();
  try { await clickText(p2, /Skip/); } catch (_) {}
  await sleep(1500);
  for (let i = 0; i < 4 && !/Back to the room/.test(await allText(p2)); i++) { try { await clickText(p2, /Tap to continue/); } catch (_) {} await sleep(900); }
  await clickText(p2, /Back to the room/);
  await sleep(1200);
  await scrollTo(host, /Start Game/);
  const ht2 = await allText(host);
  check('host: start enabled after everyone is back', !/Waiting: /.test(ht2) && !/Still viewing results/.test(ht2));
  check('host: still 3 players', /Players \(3\)/.test(ht2));
  await shot(host, 'host_all_back');

  // P2 quits: removed right away.
  await p2.bringToFront();
  await clickText(p2, /Leave room/);
  await sleep(1500);
  check('quitter removed from host list', /Players \(2\)/.test(await allText(host)));

  // ---- Challenge link round trip ----
  if (challengeUrl) {
    const u = new URL(challengeUrl);
    const friend = await mk('FRIEND');
    await friend.goto(`${BASE}/challenge${u.search}`, { waitUntil: 'networkidle0' });
    await sleep(4000); await semantics(friend);
    check('challenge screen', await waitFor(friend, /challenged you/, 15));
    await shot(friend, 'challenge_intro');
    const introT = await allText(friend);
    check('challenge intro hides the score as ???', /\?\?\?/.test(introT) && !/\d+ words?/.test(introT), '');
    await scrollTo(friend, /^Play/);
    await clickText(friend, /^Play/);
    await sleep(4500);
    const fl = await friend.evaluate(() => Array.from(document.querySelectorAll('flt-semantics')).filter(e => !e.querySelector('flt-semantics')).map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()));
    const ftiles = fl.filter(t => /^([A-Z]|Qu)$/.test(t));
    check('challenge board matches original', ftiles.join('') === tiles.join(''), ftiles.join(''));
    // Browser back mid-round asks instead of leaving the page.
    const urlBefore = friend.url();
    await friend.goBack({ timeout: 3000 }).catch(() => {});
    await sleep(1200); await semantics(friend);
    check('browser back during a round shows the quit dialog', await waitFor(friend, /Quit this game\?/, 5));
    check('browser back keeps the page', friend.url().startsWith(BASE), friend.url() + ' (was ' + urlBefore + ')');
    await shot(friend, 'back_quit_dialog');
    await clickText(friend, /Keep playing/);
    await sleep(800);
    check('Keep playing returns to the round', !/Quit this game/.test(await allText(friend)) && /Quit/.test(await allText(friend)));
    check('challenge results', await waitFor(friend, /Time's up/i, 75));
    await sleep(2500);
    const replayT = await allText(friend);
    await clickText(friend, /Skip/);
    await sleep(1500);
    check('challenge Skip lands on highlights', /Tap to continue/.test(await allText(friend)));
    const ft = await allText(friend);
    for (let i = 0; i < 4 && !/Challenge a friend|Play again|Back home|Done/.test(await allText(friend)); i++) { try { await clickText(friend, /Tap to continue/); } catch (_) {} await sleep(900); }
    const winT = await allText(friend);
    await shot(friend, 'challenge_winner');
    const rows = (winT.match(/\d+ words?/g) || []).length;
    check('challenge winner page lists the challengers and the friend', rows >= 4, rows + ' rows');
    check('real challenger scores shown after scoring', !/\?\?\?/.test(winT));
    await shot(friend, 'challenge_results');
  }

  const failed = results.filter(r => !r[1]);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  if (failed.length) console.log('FAILED:', failed.map(f => f[0]).join('; '));
  await browser.close();
  process.exit(failed.length ? 1 : 0);
})().catch(e => { console.error('E2E error', e); process.exit(3); });
