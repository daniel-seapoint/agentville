# Agentville

A small Mac app that shows every Claude Code, Codex and GitHub Copilot CLI session running on
this machine as a pixel robot in a workshop. Robots walk between stations as their work
changes, carry a label with the provider, the task and what they are doing right now, and get
confetti when they ship.

It only reads the session logs those tools already write (`~/.claude`, `~/.codex`, `~/.copilot`).
It changes nothing, installs no hooks, and makes no network requests.

## Run

```sh
swift run Agentville            # live sessions
swift run Agentville --demo     # open straight on the demo
swift run Agentville --replay <transcript-or-rollout.jsonl> --speed 20
./scripts/bundle.sh && open build/Agentville.app
```

The app opens on your real agents. The **Live | Demo** switch in the title bar swaps them for a
scripted demo to play with, and back; "See a demo" in the empty state does the same. While the
demo is on, a yellow DEMO tag sits beside the title and a second picker chooses the scene:
**Working** (five agents cycling through the stations), **Idle** (the same five asleep) or
**None** (the empty state). The demo never touches real sessions. To open on a particular
scene, pass it after the flag: `--demo idle`, `--demo empty`.

`--snapshot <file.png> [--after <seconds>]` saves a picture of the floor and quits; useful for
checking visual changes.

The agents are drawn smooth by default. The **Smooth | Pixel** picker in the title bar switches
them to hard-edged pixel art and back; both are rendered from the same drawings, and the choice is
remembered.

Click the blue button in the top-right corner ("3 agents working ▾") for a list of every agent:
its robot as drawn on the floor, its task, station and current status, and its provider's icon
at the end of the row. Subagents are listed under their parent.

Click a provider in the legend to hide that provider's agents from the floor and the list; click
it again to bring them back. A hidden provider's plate is dimmed.

Click a robot to see it up close with the last few tasks it has run. The pin in the title bar
keeps the window above others. The menu bar item shows how many agents are working and stays
after the window is closed.

## How a robot picks a station

Sessions do not announce what stage they are in, so the station is inferred from each tool call
(`Sources/AgentvilleCore/StageClassifier.swift`):

| Station | Triggered by |
|---|---|
| Plan | plan mode, plan/todo tools |
| Research | reading and searching files, web lookups |
| Build | editing files, applying patches |
| Verify | tests, linters, type checkers, builds |
| Review | `git diff/status/log`, `gh pr view/diff` |
| Ship | `git commit`, `git push`, `gh pr create` |

A robot only walks once a new stage has held for 1.5 seconds, so quick read-edit-read sequences
do not make it bounce. Claude subagents appear as small robots beside their parent.

The lounge is a strip along the bottom of the floor, always furnished with a couch at each end
and one in the middle, plus a couple of lamps and plants. Agents waiting on you walk down to it and go to sleep under a thought
bubble. Sitters take the couches. Those who prefer a bed get one on the floor between the
couches, or make do with a free couch when the floor is full. If every spot is taken, the rest
bunch up on the floor. The task name moves to a caption underneath. When nobody is
working the header reads "All agents idle" and a note in the middle of the floor says everyone
is on a break.

Each agent also gets a hat, an accessory, or both, drawn as pixel art (17 hats, from a beanie
and a top hat to a wizard hat, a halo and a propeller cap; sunglasses, bow tie, scarf), along
with its bed preference, dream and bedside clutter. These are picked from a hash of the agent's
id, so they look random but stay the same for that agent every time you open the app.

## App icon

The icon is the crowned orange robot, drawn by the app itself. `swift run Agentville --icon icon`
writes 1024px artwork in both art styles to `icon/`, and `scripts/bundle.sh` builds the app's
icon from the smooth one.

## Logos

Floating beside each agent is its provider's logo, on a tile in the provider's colour (coral
for Claude, green for Codex, purple for Copilot). When an agent is asleep the tile sits on the
floor to its left, opposite its bedside keepsake. A legend in the header, beside the agent count, pairs each logo
with its name. The empty state shows the same logos as larger tiles with
the names underneath. The marks are the Claude, OpenAI and GitHub Copilot logos, in
`Sources/Agentville/Resources/Logos`. They were copied from the VS Code extensions installed
on the machine this was built on and are redrawn in a single dark colour at runtime. Each is a
trademark of its owner; check their brand guidelines before distributing the app. If a file is
missing the tile falls back to the name alone.

## Caveats

- The log formats are internal to Claude Code and Codex and can change with any update. Parsers
  ignore what they do not recognise, so a format change should mean missing detail, not a crash.
- A Claude subagent is considered finished when it replies without calling a tool, or after
  three quiet minutes. A subagent waiting on a long command can disappear early.
- Codex and Copilot sessions are found by recently modified log files, so one appears when its
  first turn starts and leaves ten minutes after its last activity.
- The Copilot reader follows the Copilot CLI's `session-state/<id>/events.jsonl` layout and is
  tested against hand-written fixtures only; it has not been run against a real Copilot session.
  Copilot Chat inside VS Code keeps its history elsewhere and is not shown.

## Adding another tool

Implement `AgentEventSource` (one `poll(now:)` method returning `AgentEvent`s) and add it to the
list in `WorkshopController`. `CopilotSource` is the shortest example. A new provider also needs
a case in `AgentSource`, plus a robot shape and badge colour in `PixelArt`.

## Tests

```sh
swift test
```
