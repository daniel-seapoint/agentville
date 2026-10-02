<p align="center"><img src="docs/icon.png" width="128" alt="Agentville icon: an orange agent wearing a crown"></p>

<p align="center"><img src="docs/providers.png" width="268" alt="Claude, Codex and Copilot"></p>

<h1 align="center">Agentville</h1>

<p align="center">
See your Claude Code, Codex and GitHub Copilot agents at work.<br>
A Mac app that turns every running session into a little cartoon agent.
</p>

![Agents moving between the Plan, Research, Build, Verify, Review and Ship stations](docs/working.gif)

## What you get

**Working** — each agent stands at the station that matches what it is doing, tool in hand.

![Agents at their stations](docs/floor.png)

**Idle** — agents waiting on you head to the lounge and fall asleep.

![Agents asleep in the lounge](docs/idle.gif)

**Nobody home** — the dog keeps watch until a session starts.

![The empty workshop](docs/empty.gif)

**Pixel style** — switch the artwork between smooth and pixel art.

![The floor in pixel art](docs/pixel-style.png)

**Agent list and close-up** — open the list from the header, or click an agent to see its recent tasks.

<p align="center">
<img src="docs/agent-list.png" width="340" alt="The list of agents with their task, station and provider">
<img src="docs/agent-detail.png" width="290" alt="One agent up close with its recent tasks">
</p>

Also: filter by provider from the legend, keep the window on top, and a menu bar counter of
agents at work.

## Install

Requires macOS 14 or later on an Apple silicon Mac.

**Download**

1. Download `Agentville.zip` from the [latest release](https://github.com/danfar93/agentville/releases/latest) and unzip it.
2. Drag **Agentville** into your Applications folder.
3. Open it, and allow it the first time (see below).

**Opening it the first time**

macOS blocks Agentville on first launch. Apple only lets an app open without a warning if its
developer has paid for an Apple Developer account and sent the app to Apple to be checked
("notarised"). Agentville is a free hobby project that has not been through that, so macOS
cannot vouch for it and asks you to confirm. You only do this once. The source code is all in
this repository if you would rather read it or build it yourself.

1. Double-click Agentville. macOS says it was not opened. Click **Done**, not "Move to Bin".

   <img src="docs/install-1-not-opened.png" width="277" alt="macOS dialog: Agentville.app Not Opened, with Done and Move to Bin buttons">

2. Open **System Settings → Privacy & Security** and scroll down to Security. Click
   **Open Anyway** next to the message about Agentville.

   <img src="docs/install-2-privacy-security.png" width="474" alt="Privacy & Security: Agentville.app was blocked to protect your Mac, with an Open Anyway button">

3. In the dialog that follows, click **Open Anyway**. macOS may ask for your password or Touch ID.

   <img src="docs/install-3-open-anyway.png" width="279" alt="macOS dialog: Open Agentville.app? with Move to Bin, Open Anyway and Done buttons">

From then on Agentville opens normally.

Prefer Terminal? This one command does the same thing:

```sh
xattr -dr com.apple.quarantine /Applications/Agentville.app
```

**Or build it yourself** (needs Xcode 15 or later)

```sh
git clone https://github.com/danfar93/agentville.git
cd agentville
./scripts/bundle.sh
open build/Agentville.app
```

Then start a Claude Code, Codex or Copilot CLI session and its agent walks in.

## How it works

Agentville only reads the session logs these tools already write to `~/.claude`, `~/.codex`
and `~/.copilot`. It changes nothing, needs no sign-in, and makes no network requests.

An agent's station is worked out from what its session is doing:

| Station | When the session is… |
|---|---|
| 🗺️ Plan | planning or updating a to-do list |
| 🔎 Research | reading and searching files, or the web |
| 🔨 Build | editing files |
| 🧪 Verify | running tests, linters or builds |
| ✅ Review | looking at diffs and pull requests |
| 🚀 Ship | committing, pushing or opening a pull request |

## Good to know

- Only sessions on this Mac are shown, not cloud or remote ones.
- Codex and Copilot agents appear when their first turn starts and leave ten minutes after their last activity.
- Copilot Chat inside VS Code is not shown, only the Copilot CLI. Copilot support has not yet been tried against a real session.
- The session log formats are not official and may change; if they do, agents may lose detail until the app is updated.

## Credits

The Claude, OpenAI and GitHub Copilot logos are trademarks of their owners and are used here
only to label each agent's provider.
