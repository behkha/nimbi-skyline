# Design choices

Options were shown as mockups drawn with DESIGN.md tokens and the CloudShape formula, in the private
artifact <https://claude.ai/artifact/VFjj8oyqw58CARf5bKgDqi> (owner only). Chosen on 10 Oct 2026; all
four are the recommended options.

| Decision | Chosen | Rejected |
|---|---|---|
| Menu bar glyph | **A · Cloud and temperature.** The standard 11.3 template cloud (eyes cut out) plus "18°". Drizzle marks under the cloud only when rain starts within the hour; an amber dot only for a storm or dangerous heat. | B · cloud with a sun/moon prop (crowded at 16–18 pt, bends 11.3). C · temperature only, cloud on duty (not recognisable, width jumps). |
| Dropdown | **B · The skyline chart.** Header with the cloud (40 pt, current mood), place, condition and big temperature. A 24 h chart: rain bars (mm, the "skyline") under a temperature line, axis labels every 6 h. Five day rows with low–high range bars. Footer: "Weather data © MET Norway" and the update time. Keys: R refresh (only after `Expires`), L change place, `,` settings. | A · hour chips plus day rows (generic, busy). C · sentence first with H/D tabs (sentences must stay true; hides data). |
| Island page (18.4, phase 2) | **A · bars.** Rain for the next 12 h; temperature bars on dry days. Glance "☂︎ 18°" when rain is coming, else "18°". Title like "18° · rain within the hour". Actions: Forecast ↩, Place L (never primary unless `needsYou`). | B · three text rows. C · daylight ring. |
| App icon (11.2) | **A · Raindrops.** Three sky-blue (`#7FD0FF`) drops below the cloud's left side, away from the eyes. Drawn by `scripts/make-icon.swift`. | B · sun behind (generic; amber means "waiting on you"). C · city skyline below (says city before weather; mush at 32 px). |

## Answered questions (10 Oct 2026)

Both open questions were answered with the recommended option, and both are now in DESIGN.md
(nimbi `acb9739`) and NimbiKit 0.2.0.

- **A `rain` color: yes, `sky` as a flat color.** Rain bars (the dropdown's chart now, the island's
  bars later) use `rain` `#7FD0FF`, which is `sky` as one flat color, never the aurora gradient.
  DESIGN.md 4.5 lists it; Skyline uses `Nimbi.State.rain` from NimbiKit.
- **`needsYou`: keep it, for hazards only.** `SkyMood` stays as it is. Only thunder, storm-force wind
  (≥ 20.8 m/s mean) or ≥ 35 °C within the next three hours is `needsYou` (the amber dot on the glyph,
  `asking` on the cloud). Everything else, rain within the hour included, is at most `notice`.
  DESIGN.md 18.5 now names this exception.
- **The notch, phase 1 (built 10 Oct 2026).** Skyline never claims the notch on its own; Relay has it
  by default. Settings name the owner ("Notch is used by Relay") with a one-click **Use for Skyline**,
  and **Give it to Relay** back. While Skyline owns it, it draws its own island (option A above, one
  page, so no dots or swiping) and Relay's pill waits at the right edge. Two departures from 18.7:
  the closed island's wings are 60 pt, not 76, because the closed island hides the menu bar items
  under it; and the open island is the notch plus 160 pt (about 200), not 222, because one page needs no dots.

## Air, sun and UV (11 Oct 2026)

Options in the private artifact <https://claude.ai/artifact/WMqNogkLmHXxqRS2wgBGc4> (copy in
`docs/air-and-sun-options.html`).

| Decision | Chosen |
|---|---|
| Layout | **A and B, with a toggle.** The quiet strip (only what matters now) by default; the grid of tiles (every value, labelled) one key away, D, and the choice is remembered. |
| Weather extras | **Everything MET's `complete` product has:** feels like, wind and gusts, rain chance, UV (clear sky), humidity and dew point, pressure, cloud layers, fog, thunder chance, and the 10–90% temperature range (a band round the chart's line). |
| Air and pollen | **CAMS via Open-Meteo.** Air quality worldwide, pollen in Europe only. Free API, CC BY 4.0, non-commercial use only; a paid Skyline would need their subscription or CAMS directly. |
| Nudges | **Notice for bad days:** air "Very poor" or worse, or UV 8+ under a mostly clear sky. Never `needsYou`, never the cloud's mood. |

Sunrise and sunset are always there, worked out locally.

## Redesign: the two-pane dropdown (11 Oct 2026)

Inspired by a two-pane weather card the user shared. Options in the private artifact
<https://claude.ai/artifact/X94dzvnRhTuK6nPZSaQ8wQ> (copy in `docs/redesign-options.html`); all four
recommended options chosen.

| Decision | Chosen |
|---|---|
| Layout | **A · Two panes, 600 wide.** Left, the now card: big temperature, high/low (and feels like), the condition in big capitals, sunrise and sunset, facts (what matters, or all with D). Right: place in caps with the date and time, seven day cards (click or ← → to show a day in the now card; esc goes back to now), the 24 h skyline chart, keys and credits. It replaces the strip and grid layout of "Air, sun and UV". |
| Symbols | **Multicolor SF Symbols**, filled variants (sun yellow, rain blue). |
| The cloud | **Peeking from the bottom-right corner**, big and cropped, in its mood, eyes on the cursor. Replaces the header cloud. |
| Temperature | **Flat white.** No gradient on text. |

## Mood mapping

See the Moods section of the [README](../README.md#moods).
