# Skyline

A little cloud in your menu bar that keeps an eye on the sky. Skyline by nimbi.

Skyline is the second app in the [nimbi](https://github.com/behkha/nimbi) family, after
[Relay](https://github.com/behkha/relay). It lives in the menu bar, shows the temperature next to
the nimbi cloud, and tells you when rain is coming within the hour.

**Status:** early. The menu bar glyph, the dropdown (sky now, a 24 h skyline chart, five days), the
place picker, settings and About window are built, on top of the MET client, cache, location, sky
reading and moods. The choices behind them are in [docs/design-choices.md](docs/design-choices.md).
The Worker proxy isn't deployed yet, so builds talk to api.met.no directly.

Weather data © MET Norway, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Air quality
and pollen: Copernicus Atmosphere Monitoring Service (CAMS) data via [Open-Meteo](https://open-meteo.com),
CC BY 4.0.

## How it works

- **Data:** [MET Norway Locationforecast 2.0](https://api.met.no/weatherapi/locationforecast/2.0/documentation),
  the `complete` product: hourly steps for about two and a half days, then six-hourly, worldwide, with
  feels-like temperature, gusts, clear-sky UV, cloud layers, fog, pressure, the 10–90% temperature range
  and rain and thunder chances. Free and open, no key.
- **Air quality and pollen:** CAMS through [Open-Meteo's air quality API](https://open-meteo.com/en/docs/air-quality-api),
  hourly, cached an hour per ~1 km cell (the position is rounded to two decimals). Air quality worldwide,
  pollen only in Europe. Open-Meteo's free API is for **non-commercial use** (under 10,000 calls a
  day); a paid Skyline needs their subscription or CAMS directly. If it can't be reached, Skyline just
  shows the weather.
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

## Using it

- **Menu bar:** the nimbi cloud and the temperature. Drizzle marks hang under the cloud when rain starts
  within the hour; an amber dot means a storm or dangerous heat within three hours.
- **Click** for the dropdown: the cloud in its mood, the place and what the sky is doing, the next 24
  hours as a skyline (rain bars under the temperature line), and five days. **Right-click** for a short
  menu.
- **Around the temperature:** a quiet strip of what matters now (feels like when it differs, wind when
  it blows, rain chance, air quality, pollen in season, UV by day, the next sunrise or sunset), or, with
  **D**, a grid with every value labelled (humidity, dew point, pressure, cloud layers, fog and thunder
  too). The chart shades MET's 10–90% temperature range and tints hours likely to be wet. Very poor air,
  or UV 8+ under a mostly clear sky, is a `notice`: it never changes the cloud's mood.
- **Keys** in the dropdown: **R** asks MET again (shown only once the forecast has expired; MET's terms
  forbid asking sooner), **L** changes place, **D** more or less detail, **,** opens settings (theme,
  text size, detail, European or US air index), **esc** goes back or closes.
- **Place:** follow the Mac (Location Services) or pick a city. Settings also hold the theme (Dark,
  Black) and the text size.
- **The notch:** shared by every nimbi app, one at a time (DESIGN.md 18.2). Skyline never takes it on
  its own; Relay has it by default. **Use for Skyline** in settings moves Skyline there: a black island
  with the cloud and the glance ("☂︎ 18°"), opening on hover into the next 12 hours (rain bars, or
  the temperature on a dry day) with **Forecast ↩** and **Place L**. The dropdown then hangs from the
  island, and the menu bar glyph steps aside. **Give it to Relay** hands it back; Relay's pill waits
  at the right edge meanwhile. Either app's switch works live.

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
- `needsYou` is used only for row 2: a thunderstorm, storm-force wind or dangerous heat in the next
  three hours, the one exception DESIGN.md 18.5 allows for weather.
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

To look at the glyph and the dropdown in a given sky without waiting for the weather, run a demo
(made-up forecast for Oslo; asks neither MET nor Location Services): `rain` (rain within the hour),
`storm` (thunder: the amber dot) or `clear`.

```bash
SKYLINE_DEMO=storm build/Skyline.app/Contents/MacOS/Skyline
```

To see what Skyline makes of the live forecast for a place, without any UI:

```bash
swift run Skyline --fetch 59.9139 10.7522
```

## Layout

- `Sources/SkylineCore` — everything that isn't a view: `METClient` and its cache, the compact JSON
  models, `SkyReport` (rain now / soon / later, hazards, five days, the headline), `HourlyOutlook` (the
  chart's hours and its spoken summary), `IslandPage` (the notch page: glance, title, subtitle, bars),
  `Conditions` (the strip, the grid and their urgency), `AirQuality` and `AirClient`, `Sun` (position,
  sunrise and sunset), `SkyMood`, `LocationService`.
- `Sources/Skyline` — the app: `SkyModel` (fetches at `Expires`, re-reads the cache every 30 s),
  `MenuBarItem` (the template glyph), `Dropdown` (the panel and its keys), `ForecastView` and
  `SkylineChart`, `ConditionsView` (strip and grid), `PlacePicker`, `SettingsView` (with the notch switch), `Island` (Skyline at the
  notch), `About`, `Demo`.
- `Tests/SkylineCoreTests` — Swift Testing suites with scripted HTTP answers and a movable clock.
- `scripts/` — `build.sh`, `make-icon.swift` (the app icon, drawn procedurally).
- `worker/` — the Cloudflare Worker proxy, with its own tests (`cd worker && npm test`).

## Design

Skyline follows the nimbi design system,
[DESIGN.md](https://github.com/behkha/nimbi/blob/main/DESIGN.md). The options and the choices made are
in [docs/design-choices.md](docs/design-choices.md).
