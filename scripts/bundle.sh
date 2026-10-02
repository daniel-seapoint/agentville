#!/bin/bash
# Builds a release binary and wraps it in build/Agentville.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/Agentville.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Agentville" "$APP/Contents/MacOS/Agentville"

mkdir -p "$APP/Contents/Resources"
cp -R Sources/Agentville/Resources/Logos "$APP/Contents/Resources/Logos"

# App icon: every size macOS asks for, made from the 1024px artwork in icon/.
# Regenerate that artwork with: swift run Agentville --icon icon
ICON_SOURCE="icon/Agentville-icon-smooth.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Agentville</string>
    <key>CFBundleDisplayName</key><string>Agentville</string>
    <key>CFBundleIdentifier</key><string>dev.agentville.app</string>
    <key>CFBundleExecutable</key><string>Agentville</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will launch it locally.
codesign --force --sign - "$APP"
echo "Built $APP — open it with: open $APP"
