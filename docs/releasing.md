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

Pushing a tag does it for you: `git tag vX.Y.Z && git push origin vX.Y.Z` runs `.github/workflows/release.yml`, which tests, builds the DMG, checks the tag against the version in `build.sh`, and creates the release with `Transom.dmg`, `Transom.dmg.sha256` and the changelog entry as the notes. Check the release afterwards (download it back and compare checksums). By hand, it is:

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

- `swift test` passes (CI runs it on every pull request).
- Drag, Select and delete, scrolling on the menu bar, keyboard navigation, two copies running together, and the Library | Settings switch, all tried by hand.
- Upgrade from the previous version with data kept.
- VoiceOver over the drawer and the Library; contrast on glass at low opacity.
- Sync between two Macs, including pictures arriving after their history entry.
- Idle CPU and memory with a long history; launch with the network off.
- macOS 14, 15 and 26; a notched MacBook; two displays; a full-screen app in front.

## Performance budget

Measured on 2026-10-17 with the release build from a fresh clone, on an Apple silicon Mac running macOS 27.0.1 (built against the macOS 27 SDK, minimum macOS 14), drawer closed, capture paused, a history of 5,000 items over three months. Re-measure before a release and update the numbers.

| | Budget | Measured |
|---|---|---|
| Build from a fresh clone (`./build.sh dmg`) | under 3 minutes | 77 s |
| Launch peak memory (first seconds) | under 150 MB | about 100 MB |
| Memory once settled | under 40 MB | 10 to 18 MB over 5 minutes |
| Idle CPU, averaged over 5 minutes | under 1% | 0.4% (1.2 s of CPU in 290 s) |
| Launch with the network off | opens, no crash, no dialog | opens at 38 MB; the update check fails silently; no crash report |

Long history, measured 2026-10-23 with `footprint` (release build, 20,000 text items over 13 months, drawer closed): 94 MB before the drawer drew only a window of the history, 47 MB after; an empty history is 25 MB. The rest is the history itself held in memory (about 22 MB for 20,000 items); loading older months only on demand is the next step.

Launch work with the same 20,000 items: 14.1 s of CPU before batching the removals at launch, 3.7 s after (an empty history needs 0.9 s); it runs off the main thread, so the menu bar icon and drawer are not held up.

Not covered yet: memory with a year of history including pictures, and CPU while Transom is open and scrolling.
