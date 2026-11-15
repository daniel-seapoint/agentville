# Agentville brand kit (for films)

Agentville is a native macOS app (Swift + SpriteKit). It has no web components, so films are
built from the app's own rendered output: `--record` footage, `--casts` sheets and `AppIcon` art.

## Sources of truth
| What | Where |
|---|---|
| Voice, claims | `README.md` (British spelling: colours, favourite; plain, warm, short) |
| Floor footage | `Agentville --demo working|idle --record <dir> --record-fps 30 --snapshot-scale 4 -theme <theme> -artStyle smooth` |
| Cast sheets | `Agentville --casts <dir>` (`Wardrobe.writeCasts`) |
| App icon, dressed | `Agentville --icon-png <png> --icon-choice northPole:santa` (`AppIcon.render`) |

`--record-fps` and `--icon-png` were added to the app for the Santa Claude film.

## Colours (decoded from the app's own pixels)
- Night navy (cast sheet and icon background): `#0d1a30` (13, 26, 48)
- North Pole sky: (10, 21, 39); lounge: (47, 22, 33)
- Stations light up in Christmas red and green (Santa Claude theme)

## Rules
- Only the app's own surfaces. No invented cards, glows or particles; the floor brings its own snow,
  aurora and fairy lights.
- Mascot: the app icon character, dressed per theme (user's choice: Santa Claude icon bookends).
- Claims: Agentville shows Claude Code, Codex and Copilot sessions as agents on a floor. The demo
  footage is the app's own `--demo` mode; never imply real users' tasks.

## Santa Claude film decisions (interview, 2026-11-15)
- Plays as a muted README / landing loop; a with-music cut is also made.
- 20-30 s, 16:9. No words beyond the app's own UI text.
- One canvas with camera moves; the Santa Claude icon opens and closes the loop.
- Must show: sleigh fly-over, the cast, agents at work, lounge and icon.
- Music: "Jingle Bells", Kevin MacLeod (incompetech.com), CC BY 3.0. Credit required on the audio cut.
