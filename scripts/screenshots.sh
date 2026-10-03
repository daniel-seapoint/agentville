#!/bin/bash
# Renders the README's pictures of the themes and agent styles from the scripted demo.
# Needs a Mac with a logged-in desktop, since the floor is drawn by SpriteKit on screen.
# Makes: docs/wardrobe.png, docs/themes/<theme>.png, docs/styles/<style>.png, docs/themes.gif,
# docs/styles.gif
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Agentville"
THEMES="workshop daylight forest ocean space sunset terminal winter suburbia hyperspace hearthland spellhall"
STYLES="smooth pixel outlined glow toon hologram parchment spectral"
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
    run --record "$WORK/themes/$theme" --after 16 --seconds 2 -theme "$theme" -artStyle smooth
    echo "  recorded $(ls "$WORK/themes/$theme" | wc -l | tr -d ' ') frames"
done
# Most styles are shown on the Workshop floor; the themed ones on the theme made for them.
for style in $STYLES; do
    case "$style" in
        toon) theme=suburbia ;;
        hologram) theme=hyperspace ;;
        parchment) theme=hearthland ;;
        spectral) theme=spellhall ;;
        *) theme=workshop ;;
    esac
    echo "Style: $style on $theme"
    run --snapshot "docs/styles/$style.png" --after 16 -theme "$theme" -artStyle "$style"
    run --record "$WORK/styles/$style" --after 16 --seconds 2 -theme "$theme" -artStyle "$style"
    echo "  recorded $(ls "$WORK/styles/$style" | wc -l | tr -d ' ') frames"
done

python3 scripts/make_gif.py docs themes.gif $(for theme in $THEMES; do echo "$WORK/themes/$theme"; done)
python3 scripts/make_gif.py docs styles.gif $(for style in $STYLES; do echo "$WORK/styles/$style"; done)
ls -la docs docs/themes docs/styles
