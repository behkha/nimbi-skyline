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

## Open questions for DESIGN.md

- **A `rain` color.** The chart and island bars use `sky` `#7FD0FF` as a flat color (never the aurora
  gradient). DESIGN.md 4.5 should gain a `rain` state token before the views ship.
- **The `needsYou` exception.** 18.5 says a weather update is never `needsYou`. Skyline proposes one
  exception: thunder, storm-force wind or dangerous heat within three hours. Write it into 18.5, or
  drop Skyline's row 2 to `notice`.

## Mood mapping

See the Moods section of the [README](../README.md#moods).
