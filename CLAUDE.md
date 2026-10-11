# Skyline

Skyline is a native macOS menu bar weather app, app #2 in the nimbi family (Relay is #1).

## Follow these first

- **Design:** `~/Programming/nimbi-site/DESIGN.md` (github.com/behkha/nimbi) is the binding design system: the cloud and its moods, tokens, components, icon rules, writing voice, the new-app checklist (§16) and shared surfaces (§18). When code and DESIGN.md disagree, DESIGN.md wins.
- **Shared code:** use NimbiKit (`github.com/behkha/nimbi-kit`, see its README) for tokens, `NimbiCloud`, `Mood`, `KeyHint`, button styles, `PanelBackground`, `SurfaceClaim`. Don't copy code out of Relay; if a second app needs something that only Relay has, move it into NimbiKit.
- **Design before UI code:** show options as a published HTML artifact and let the user choose before writing view code. Choices so far are in `docs/design-choices.md`.

## Rules

- Swift, SwiftUI and AppKit only. NimbiKit is the only dependency. Never add WeatherKit or third-party packages.
- Weather data is MET Norway Locationforecast 2.0 (CC BY 4.0). Respect its terms: identifying User-Agent, cache every response, never re-request before `Expires`, send `If-Modified-Since`, at most 4 decimals in coordinates, back off on 429. "Weather data © MET Norway" stays visible in the app.
- Air quality and pollen come from CAMS via Open-Meteo's air quality API (CC BY 4.0, free tier is non-commercial only). Cache it (an hour per ~1 km cell), round the position to 2 decimals, back off on errors, and keep "Air quality © CAMS via Open-Meteo" visible whenever air data shows. Weather stays MET's.
- The app talks to the Worker proxy in `worker/` when a proxy URL is set, and to api.met.no directly otherwise (development). The proxy covers MET only.
- Menu bar first (LSUIElement). The notch only through `SurfaceClaim` (§18.2); weather urgency is at most `notice`, except a real storm or dangerous heat.

## Commands

- `swift build` / `swift test` (Swift Testing; the Command Line Tools are enough). Inside Claude Code's command sandbox the Testing macro plugin can't load ("plugin for module 'TestingMacros' not found"); run `swift test` outside the sandbox. If it still says the plugin is missing, point at it: `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.
- `SKYLINE_DEMO=rain|storm|clear build/Skyline.app/Contents/MacOS/Skyline` shows a made-up sky (no MET, no location), for checking the glyph and dropdown.
- `scripts/build.sh [--install]` builds and ad-hoc signs `build/Skyline.app`
- `swift run Skyline --fetch <lat> <lon>` prints a live forecast reading (direct MET)
- `cd worker && npm test` tests the proxy
