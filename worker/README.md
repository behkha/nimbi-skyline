# Skyline proxy

A small Cloudflare Worker that sits between the Skyline app and MET Norway's
Locationforecast API. It caches forecasts and keeps the app within MET's terms
of service.

It serves the same path and query as `api.met.no`:

```
GET {base}/weatherapi/locationforecast/2.0/complete?lat=<lat>&lon=<lon>[&altitude=<m>]
```

So the app only changes its base URL. Everything else stays the same.

## Why it exists

MET's terms (https://api.met.no/doc/TermsOfService) ask every client to:

- Send an identifying User-Agent. The proxy sends the `USER_AGENT` value from
  `wrangler.toml` on every upstream request.
- Use at most 4 decimals for coordinates. The proxy rounds lat and lon to 2
  decimals (about 1 km). MET's grid is 1 to 2.5 km, so nothing is lost.
- Cache responses and not ask again before `Expires`. The proxy serves from
  cache until `Expires`. After that it asks MET with `If-Modified-Since`, which
  usually returns a cheap 304.
- Stay under the total request cap (20 requests per second for the whole
  app). One shared cache for all users keeps the load far below that.
- Back off on 429. The proxy waits at least `Retry-After` before calling MET
  again for that location.

It also protects users. MET never sees a user's IP address, headers or exact
location. The proxy builds each upstream request from scratch with only
`User-Agent`, `Accept-Encoding: gzip` and `If-Modified-Since`.

## How it behaves

- Bad `lat`, `lon` or `altitude` gives a 400 with a short JSON error.
  Altitude is rounded to whole meters and clamped to -500..9000.
- Other paths give 404. Methods other than GET and HEAD give 405.
- `GET /health` returns `ok`.
- Responses carry MET's body, `Content-Type`, `Expires` and `Last-Modified`.
- `X-Skyline-Cache` says where the answer came from:
  - `HIT`: fresh from cache, MET was not called.
  - `MISS`: new data from MET.
  - `REVALIDATED`: MET answered 304, the cached body was reused.
  - `STALE`: MET failed (429, 5xx or network error) and an old copy was
    served. These responses also carry `X-Skyline-Stale: 1` and an `Expires`
    60 seconds ahead, so the app tries again soon but not at once.
- If the app sends `If-Modified-Since` and nothing newer exists, the proxy
  answers 304.
- If MET fails and nothing is cached, the proxy returns MET's status (or 502
  for a network error) with `Retry-After`.

Cached bodies are kept for 24 hours, longer than `Expires`, so there is
always something to revalidate or to fall back on.

### Note on workers.dev

Cloudflare's Cache API does nothing on `*.workers.dev` hostnames. On
workers.dev the proxy still works, but it caches only in each Worker
instance's memory, which is short-lived and not shared. For a real shared
cache, attach a custom domain or route to the Worker. No code change is
needed.

## Deploy

```
cd worker
npx wrangler login
npx wrangler deploy
```

The deployed URL looks like `https://skyline-proxy.<account>.workers.dev`.

## Run locally

```
cd worker
npx wrangler dev
```

## Tests

```
cd worker
npm test
```

The tests use Node's built-in test runner. They do not need wrangler.

## Point the app at it

Set the app's proxy base URL setting to the deployed URL, for example
`https://skyline-proxy.<account>.workers.dev`. Leave off the trailing slash and
the path. The app adds `/weatherapi/locationforecast/2.0/complete` itself.

## Check it

Run this twice:

```
curl -i "$URL/weatherapi/locationforecast/2.0/complete?lat=59.91&lon=10.75"
```

The first answer should show `X-Skyline-Cache: MISS`. The second should show
`X-Skyline-Cache: HIT`. (On workers.dev the second may still be a MISS if it
lands on another instance. See the note above.)

## Attribution

Forecast data comes from MET Norway under CC BY 4.0. The app must show:
"Weather data © MET Norway".
