// Skyline proxy: a small caching proxy in front of MET Norway's
// Locationforecast 2.0 API. It serves the same path and query shape as
// api.met.no, so the app can swap base URLs without other changes.
//
// What it does for MET's terms of service:
//  - sends an identifying User-Agent on every upstream request
//  - rounds lat/lon to 2 decimals (MET allows at most 4), so MET never sees
//    a user's precise location and nearby users share cache entries
//  - caches every response and never asks MET again before Expires
//  - revalidates with If-Modified-Since after Expires
//  - backs off after 429, serves stale data on 429/5xx when it can
//  - never forwards client IPs, cookies or client headers upstream

import {
  FORECAST_PATH,
  DEFAULT_USER_AGENT,
  STORE_TTL_SECONDS,
  DEFAULT_RETRY_AFTER_SECONDS,
  parseForecastQuery,
  cacheKeyUrl,
  upstreamUrl,
  expiresFromHeaders,
  parseRetryAfter,
  decideBeforeUpstream,
  classifyUpstream,
  clientHasCurrent,
  httpDate,
} from './lib.js';

// Per-isolate state. Isolates are reused across requests but may be
// recycled at any time, so this is only a best-effort layer.
const backoff = new Map(); // cache key -> epoch ms until which MET is not called
const memory = new Map(); // cache key -> entry (small L1; see README about workers.dev)
const MEMORY_MAX = 500;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const isRead = request.method === 'GET' || request.method === 'HEAD';

    if (url.pathname === '/health') {
      if (!isRead) return methodNotAllowed();
      return new Response(request.method === 'HEAD' ? null : 'ok', {
        headers: { 'Content-Type': 'text/plain' },
      });
    }
    if (url.pathname !== FORECAST_PATH) return jsonError(404, 'not found');
    if (!isRead) return methodNotAllowed();

    const query = parseForecastQuery(url.searchParams);
    if (!query.ok) return jsonError(400, query.error);

    const key = cacheKeyUrl(url.origin, query);
    const now = Date.now();
    let entry = await loadEntry(key);

    const decision = decideBeforeUpstream({ entry, now, backoffUntil: backoff.get(key) });
    if (decision === 'hit') return respond(request, entry, 'HIT');
    if (decision === 'stale-backoff') return respondStale(request, entry, now);
    if (decision === 'error-backoff') {
      const wait = Math.max(1, Math.ceil((backoff.get(key) - now) / 1000));
      return jsonError(429, 'upstream rate limited, retry later', { 'Retry-After': String(wait) });
    }

    // Build the upstream request from scratch: nothing from the client.
    const headers = {
      'User-Agent': env.USER_AGENT || DEFAULT_USER_AGENT,
      'Accept-Encoding': 'gzip',
    };
    if (entry && entry.lastModified) headers['If-Modified-Since'] = entry.lastModified;

    let upstream = null;
    try {
      upstream = await fetch(upstreamUrl(query), { method: 'GET', headers });
    } catch {
      upstream = null; // network error, handled as a 5xx below
    }

    const status = upstream ? upstream.status : null;
    switch (classifyUpstream(status, Boolean(entry))) {
      case 'store': {
        entry = {
          body: await upstream.text(),
          contentType: upstream.headers.get('content-type') || 'application/json',
          lastModified: upstream.headers.get('last-modified'),
          expires: expiresFromHeaders(upstream.headers, now),
        };
        ctx.waitUntil(saveEntry(key, entry));
        return respond(request, entry, 'MISS');
      }
      case 'revalidated': {
        entry = { ...entry, expires: expiresFromHeaders(upstream.headers, now) };
        const lm = upstream.headers.get('last-modified');
        if (lm) entry.lastModified = lm;
        ctx.waitUntil(saveEntry(key, entry));
        return respond(request, entry, 'REVALIDATED');
      }
      case 'stale':
      case 'error': {
        const retryAfter = upstream
          ? parseRetryAfter(upstream.headers.get('retry-after'), now)
          : DEFAULT_RETRY_AFTER_SECONDS;
        // Back off on 429 (required) and on 5xx / network errors too, so a
        // struggling MET is not hammered by every client.
        backoff.set(key, now + retryAfter * 1000);
        if (entry) return respondStale(request, entry, now);
        return jsonError(status && status !== 304 ? status : 502, 'upstream unavailable', {
          'Retry-After': String(retryAfter),
        });
      }
      default: {
        // e.g. 400/404 from MET: forward status and body, do not cache.
        return new Response(request.method === 'HEAD' ? null : await upstream.text(), {
          status,
          headers: {
            'Content-Type': upstream.headers.get('content-type') || 'application/json',
            'X-Skyline-Cache': 'MISS',
          },
        });
      }
    }
  },
};

// ---------- responses ----------

function respond(request, entry, cacheState, expiresOverride) {
  const headers = new Headers({
    'Content-Type': entry.contentType,
    Expires: httpDate(expiresOverride ?? entry.expires),
    'X-Skyline-Cache': cacheState,
  });
  if (entry.lastModified) headers.set('Last-Modified', entry.lastModified);
  if (expiresOverride) headers.set('X-Skyline-Stale', '1');

  // The client already has this version: a cheap 304.
  if (clientHasCurrent(request.headers.get('if-modified-since'), entry.lastModified)) {
    headers.delete('Content-Type');
    return new Response(null, { status: 304, headers });
  }
  return new Response(request.method === 'HEAD' ? null : entry.body, { status: 200, headers });
}

// Stale body with Expires bumped to now + 60 s so clients back off.
function respondStale(request, entry, now) {
  return respond(request, entry, 'STALE', now + DEFAULT_RETRY_AFTER_SECONDS * 1000);
}

function jsonError(status, message, extra = {}) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', ...extra },
  });
}

function methodNotAllowed() {
  return new Response(JSON.stringify({ error: 'method not allowed' }), {
    status: 405,
    headers: { 'Content-Type': 'application/json', Allow: 'GET, HEAD' },
  });
}

// ---------- storage ----------
// Entries live in the in-isolate Map and in caches.default. The Cache API
// copy is kept for STORE_TTL_SECONDS (longer than Expires) so a stale body
// is still there to revalidate; the real Expires travels in X-Skyline-Expires.

async function loadEntry(key) {
  // A fresh memory copy wins; an expired one is checked against the shared
  // cache, which another isolate may already have refreshed.
  const mem = memory.get(key);
  if (mem && Date.now() < mem.expires) return mem;
  let res;
  try {
    res = await caches.default.match(key);
  } catch {
    return mem || null;
  }
  if (!res) return mem || null;
  const expires = Number(res.headers.get('x-skyline-expires'));
  if (!Number.isFinite(expires) || (mem && mem.expires >= expires)) return mem || null;
  const entry = {
    body: await res.text(),
    contentType: res.headers.get('content-type') || 'application/json',
    lastModified: res.headers.get('x-skyline-last-modified'),
    expires,
  };
  remember(key, entry);
  return entry;
}

async function saveEntry(key, entry) {
  remember(key, entry);
  const headers = new Headers({
    'Content-Type': entry.contentType,
    'Cache-Control': `public, max-age=${STORE_TTL_SECONDS}`,
    'X-Skyline-Expires': String(entry.expires),
  });
  // Stored under a custom name: a Last-Modified header would let the
  // Cache API answer conditional matches on its own.
  if (entry.lastModified) headers.set('X-Skyline-Last-Modified', entry.lastModified);
  try {
    await caches.default.put(key, new Response(entry.body, { headers }));
  } catch {
    // Cache API unavailable (e.g. some preview environments): memory only.
  }
}

function remember(key, entry) {
  memory.delete(key);
  memory.set(key, entry);
  if (memory.size > MEMORY_MAX) memory.delete(memory.keys().next().value);
}
