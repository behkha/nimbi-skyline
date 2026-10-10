#!/bin/bash
# Builds Skyline.app (release) into ./build. Needs only the Xcode Command Line Tools.
#   scripts/build.sh            build
#   scripts/build.sh --install  build and copy to /Applications
# Set SKYLINE_PROXY_URL to bake the Worker's URL into Info.plist; without it the app talks to
# api.met.no directly, which is fine for development only.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Skyline.app"
VERSION="0.1.0"
PROXY_URL="${SKYLINE_PROXY_URL:-}"

echo "==> Compiling (release)"
set +e
swift build -c release --arch arm64 2>&1 | grep -vE "search path .* not found"
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || { echo "build failed (swift build exit $STATUS)"; exit 1; }
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Skyline"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Skyline"
# SwiftPM resource bundles (NimbiKit has none today), if any appear later.
find "$(dirname "$BIN")" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "==> Drawing icon"
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset 2>&1 | grep -vE "search path" || true
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Skyline</string>
  <key>CFBundleDisplayName</key><string>Skyline</string>
  <key>CFBundleIdentifier</key><string>app.nimbi.skyline</string>
  <key>CFBundleExecutable</key><string>Skyline</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Skyline by nimbi. Weather data © MET Norway (CC BY 4.0).</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocationUsageDescription</key><string>Skyline uses your location to show the weather where you are.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Skyline uses your location to show the weather where you are.</string>
  <key>SkylineProxyURL</key><string>$PROXY_URL</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP" && echo "    signature ok"

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  pkill -x Skyline 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Skyline.app
  cp -R "$APP" /Applications/
  echo "    /Applications/Skyline.app"
fi
echo "Done: $APP"
