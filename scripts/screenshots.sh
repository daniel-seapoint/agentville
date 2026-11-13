#!/bin/bash
# Renders the README's pictures of the themes and agent styles from the scripted demo.
# Needs a Mac with a logged-in desktop, since the floor is drawn by SpriteKit on screen.
# Makes: docs/wardrobe.png, docs/themes/<theme>.png, docs/styles/<style>.png, docs/themes.gif,
# docs/styles.gif, docs/santaClaude.gif
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Agentville"
THEMES="workshop daylight forest ocean space sunset terminal winter simpsons starWars lordOfTheRings shire harryPotter santaClaude"
STYLES="smooth pixel toon hologram"
WORK="$(mktemp -d)"
mkdir -p docs/themes docs/styles

# Every hat, accessory, pattern, colour and style on one sheet. Drawn offscreen.
"$BIN" --wardrobe docs/wardrobe.png -theme workshop
# The README's icon: the mascot dressed as characters from each film and TV world.
"$BIN" --icon-gif docs/icon.gif -theme workshop
# Each film, TV and seasonal theme's cast, named. Drawn offscreen.
"$BIN" --casts docs/cast -theme workshop -artStyle smooth

# `-theme` and `-artStyle` are read as defaults for this run only, so they do not change the
# saved settings. Forgetting the window's saved frame gives every picture the default size.
defaults delete Agentville "NSWindow Frame AgentvilleMain" 2>/dev/null || true
run() {
    "$BIN" --demo working --snapshot-scale 2 "$@"
}

# The agent style each film or TV theme brings with it; the others are shown in Smooth.
style_for() {
    case "$1" in
        simpsons) echo toon ;;
        *) echo smooth ;;
    esac
}

for theme in $THEMES; do
    style="$(style_for "$theme")"
    echo "Theme: $theme in $style"
    run --snapshot "docs/themes/$theme.png" --after 16 -theme "$theme" -artStyle "$style"
    run --record "$WORK/themes/$theme" --after 16 --seconds 2 -theme "$theme" -artStyle "$style"
    echo "  recorded $(ls "$WORK/themes/$theme" | wc -l | tr -d ' ') frames"
done
# Most styles are shown on the Workshop floor; the themed ones on the theme made for them.
for style in $STYLES; do
    case "$style" in
        toon) theme=simpsons ;;
        hologram) theme=starWars ;;
        *) theme=workshop ;;
    esac
    echo "Style: $style on $theme"
    run --snapshot "docs/styles/$style.png" --after 16 -theme "$theme" -artStyle "$style"
    run --record "$WORK/styles/$style" --after 16 --seconds 2 -theme "$theme" -artStyle "$style"
    echo "  recorded $(ls "$WORK/styles/$style" | wc -l | tr -d ' ') frames"
done

python3 scripts/make_gif.py docs themes.gif $(for theme in $THEMES; do echo "$WORK/themes/$theme"; done)
python3 scripts/make_gif.py docs styles.gif $(for style in $STYLES; do echo "$WORK/styles/$style"; done)

# A longer look at Santa Claude, with the sleigh flying over.
echo "Santa Claude"
run --record "$WORK/santaClaude" --after 11 --seconds 7 -theme santaClaude -artStyle smooth
GIF_FRAMES=35 python3 scripts/make_gif.py docs santaClaude.gif "$WORK/santaClaude"
ls -la docs docs/themes docs/styles
