#!/bin/bash
# Builds Drawer.app into ./build.
#   ./build.sh          build only
#   ./build.sh run      build and launch
#   ./build.sh install  build, copy to /Applications and launch
#   ./build.sh zip      build and write build/Drawer.zip (and its SHA-256) for sharing
#   ./build.sh dmg      build and write build/Drawer.dmg (and its SHA-256) for sharing
#   ./build.sh dev      fast debug build (a few seconds after the first), then launch; for trying changes. It is
#                       unoptimised, so judge smoothness with a normal build, and never release a dev build.
# Preview channel: DRAWER_CHANNEL=beta ./build.sh [run|install] builds "Drawer Beta" (own bundle id, data folder and
# drawer-beta:// scheme), so changes can be tried out beside the real app. Only the real app is ever released.
set -euo pipefail
cd "$(dirname "$0")"
CONFIG=release
[ "${1:-}" = "dev" ] && CONFIG=debug
swift build -c "$CONFIG"
if [ "${DRAWER_CHANNEL:-}" = "beta" ]; then
  NAME="Drawer Beta"; BUNDLE_ID="com.studioab.drawer.beta"; SCHEME="drawer-beta"
else
  NAME="Drawer"; BUNDLE_ID="com.studioab.drawer"; SCHEME="drawer"
fi
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/Drawer" "$APP/Contents/MacOS/$NAME"
# SwiftPM records the deployment target (14.0) as the SDK version, which makes macOS draw the old control
# styles (round gray switch knobs). Stamp the real SDK so the current system look is used. Still runs on 14+.
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || echo 26.0)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/$NAME" "$APP/Contents/MacOS/$NAME"
mkdir -p "$APP/Contents/Resources"
# The icon is drawn by make-icon.swift (Command Line Tools only) the first time and kept as an .icns.
if [ "${DRAWER_CHANNEL:-}" = "beta" ]; then ICON=AppIcon-beta; ICON_ARGS="beta"; else ICON=AppIcon; ICON_ARGS=""; fi
if [ ! -f "$ICON.icns" ]; then
  swift make-icon.swift "$ICON" $ICON_ARGS && iconutil -c icns "$ICON.iconset" -o "$ICON.icns" && rm -rf "$ICON.iconset"
fi
cp "$ICON.icns" "$APP/Contents/Resources/AppIcon.icns"
cp Drawer.sdef "$APP/Contents/Resources/Drawer.sdef"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5.1</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleScriptEnabled</key><true/>
  <key>OSAScriptingDefinition</key><string>Drawer.sdef</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>$NAME</string>
    <key>CFBundleURLSchemes</key><array><string>$SCHEME</string></array>
  </dict></array>
</dict></plist>
PLIST
if [ -n "${DRAWER_SIGN_IDENTITY:-}" ]; then
  # A real certificate (e.g. "Apple Development: Name (TEAMID)") once Xcode is installed.
  codesign --force --options runtime --sign "$DRAWER_SIGN_IDENTITY" "$APP"
else
  # Ad-hoc, but with a fixed designated requirement. Without it every rebuild looks like a new app to macOS
  # and the Accessibility permission has to be granted again.
  codesign --force --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign -dr - "$APP" 2>&1 | grep designated
echo "Built $APP"
if [ "${1:-}" = "install" ]; then
  pkill -x "$NAME" || true
  rm -rf "/Applications/$NAME.app" && cp -R "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed to /Applications/$NAME.app"
elif [ "${1:-}" = "zip" ]; then
  rm -f build/Drawer.zip
  ditto -c -k --keepParent "$APP" build/Drawer.zip
  (cd build && shasum -a 256 Drawer.zip | tee Drawer.zip.sha256)
  echo "Wrote build/Drawer.zip"
elif [ "${1:-}" = "dmg" ]; then
  rm -rf build/dmg build/Drawer.dmg
  mkdir -p build/dmg
  cp -R "$APP" build/dmg/Drawer.app
  ln -s /Applications build/dmg/Applications
  hdiutil create -volname "Drawer" -srcfolder build/dmg -ov -format UDZO build/Drawer.dmg >/dev/null
  rm -rf build/dmg
  (cd build && shasum -a 256 Drawer.dmg | tee Drawer.dmg.sha256)
  echo "Wrote build/Drawer.dmg"
elif [ "${1:-}" = "run" ] || [ "${1:-}" = "dev" ]; then
  pkill -x "$NAME" || true
  open "$APP"
fi
