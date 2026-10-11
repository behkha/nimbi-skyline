import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  quantize,
  parseForecastQuery,
  canonicalQuery,
  cacheKeyUrl,
  upstreamUrl,
  parseRetryAfter,
  expiresFromHeaders,
  decideBeforeUpstream,
  classifyUpstream,
  clientHasCurrent,
  DEFAULT_FRESH_SECONDS,
} from '../src/lib.js';

const q = (s) => parseForecastQuery(new URLSearchParams(s));

test('quantize rounds to 2 decimals and drops -0', () => {
  assert.equal(quantize(59.91234), 59.91);
  assert.equal(quantize(10.755), 10.76);
  assert.equal(quantize(-0.001), 0);
  assert.ok(!Object.is(quantize(-0.001), -0));
  assert.equal(quantize(-33.8688), -33.87);
});

test('parseForecastQuery accepts valid input and quantizes', () => {
  assert.deepEqual(q('lat=59.913868&lon=10.752245'), { ok: true, lat: 59.91, lon: 10.75, altitude: null });
  assert.deepEqual(q('lon=10.75&lat=59.91&altitude=12.6'), { ok: true, lat: 59.91, lon: 10.75, altitude: 13 });
  assert.deepEqual(q('lat=90&lon=-180'), { ok: true, lat: 90, lon: -180, altitude: null });
  assert.equal(q('lat=1&lon=2&altitude=').altitude, null);
});

test('parseForecastQuery clamps altitude', () => {
  assert.equal(q('lat=1&lon=2&altitude=99999').altitude, 9000);
  assert.equal(q('lat=1&lon=2&altitude=-10000').altitude, -500);
  assert.ok(!Object.is(q('lat=1&lon=2&altitude=-0.2').altitude, -0));
});

test('parseForecastQuery rejects bad input', () => {
  for (const s of [
    '', 'lat=59', 'lon=10', 'lat=abc&lon=10', 'lat=&lon=10', 'lat=0x10&lon=1',
    'lat=1e2&lon=1', 'lat=90.01&lon=0', 'lat=-91&lon=0', 'lat=0&lon=180.5',
    'lat=0&lon=Infinity', 'lat=1&lon=2&altitude=high',
  ]) {
    const r = q(s);
    assert.equal(r.ok, false, `expected rejection for "${s}"`);
    assert.equal(typeof r.error, 'string');
  }
});

test('canonical query is sorted and normalized so equivalent requests share a key', () => {
  const a = q('lon=10.7522&lat=59.9139&altitude=10&foo=bar');
  const b = q('altitude=10.2&lat=59.911&lon=10.749');
  assert.equal(canonicalQuery(a), 'altitude=10&lat=59.91&lon=10.75');
  assert.equal(cacheKeyUrl('https://x.dev', a), cacheKeyUrl('https://x.dev', b));
  assert.equal(
    upstreamUrl(q('lat=59.91&lon=10.75')),
    'https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=59.91&lon=10.75',
  );
});

test('parseRetryAfter handles seconds, dates and missing values', () => {
  const now = Date.parse('2026-01-01T00:00:00Z');
  assert.equal(parseRetryAfter('120', now), 120);
  assert.equal(parseRetryAfter('Thu, 01 Jan 2026 00:00:30 GMT', now), 30);
  assert.equal(parseRetryAfter(null, now), 60);
  assert.equal(parseRetryAfter('soon', now), 60);
  assert.equal(parseRetryAfter('0', now), 1);
});

test('expiresFromHeaders reads Expires or falls back', () => {
  const now = 1_000_000;
  const h = new Headers({ Expires: 'Thu, 01 Jan 2026 00:30:00 GMT' });
  assert.equal(expiresFromHeaders(h, now), Date.parse('2026-01-01T00:30:00Z'));
  assert.equal(expiresFromHeaders(new Headers(), now), now + DEFAULT_FRESH_SECONDS * 1000);
});

test('decideBeforeUpstream', () => {
  const entry = { expires: 1000 };
  assert.equal(decideBeforeUpstream({ entry, now: 999 }), 'hit');
  assert.equal(decideBeforeUpstream({ entry, now: 999, backoffUntil: 5000 }), 'hit');
  assert.equal(decideBeforeUpstream({ entry, now: 1000 }), 'upstream');
  assert.equal(decideBeforeUpstream({ entry, now: 2000, backoffUntil: 5000 }), 'stale-backoff');
  assert.equal(decideBeforeUpstream({ entry: null, now: 2000, backoffUntil: 5000 }), 'error-backoff');
  assert.equal(decideBeforeUpstream({ entry: null, now: 6000, backoffUntil: 5000 }), 'upstream');
  assert.equal(decideBeforeUpstream({ entry: null, now: 0 }), 'upstream');
});

test('classifyUpstream', () => {
  assert.equal(classifyUpstream(200, false), 'store');
  assert.equal(classifyUpstream(203, true), 'store');
  assert.equal(classifyUpstream(304, true), 'revalidated');
  assert.equal(classifyUpstream(304, false), 'error');
  assert.equal(classifyUpstream(429, true), 'stale');
  assert.equal(classifyUpstream(503, true), 'stale');
  assert.equal(classifyUpstream(null, true), 'stale');
  assert.equal(classifyUpstream(429, false), 'error');
  assert.equal(classifyUpstream(500, false), 'error');
  assert.equal(classifyUpstream(400, true), 'passthrough');
  assert.equal(classifyUpstream(404, false), 'passthrough');
});

test('clientHasCurrent compares If-Modified-Since with Last-Modified', () => {
  const lm = 'Thu, 01 Jan 2026 00:00:00 GMT';
  assert.equal(clientHasCurrent(lm, lm), true);
  assert.equal(clientHasCurrent('Thu, 01 Jan 2026 00:05:00 GMT', lm), true);
  assert.equal(clientHasCurrent('Wed, 31 Dec 2025 23:59:00 GMT', lm), false);
  assert.equal(clientHasCurrent(null, lm), false);
  assert.equal(clientHasCurrent(lm, null), false);
  assert.equal(clientHasCurrent('garbage', lm), false);
});
