// Pure helpers for the Skyline proxy. Nothing here touches the Workers
// runtime (no caches, no fetch), so it runs under plain Node for tests.

export const FORECAST_PATH = '/weatherapi/locationforecast/2.0/compact';
export const UPSTREAM_ORIGIN = 'https://api.met.no';
export const DEFAULT_USER_AGENT =
  'Skyline-proxy/0.1 github.com/behkha/nimbi-skyline behzadkhanlar@gmail.com';

// How long a body stays in the cache after it was stored. It must outlive
// Expires so the stale copy is still there to revalidate or to serve when
// MET is down.
export const STORE_TTL_SECONDS = 24 * 60 * 60;
// Used when MET sends no Retry-After, and as the stale-serve Expires bump.
export const DEFAULT_RETRY_AFTER_SECONDS = 60;
// Used only if MET ever omits Expires on a 200 (it normally sends one).
export const DEFAULT_FRESH_SECONDS = 10 * 60;

export const ALTITUDE_MIN = -500;
export const ALTITUDE_MAX = 9000;

const NUMBER_RE = /^[+-]?(\d+(\.\d*)?|\.\d+)$/;

function parseNumber(raw) {
  if (raw === null || raw === undefined) return null;
  const s = String(raw).trim();
  if (!NUMBER_RE.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

// Round to `decimals` places. Normalizes -0 to 0.
export function quantize(value, decimals = 2) {
  const f = 10 ** decimals;
  const q = Math.round(value * f) / f;
  return q === 0 ? 0 : q;
}

// Validate and normalize the client's query. Returns
// { ok: true, lat, lon, altitude } (altitude may be null) or
// { ok: false, error }.
export function parseForecastQuery(searchParams) {
  const lat = parseNumber(searchParams.get('lat'));
  const lon = parseNumber(searchParams.get('lon'));
  if (lat === null) return { ok: false, error: 'lat is missing or not a number' };
  if (lon === null) return { ok: false, error: 'lon is missing or not a number' };
  if (Math.abs(lat) > 90) return { ok: false, error: 'lat must be between -90 and 90' };
  if (Math.abs(lon) > 180) return { ok: false, error: 'lon must be between -180 and 180' };

  let altitude = null;
  const rawAlt = searchParams.get('altitude');
  if (rawAlt !== null && rawAlt !== '') {
    const a = parseNumber(rawAlt);
    if (a === null) return { ok: false, error: 'altitude is not a number' };
    altitude = Math.min(ALTITUDE_MAX, Math.max(ALTITUDE_MIN, Math.round(a)));
    if (altitude === 0) altitude = 0; // avoid -0
  }

  return { ok: true, lat: quantize(lat), lon: quantize(lon), altitude };
}

// Canonical query string: only known params, sorted by name, quantized.
export function canonicalQuery({ lat, lon, altitude }) {
  const params = [];
  if (altitude !== null && altitude !== undefined) params.push(['altitude', String(altitude)]);
  params.push(['lat', String(lat)]);
  params.push(['lon', String(lon)]);
  return params.map(([k, v]) => `${k}=${v}`).join('&');
}

// Cache key URL. `origin` is the Worker's own origin so the Cache API
// accepts it for this zone.
export function cacheKeyUrl(origin, query) {
  return `${origin}${FORECAST_PATH}?${canonicalQuery(query)}`;
}

export function upstreamUrl(query) {
  return `${UPSTREAM_ORIGIN}${FORECAST_PATH}?${canonicalQuery(query)}`;
}

// Parse an HTTP date to epoch ms, or null.
export function parseHttpDate(value) {
  if (!value) return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? t : null;
}

export function httpDate(ms) {
  return new Date(ms).toUTCString();
}

// Expires from upstream headers, falling back to now + DEFAULT_FRESH_SECONDS.
export function expiresFromHeaders(headers, now) {
  return parseHttpDate(headers.get('expires')) ?? now + DEFAULT_FRESH_SECONDS * 1000;
}

// Retry-After in seconds (accepts delta-seconds or an HTTP date).
export function parseRetryAfter(value, now) {
  if (value) {
    const s = String(value).trim();
    if (/^\d+$/.test(s)) return Math.max(1, parseInt(s, 10));
    const t = parseHttpDate(s);
    if (t !== null) return Math.max(1, Math.ceil((t - now) / 1000));
  }
  return DEFAULT_RETRY_AFTER_SECONDS;
}

// What to do before talking to MET.
//   'hit'           fresh cached entry, serve it
//   'stale-backoff' in backoff, serve the stale entry
//   'error-backoff' in backoff, nothing cached, answer 429
//   'upstream'      go to MET (with If-Modified-Since if we have an entry)
export function decideBeforeUpstream({ entry, now, backoffUntil }) {
  if (entry && now < entry.expires) return 'hit';
  if (backoffUntil && now < backoffUntil) return entry ? 'stale-backoff' : 'error-backoff';
  return 'upstream';
}

// What to do with MET's answer.
//   'store'       new body (200/203): cache it and serve it
//   'revalidated' 304 and we have an entry: refresh its Expires, serve it
//   'stale'       429/5xx/network error and we have an entry: serve stale
//   'error'       429/5xx/network error and nothing cached
//   'passthrough' anything else (e.g. 400/404): forward it, do not cache
// `status` is null for a network error.
export function classifyUpstream(status, hasEntry) {
  if (status === 200 || status === 203) return 'store';
  if (status === 304) return hasEntry ? 'revalidated' : 'error';
  if (status === null || status === 429 || status >= 500) return hasEntry ? 'stale' : 'error';
  return 'passthrough';
}

// True if the client's copy (If-Modified-Since) is at least as new as ours.
export function clientHasCurrent(ifModifiedSince, lastModified) {
  const ims = parseHttpDate(ifModifiedSince);
  const lm = parseHttpDate(lastModified);
  if (ims === null || lm === null) return false;
  return lm <= ims;
}
