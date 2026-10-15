#!/bin/bash
# Builds Transom.app into ./build.
#   ./build.sh          build only
#   ./build.sh run      build and launch
#   ./build.sh install  build, copy to /Applications and launch
#   ./build.sh zip      build and write build/Transom.zip (and its SHA-256) for sharing
#   ./build.sh dmg      build and write build/Transom.dmg (and its SHA-256) for sharing
#   ./build.sh clean    delete .build and build (the compiler's caches grow to about 1 GB over time; the next build is a clean
#                       one, about a minute). Worth doing after a Command Line Tools or macOS update.
#   ./build.sh dev      fast debug build (a few seconds after the first), then launch; for trying changes. It is
#                       unoptimised, so judge smoothness with a normal build, and never release a dev build.
# To try a build without touching your real history, notes and settings, run it with TRANSOM_SUPPORT_DIR set to a
# scratch folder (see CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = "clean" ]; then
  rm -rf .build build
  echo "Cleaned .build and build"
  exit 0
fi
CONFIG=release
[ "${1:-}" = "dev" ] && CONFIG=debug
swift build -c "$CONFIG"
NAME="Transom"; BUNDLE_ID="com.studioab.drawer"; SCHEME="transom"   # the bundle id is kept from the Drawer days on purpose: the Accessibility grant, login item and preferences survive
LEGACY_SCHEME="drawer"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/Transom" "$APP/Contents/MacOS/$NAME"
# SwiftPM records the deployment target (14.0) as the SDK version, which makes macOS draw the old control
# styles (round gray switch knobs). Stamp the real SDK so the current system look is used. Still runs on 14+.
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || echo 26.0)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/$NAME" "$APP/Contents/MacOS/$NAME"
mkdir -p "$APP/Contents/Resources"
# The icon is drawn by make-icon.swift (Command Line Tools only) the first time and kept as an .icns.
if [ ! -f AppIcon.icns ]; then
  swift make-icon.swift AppIcon && iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf AppIcon.iconset
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Transom.sdef "$APP/Contents/Resources/Transom.sdef"
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
  <key>CFBundleShortVersionString</key><string>0.6.0</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleScriptEnabled</key><true/>
  <key>OSAScriptingDefinition</key><string>Transom.sdef</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>$NAME</string>
    <key>CFBundleURLSchemes</key><array><string>$SCHEME</string><string>$LEGACY_SCHEME</string></array>
  </dict></array>
</dict></plist>
PLIST
if [ -n "${TRANSOM_SIGN_IDENTITY:-${DRAWER_SIGN_IDENTITY:-}}" ]; then
  # A real certificate (e.g. "Apple Development: Name (TEAMID)") once Xcode is installed.
  codesign --force --options runtime --sign "${TRANSOM_SIGN_IDENTITY:-$DRAWER_SIGN_IDENTITY}" "$APP"
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
  rm -f build/Transom.zip
  ditto -c -k --keepParent "$APP" build/Transom.zip
  (cd build && shasum -a 256 Transom.zip | tee Transom.zip.sha256)
  echo "Wrote build/Transom.zip"
elif [ "${1:-}" = "dmg" ]; then
  rm -rf build/dmg build/Transom.dmg
  mkdir -p build/dmg
  cp -R "$APP" build/dmg/Transom.app
  ln -s /Applications build/dmg/Applications
  hdiutil create -volname "Transom" -srcfolder build/dmg -ov -format UDZO build/Transom.dmg >/dev/null
  rm -rf build/dmg
  (cd build && shasum -a 256 Transom.dmg | tee Transom.dmg.sha256)
  echo "Wrote build/Transom.dmg"
elif [ "${1:-}" = "run" ] || [ "${1:-}" = "dev" ]; then
  pkill -x "$NAME" || true
  open "$APP"
fi
