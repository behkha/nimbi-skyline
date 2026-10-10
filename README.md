# Skyline

A little cloud in your menu bar that keeps an eye on the sky. Skyline by nimbi.

Skyline is the second app in the [nimbi](https://github.com/behkha/nimbi) family, after
[Relay](https://github.com/behkha/relay). It lives in the menu bar, shows the temperature next to
the nimbi cloud, and tells you when rain is coming within the hour.

**Status:** early. The data side works (MET client, cache, location, sky reading, moods, tests).
The menu bar glyph, dropdown and icon are designed and chosen
([docs/design-choices.md](docs/design-choices.md)); the views are next.

Weather data © MET Norway, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## How it works

- **Data:** [MET Norway Locationforecast 2.0](https://api.met.no/weatherapi/locationforecast/2.0/documentation),
  the `compact` product: hourly steps for about two and a half days, then six-hourly, worldwide. Free and
  open, no key.
- **Proxy:** shipped builds talk to a small Cloudflare Worker ([`worker/`](worker/README.md)) that adds
  Skyline's User-Agent, caches by ~1 km cells until MET's `Expires`, and keeps users' IP addresses and
  exact positions away from MET. Development builds talk to `api.met.no` directly.
- **Following MET's terms** ([TermsOfService](https://api.met.no/doc/TermsOfService)), in `METClient`:
  an identifying User-Agent, coordinates truncated to 4 decimals, every response cached on disk until
  `Expires` (no request is ever made before it, not even on relaunch), `If-Modified-Since` on
  revalidation, and an exponential backoff (60 s up to 1 h, or `Retry-After`) on 429 and 5xx, serving
  the last forecast meanwhile. Location updates only count after a move of 1 km, so GPS jitter never
  turns into requests.
- **Location:** CoreLocation when allowed, otherwise a city you pick (geocoded with `CLGeocoder`).
- **Day and night** come from a local solar position calculation, so no second API is needed.
- **"Soon"** means within the hour. MET's minute-by-minute nowcast exists only for the Nordics; Skyline
  uses hourly steps everywhere for now.

## Moods

DESIGN.md 3.3 asks every nimbi app to write down how its states map onto the cloud's moods. Skyline's
mapping lives in `SkyMood.from` (`Sources/SkylineCore/SkyMood.swift`); the first matching row wins.

| # | When | Mood | Urgency (18.5) |
|---|---|---|---|
| 1 | No forecast yet, or nothing fresh for 3 h (offline) | **lonely** | none |
| 2 | Thunder, storm-force wind (≥ 20.8 m/s mean) or ≥ 35 °C within the next 3 h | **asking** | needsYou |
| 3 | Rain, sleet or snow starts within the hour | **busy**, livelier with heavier rain (1–8) | notice |
| 4 | It's raining now | **busy**, livelier with heavier rain | none |
| 5 | The rain just stopped (3 s) | **happy** | none |
| 6 | 30 °C or warmer | **overheated** | none |
| 7 | The sun is below the horizon | **asleep** (the cursor still wakes it) | none |
| 8 | Anything else | **relaxed** | none |

Notes:
- Rain beats night: if rain is coming at 23:00 you still get the notice.
- `needsYou` is used only for row 2. DESIGN.md 18.5 says a weather *update* is never `needsYou`; a
  thunderstorm or dangerous heat in the next three hours is treated as the one honest exception.
- The menu bar glyph stays a template image. It shows drizzle marks under the cloud for row 3 and an
  amber dot for row 2, and nothing else (DESIGN.md 11.3).

## Building

Needs macOS 13+ on Apple silicon and the Xcode Command Line Tools. The only dependency is
[NimbiKit](https://github.com/behkha/nimbi-kit).

```bash
swift build
```

```bash
swift test
```

```bash
scripts/build.sh
```

`scripts/build.sh` assembles and ad-hoc signs `build/Skyline.app`; `--install` copies it to
`/Applications`. Set `SKYLINE_PROXY_URL=https://…` to bake the Worker's URL in. You can also set it at
runtime with `defaults write app.nimbi.skyline SkylineProxyURL https://…`.

To see what Skyline makes of the live forecast for a place, without any UI:

```bash
swift run Skyline --fetch 59.9139 10.7522
```

## Layout

- `Sources/SkylineCore` — everything that isn't a view: `METClient` and its cache, the compact JSON
  models, `SkyReport` (rain now / soon / later, hazards, five days), `Sun`, `SkyMood`, `LocationService`.
- `Sources/Skyline` — the app: menu bar item and (soon) the views.
- `Tests/SkylineCoreTests` — Swift Testing suites with scripted HTTP answers and a movable clock.
- `scripts/` — `build.sh`, `make-icon.swift` (the app icon, drawn procedurally).
- `worker/` — the Cloudflare Worker proxy, with its own tests (`cd worker && npm test`).

## Design

Skyline follows the nimbi design system,
[DESIGN.md](https://github.com/behkha/nimbi/blob/main/DESIGN.md). The options and the choices made are
in [docs/design-choices.md](docs/design-choices.md).
