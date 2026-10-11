// End-to-end checks of the fetch handler with a fake Cache API and a fake
// upstream fetch. Each test uses its own coordinates because the Worker keeps
// per-isolate state (memory cache, backoff) at module level.
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const store = new Map();
globalThis.caches = {
  default: {
    async match(key) {
      const v = store.get(key);
      return v ? new Response(v.body, { headers: v.headers }) : undefined;
    },
    async put(key, res) {
      store.set(key, { body: await res.text(), headers: [...res.headers] });
    },
  },
};

let calls;
let nextUpstream;
globalThis.fetch = async (url, init) => {
  calls.push({ url, headers: init.headers });
  const r = nextUpstream();
  if (r instanceof Error) throw r;
  return r;
};

const env = { USER_AGENT: 'Test-UA/1 test@example.com' };
function ctx() {
  const pending = [];
  return { waitUntil: (p) => pending.push(p), done: () => Promise.all(pending) };
}
async function call(path, init = {}) {
  const c = ctx();
  const res = await worker.fetch(new Request(`https://proxy.test${path}`, init), env, c);
  await c.done();
  return res;
}
const P = '/weatherapi/locationforecast/2.0/complete';
const inFuture = (s) => new Date(Date.now() + s * 1000).toUTCString();
const LM = 'Thu, 01 Jan 2026 00:00:00 GMT';
const ok = (expires, body = '{"ok":1}') =>
  new Response(body, {
    status: 200,
    headers: { 'Content-Type': 'application/json', Expires: expires, 'Last-Modified': LM },
  });

beforeEach(() => {
  calls = [];
  nextUpstream = () => ok(inFuture(600));
});

test('health and routing', async () => {
  assert.equal(await (await call('/health')).text(), 'ok');
  assert.equal((await call('/nope')).status, 404);
  assert.equal((await call(`${P}?lat=1&lon=1`, { method: 'POST' })).status, 405);
  const bad = await call(`${P}?lat=95&lon=1`);
  assert.equal(bad.status, 400);
  assert.match((await bad.json()).error, /lat/);
  assert.equal(calls.length, 0);
});

test('MISS then HIT, quantized upstream URL, clean upstream headers', async () => {
  const r1 = await call(`${P}?lat=59.91387&lon=10.75225`, {
    headers: { 'User-Agent': 'client', Cookie: 'a=b', 'X-Forwarded-For': '1.2.3.4' },
  });
  assert.equal(r1.status, 200);
  assert.equal(r1.headers.get('x-skyline-cache'), 'MISS');
  assert.equal(r1.headers.get('last-modified'), LM);
  assert.ok(r1.headers.get('expires'));
  assert.equal(await r1.text(), '{"ok":1}');
  assert.equal(calls[0].url, `https://api.met.no${P}?lat=59.91&lon=10.75`);
  assert.deepEqual(Object.keys(calls[0].headers).sort(), ['Accept-Encoding', 'User-Agent']);
  assert.equal(calls[0].headers['User-Agent'], env.USER_AGENT);

  const r2 = await call(`${P}?lon=10.7524&lat=59.9141`);
  assert.equal(r2.headers.get('x-skyline-cache'), 'HIT');
  assert.equal(calls.length, 1);
});

test('client If-Modified-Since gets 304', async () => {
  await call(`${P}?lat=1.11&lon=1.11`);
  const r = await call(`${P}?lat=1.11&lon=1.11`, { headers: { 'If-Modified-Since': LM } });
  assert.equal(r.status, 304);
  assert.equal(calls.length, 1);
});

test('expired entry revalidates with If-Modified-Since', async () => {
  nextUpstream = () => ok(new Date(Date.now() - 1000).toUTCString());
  await call(`${P}?lat=2.22&lon=2.22`);
  nextUpstream = () => new Response(null, { status: 304, headers: { Expires: inFuture(600) } });
  const r = await call(`${P}?lat=2.22&lon=2.22`);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('x-skyline-cache'), 'REVALIDATED');
  assert.equal(await r.text(), '{"ok":1}');
  assert.equal(calls[1].headers['If-Modified-Since'], LM);
  assert.equal((await call(`${P}?lat=2.22&lon=2.22`)).headers.get('x-skyline-cache'), 'HIT');
  assert.equal(calls.length, 2);
});

test('429 with stale entry serves STALE and backs off', async () => {
  nextUpstream = () => ok(new Date(Date.now() - 1000).toUTCString());
  await call(`${P}?lat=3.33&lon=3.33`);
  nextUpstream = () => new Response('slow down', { status: 429, headers: { 'Retry-After': '120' } });
  const r = await call(`${P}?lat=3.33&lon=3.33`);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('x-skyline-cache'), 'STALE');
  assert.equal(r.headers.get('x-skyline-stale'), '1');
  assert.ok(Date.parse(r.headers.get('expires')) > Date.now());
  const r2 = await call(`${P}?lat=3.33&lon=3.33`);
  assert.equal(r2.headers.get('x-skyline-cache'), 'STALE');
  assert.equal(calls.length, 2); // no third upstream call during backoff
});

test('5xx without cache returns status with Retry-After', async () => {
  nextUpstream = () => new Response('down', { status: 503 });
  const r = await call(`${P}?lat=4.44&lon=4.44`);
  assert.equal(r.status, 503);
  assert.equal(r.headers.get('retry-after'), '60');
});

test('network error without cache returns 502', async () => {
  nextUpstream = () => new Error('boom');
  const r = await call(`${P}?lat=5.55&lon=5.55`);
  assert.equal(r.status, 502);
  assert.equal(r.headers.get('retry-after'), '60');
});

test('HEAD returns headers without body', async () => {
  const r = await call(`${P}?lat=6.66&lon=6.66`, { method: 'HEAD' });
  assert.equal(r.status, 200);
  assert.equal(await r.text(), '');
});
