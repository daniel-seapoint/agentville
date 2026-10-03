#!/bin/bash
# Renders the README's pictures of the themes and agent styles from the scripted demo.
# Needs a Mac with a logged-in desktop, since the floor is drawn by SpriteKit on screen.
# Makes: docs/wardrobe.png, docs/themes/<theme>.png, docs/styles/<style>.png, docs/themes.gif
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Agentville"
THEMES="workshop daylight forest ocean space sunset terminal winter"
STYLES="smooth pixel outlined glow"
WORK="$(mktemp -d)"
mkdir -p docs/themes docs/styles

# Every hat, accessory, pattern, colour and style on one sheet. Drawn offscreen.
"$BIN" --wardrobe docs/wardrobe.png -theme workshop

# `-theme` and `-artStyle` are read as defaults for this run only, so they do not change the
# saved settings. Forgetting the window's saved frame gives every picture the default size.
defaults delete Agentville "NSWindow Frame AgentvilleMain" 2>/dev/null || true
run() {
    "$BIN" --demo working --snapshot-scale 2 "$@"
}

for theme in $THEMES; do
    echo "Theme: $theme"
    run --snapshot "docs/themes/$theme.png" --after 16 -theme "$theme" -artStyle smooth
    run --record "$WORK/$theme" --after 16 --seconds 2 -theme "$theme" -artStyle smooth
done
for style in $STYLES; do
    echo "Style: $style"
    run --snapshot "docs/styles/$style.png" --after 16 -theme workshop -artStyle "$style"
done

python3 scripts/make_gif.py "$WORK" docs $THEMES
ls -la docs docs/themes docs/styles
