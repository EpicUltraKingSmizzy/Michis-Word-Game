// Real PeerJS/WebRTC multi-join check with Playwright.
// ENGINES=firefox,webkit (host first, then joiners cycle) N=4 MODE=simul|stagger PLAY=1 BASE=...
// QUIT=1 (with PLAY): P1 tries browser back mid-round (must get the quit dialog), the last joiner quits with the Quit button.
const pw = require('playwright');
const BASE = process.env.BASE || 'https://michiswordgame.github.io';
const N = +(process.env.N || 4);
const MODE = process.env.MODE || 'simul';
const PLAY = process.env.PLAY === '1';
const Q = process.env.Q || 'debug=1';
const ENG = (process.env.ENGINES || 'firefox').split(',');
const QUIT = process.env.QUIT === '1';
const VERBOSE = process.env.VERBOSE === '1';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const logs = {};
const t0 = Date.now();
const el = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
async function semantics(page) { await page.evaluate(() => { const el = document.querySelector('flt-semantics-placeholder'); if (el) el.click(); }); await sleep(600); }
async function texts(page) { return page.evaluate(() => Array.from(document.querySelectorAll('flt-semantics, [aria-label], span')).map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean)); }
const allText = async p => (await texts(p)).join(' \n ');
async function clickText(page, re) {
  const ok = await page.evaluate((src) => { const re = new RegExp(src); const el = Array.from(document.querySelectorAll('flt-semantics')).find(e => re.test((e.getAttribute('aria-label') || e.textContent || '').trim()) && (e.getAttribute('role') === 'button' || e.getAttribute('flt-tappable') !== null)); if (!el) return false; el.click(); return true; }, re.source);
  if (!ok) throw new Error('No button ' + re);
}
async function clickLast(page, re) {
  const ok = await page.evaluate((src) => { const re = new RegExp(src); const els = Array.from(document.querySelectorAll('flt-semantics')).filter(e => re.test((e.getAttribute('aria-label') || e.textContent || '').trim()) && (e.getAttribute('role') === 'button' || e.getAttribute('flt-tappable') !== null)); const el = els[els.length - 1]; if (!el) return false; el.click(); return true; }, re.source);
  if (!ok) throw new Error('No button ' + re);
}
async function rectOf(page, re) {
  return page.evaluate((src) => { const re = new RegExp(src); const els = Array.from(document.querySelectorAll('flt-semantics')).filter(e => re.test((e.getAttribute('aria-label') || e.textContent || '').trim())); const el = els.find(e => !e.querySelector('flt-semantics')) || els[0]; if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; }, re.source);
}
async function scrollTo(page, re) {
  for (let i = 0; i < 30; i++) { const r = await rectOf(page, re); if (r && r.y > 60 && r.y < 780) return r; await page.mouse.move(195, 420); await page.mouse.wheel(0, r && r.y < 60 ? -250 : 250); await sleep(250); }
  return rectOf(page, re);
}
async function waitFor(page, re, secs = 30) { for (let i = 0; i < secs * 2; i++) { try { if (re.test(await allText(page))) return true; } catch (_) {} await sleep(500); } return false; }

(async () => {
  const browsers = {};
  const prefs = { 'media.peerconnection.ice.obfuscate_host_addresses': false };
  const mk = async (name, engine) => {
    if (!browsers[engine]) browsers[engine] = await pw[engine].launch(engine === 'firefox' ? { firefoxUserPrefs: prefs } : {});
    const ctx = await browsers[engine].newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: false, permissions: engine === 'webkit' ? ['microphone', 'camera'] : [] });
    // Headless WebKit only offers mDNS host candidates (which it can't resolve
    // here) unless media permission was granted, so grant it and touch the mic.
    if (engine === 'webkit') await ctx.addInitScript(() => { navigator.mediaDevices?.getUserMedia({ audio: true }).catch(() => {}); });
    const page = await ctx.newPage();
    logs[name] = [];
    page.on('pageerror', e => console.log(el(), name, 'pageerror:', e.message));
    page.on('console', m => { const t = m.text(); logs[name].push(el() + ' ' + t); if (VERBOSE || /Michi\]|\[peer\]|Socket closed|Lost connection|taken|Aborting|\[mj\]|Exception|Uncaught/.test(t)) console.log(el(), name, t.replace(/\n/g, ' ').slice(0, 220)); });
    page.engine = engine;
    return page;
  };
  const host = await mk('HOST', ENG[0]);
  await host.context().addInitScript(() => {
    const Real = window.WebSocket; window.__ws = []; window.__blockWs = false;
    window.WebSocket = function (url, p) { const ws = new Real(window.__blockWs ? 'wss://blocked.invalid/' : url, p); window.__ws.push(ws); return ws; };
    window.WebSocket.prototype = Real.prototype; Object.assign(window.WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
  });
  await host.goto(`${BASE}/?${Q}`, { waitUntil: 'networkidle' });
  await sleep(3000); await semantics(host);
  await clickText(host, /Host Game/);
  let code = null;
  for (let i = 0; i < 40 && !code; i++) { await sleep(500); const m = (await allText(host)).match(/Room code\s*\n?\s*([A-Z]{4})/); if (m) code = m[1]; }
  console.log(el(), 'room', code, 'host engine', ENG[0]);
  if (!code) process.exit(2);
  const joiners = [];
  for (let i = 1; i <= N; i++) joiners.push(await mk('P' + i, ENG[i % ENG.length]));
  const join = async (p, i) => {
    const s = Date.now();
    await p.goto(`${BASE}/join?code=${code}&${Q}`, { waitUntil: 'networkidle' });
    await sleep(2500); await semantics(p);
    const ok = await waitFor(p, /Waiting for the host to start|Waiting for .* to start|You're in/, 80);
    console.log(el(), 'P' + i, p.engine, ok ? 'IN after ' + ((Date.now() - s) / 1000).toFixed(1) + 's' : 'NOT IN');
    return ok;
  };
  const OFF = +(process.env.HOST_AWAY || 0);
  // FIRST=1: one friend joins before the host leaves to share the link.
  const firstIn = [];
  const join0 = async (p, i) => {
    const s = Date.now();
    await p.goto(`${BASE}/join?code=${code}&${Q}`, { waitUntil: 'networkidle' });
    await sleep(2500); await semantics(p);
    const ok = await waitFor(p, /Waiting for the host to start|Waiting for .* to start|You're in/, 80);
    console.log(el(), 'P' + i, p.engine, ok ? 'IN after ' + ((Date.now() - s) / 1000).toFixed(1) + 's' : 'NOT IN');
    return ok;
  };
  const everyone = [...joiners];
  if (process.env.FIRST === '1') firstIn.push(await join0(joiners.shift(), 1));
  if (OFF) {
    // Simulate the host switching to another app to send the link: its tab
    // loses the network for OFF seconds while friends start joining.
    const how = process.env.AWAY_MODE || 'kill';
    console.log(el(), 'host away for', OFF, 's, mode', how);
    if (how === 'kill') {
      // iOS-style: the OS kills the tab's server socket while it's in the
      // background, and it can't reconnect until the user comes back.
      await host.evaluate(() => { window.__blockWs = true; window.__ws.forEach(w => w.close()); });
      setTimeout(async () => { await host.evaluate(() => { window.__blockWs = false; window.dispatchEvent(new Event('focus')); }); console.log(el(), 'host back'); }, OFF * 1000);
    } else {
      // Android-style freeze: the page's JS stops (no heartbeats, no replies),
      // but the socket stays up and messages queue up.
      host.evaluate((ms) => { const end = Date.now() + ms; while (Date.now() < end) {} }, OFF * 1000).then(() => console.log(el(), 'host back'));
    }
  }
  let res;
  const off = firstIn.length;
  if (MODE === 'simul') res = await Promise.all(joiners.map((p, i) => join(p, i + 1 + off)));
  else { res = []; for (let i = 0; i < joiners.length; i++) res.push(await join(joiners[i], i + 1 + off)); }
  res = [...firstIn, ...res];
  await sleep(4000);
  const ht = await allText(host);
  const hostPlayers = (ht.match(/joined the room/g) || []).length;
  console.log(el(), 'joiners in:', res.filter(Boolean).length + '/' + N);
  let played = null;
  if (PLAY && res.every(Boolean)) {
    await host.evaluate(() => document.querySelector('input[role=slider]')?.focus());
    for (let i = 0; i < 5; i++) { await host.keyboard.press('ArrowLeft'); await sleep(150); }
    await sleep(500);
    await scrollTo(host, /Start Game/);
    await clickText(host, /Start Game/);
    const started = await Promise.all([host, ...everyone].map(p => waitFor(p, /^[123]$|\n [123] \n/m, 20)));
    console.log(el(), 'countdown seen on', started.filter(Boolean).length, 'of', N + 1);
    let players = [host, ...everyone];
    if (QUIT) {
      await sleep(4000); // into the round
      const p1 = everyone[0];
      const before = p1.url();
      await p1.goBack({ timeout: 3000 }).catch(() => {});
      await semantics(p1);
      const dlg = await waitFor(p1, /Quit this game\?/, 6);
      console.log(el(), 'P1 browser back:', dlg ? 'quit dialog shown' : 'NO DIALOG', p1.url() === before ? '(same page)' : '(url now ' + p1.url() + ')');
      if (dlg) await clickText(p1, /Keep playing/);
      const q = everyone[everyone.length - 1];
      const qName = (await allText(q)).match(/Speller \d+/)?.[0];
      await clickText(q, /Quit/);
      const asked = await waitFor(q, /Quit this game\?/, 6);
      await clickLast(q, /^Quit$/);
      const home = await waitFor(q, /Host Game|Join Game/, 10);
      const gone = await waitFor(host, /left the room/, 15);
      console.log(el(), 'last joiner Quit button:', asked ? 'asked' : 'NOT ASKED', home ? 'left to home' : 'STILL IN ROUND', gone ? 'host saw them leave' : 'HOST DID NOT SEE LEAVE', qName || '');
      players = players.filter(p => p !== q);
      everyone.splice(everyone.length - 1, 1);
    }
    const done = await Promise.all(players.map(p => waitFor(p, /Tap to continue/i, 160)));
    played = done.filter(Boolean).length;
    console.log(el(), 'results reached on', played, 'of', players.length);
    // Everyone's results list every player.
    const names = logs.HOST.map(l => (l.match(/\[Michi\] (.+) joined the room/) || [])[1]).filter(Boolean);
    for (const [i, p] of [host, ...everyone].entries()) {
      for (let k = 0; k < 12; k++) { await p.mouse.click(195, 500); await sleep(400); }
      const t = await allText(p);
      const missing = names.filter(n => !t.includes(n));
      console.log(el(), i ? 'P' + i : 'HOST', 'results list', missing.length ? 'MISSING ' + missing.join(', ') : 'has all ' + names.length + ' joiners');
    }
  }
  require('fs').writeFileSync(`/tmp/pw-logs-${MODE}-${N}.json`, JSON.stringify(logs, null, 1));
  console.log('RESULT', JSON.stringify({ N, MODE, engines: ENG, in: res.filter(Boolean).length, played }));
  for (const b of Object.values(browsers)) await b.close();
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
