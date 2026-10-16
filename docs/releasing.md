# Releasing

How a Transom release is made. The same steps keep the in-app updater working, because it reads the latest GitHub release.

## Before you tag

1. Bump the version in `build.sh` (`CFBundleShortVersionString` and `CFBundleVersion`). The app compares its own version with the
   release tag, so a release built from an old version would offer itself as an update.
2. In `CHANGELOG.md`, turn "Unreleased" into the new version with a date. Write it as what people can now do, one line each.
3. Build with plain `./build.sh dmg` (never `dev`) and check the app: name, icon, version, and that it opens on a Mac or
   account that has never run Transom.
4. Put the DMG's SHA-256 (printed by the build, also written to `build/Transom.dmg.sha256`) in the changelog entry.

## Publish

- Tag `vX.Y` (or `vX.Y.Z`) on `main` and create a GitHub release.
- Attach exactly `Transom.dmg` and `Transom.dmg.sha256`. The updater downloads the DMG, checks it against the checksum file,
  verifies the app's signature, and swaps the app in place.
- The repository must be public for the updater to see the release.
- Check the download: fetch the asset back and compare its checksum with the one in the notes.

## Signing and notarization

Releases are currently ad-hoc signed with a fixed designated requirement (`identifier "com.studioab.drawer"`), so macOS keeps the
Accessibility permission across updates, but they are **not notarized**. The README explains the first-launch warning. A
notarized release needs a paid Apple Developer membership: a Developer ID Application certificate
(`TRANSOM_SIGN_IDENTITY="…" ./build.sh`), then `notarytool` and `stapler` added to `build.sh`.

## Checks before a public release

- Drag, Select and delete, scrolling on the menu bar, keyboard navigation, two copies running together, and the Library | Settings switch, all tried by hand.
- Upgrade from the previous version with data kept.
- VoiceOver over the drawer and the Library; contrast on glass at low opacity.
- Sync between two Macs, including pictures arriving after their history entry.
- Idle CPU and memory with a long history; launch with the network off.
- macOS 14, 15 and 26; a notched MacBook; two displays; a full-screen app in front.
