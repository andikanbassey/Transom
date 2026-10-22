# Transom

Native macOS menu bar app: clipboard history, quick notes and pinned files in a window that opens at the top screen
edge (renamed from Drawer in 0.7; in the code and these notes "the drawer" still means that panel). Swift 5 mode, AppKit + SwiftUI, no dependencies. Bundle id `com.studioab.drawer`. Maintainer: Andikan Bassey.

This file is the working guide for anyone, human or AI assistant, changing the code. See also [CONTRIBUTING.md](CONTRIBUTING.md).
Personal, machine-specific notes live in `CLAUDE.local.md`, which is not committed.

## Build and run

- `./build.sh` build to `build/Transom.app`; `run` build and launch; `dev` fast debug build and launch; `install` copy to
  /Applications and launch; `zip` / `dmg` write the sharing files.
- `dev` is for trying changes: an edit to one file rebuilds in a few seconds (a change to something used everywhere, such as
  `Theme.swift`, takes about a minute) against about 90 seconds for the optimised build the other targets make. It is
  unoptimised, so judge smoothness with `run` and never release a dev build.
- Only the Command Line Tools are needed; **Xcode was tried and dropped** (heavy, and nothing here needs it). Signing is ad hoc
  with a fixed designated requirement (`identifier "<bundle id>"`) so the Accessibility grant survives rebuilds; use
  `TRANSOM_SIGN_IDENTITY` for a real certificate.
- `build.sh` stamps the binary with the real SDK using `vtool`. Without it SwiftPM records SDK 14 and macOS draws the
  old control styles (round gray switch knobs).
- No `@State` or other SwiftUI macros: the CLT SDK lacks the macro plugin. Use `Box<T>` (ObservableObject) in
  `Views.swift` for local view state, and `Binding(get:set:)` rather than `@Bindable`.
- The icon is drawn by `make-icon.swift` (Command Line Tools only) into `AppIcon.icns`; delete it to
  regenerate it. A layered Icon Composer icon was tried and dropped (it needs Xcode). The Xcode project is in git history
  (commits "Add an Xcode project for Transom and Transom Beta" and "New app icon as Icon Composer files") if it is ever wanted again.
- No `timeout` command on macOS. `screencapture` is not permitted from the shell.

## Testing without touching real data

There is one app (a Beta channel was tried and dropped; it is in git history). `./build.sh dev` and test runs use your real
history, notes and settings, so for anything risky run the binary with `TRANSOM_SUPPORT_DIR=/tmp/transom-test` (a scratch folder,
fresh settings, nothing synced): `TRANSOM_SUPPORT_DIR=/tmp/transom-test build/Transom.app/Contents/MacOS/Transom`. Any `TRANSOM_*`
(or the old `DRAWER_*`, still read as a fallback by `Env.swift`) variable also skips the "another copy is running" question. Icons, colours and names are in `BRANDING.md`. A second Transom asks
which to keep (`InstanceGuard.swift`); `TRANSOM_GUARD_CHOICE=use-this|use-other|keep-both` answers it for tests.
`TRANSOM_DROP_TEST=1` drops sample items on Notes and Quick Access (use a scratch folder).

## Verifying UI

Offscreen render to PNG, then read the image:

- `TRANSOM_SNAPSHOT=/tmp/x.png Transom --show` renders the drawer.
- `TRANSOM_SNAPSHOT_VIEW=/tmp/settings.png` (or a path ending `onboarding.png`) renders the settings window or the
  welcome; `TRANSOM_PANE=<pane>` and `TRANSOM_STEP=<n>` choose what shows.
- Set `TRANSOM_NOGLASS=1`: Liquid Glass and blur do not render offscreen (the image comes out blank or hard-edged).
  Glass can only be judged in the live app.
- Run these in the background with a `sleep` and `kill`, since the app does not exit by itself.

## Layout of the code

See README.md. Key points: `Transom.swift` owns the panel and all open/close triggers; `Views.swift` holds the three
columns; `Settings.swift` has the settings model (new fields merge over defaults, so old settings files keep working)
plus the hotkey and paste helpers; `Stores.swift` has the files and notes stores and `AppModel`.

## Decisions to keep

- Layout follows Unclutter (three equal columns: clipboard, files, notes). Feature set follows Paste. Do not copy
  either one for one.
- Look should feel premium: spacing, hierarchy, Liquid Glass on macOS 26+, native macOS switches and controls
  (custom switches were rejected).
- The drawer closes only on a click outside by default. Optional auto-close after 5, 10 or 15 seconds.
- Scrolling down anywhere in the menu bar's height opens the drawer (`scrollBand` in `Transom.swift`: the menu bar's height while it shows, else 2 pt). Settings › Shortcuts can restrict it to the top edge. `TRANSOM_SCROLL_TEST=1,12,300` feeds scroll events at those heights below the top of the screen and writes which opened the drawer to `/tmp/drawer-scroll-test.txt`.
- Scroll direction is inverted separately for mouse and trackpad (trackpad = events with a gesture phase).
- Notes are Markdown files in a folder; files can be references or copies in a folder; iCloud sync works by pointing
  those folders at iCloud Drive. Clipboard history sync (CloudKit) is on the roadmap.
- Clipboard items are plain text, files or images. No rich text yet.
- Right-click anywhere on Transom opens the app menu. Each panel has a "⋯" menu, and the right-most panel has the
  global settings gear.

## Also decided

- Default drawer: Files left, Clipboard in the middle (3/5 of the width, cards), Notes right. One layout, no interface toggle.
  Files and Notes in the drawer keep their original tile and list views; Cards/Lists/Custom (Settings › Appearance › Items)
  applies to the clipboard in the drawer and to everything in the Library.
- Clipboard history is one Markdown file per month in a Clipboard folder (see docs/DESIGN.md). No item cap; time is the only limit.
- One window holds the Library and Settings, switched by the two-sided Library | Settings pill at the bottom of both sidebars (`ModeSwitch`). The two sidebars share one structure (brand, quiet group headers, rows, the pill) so it reads as one app. It shows in the Dock while open. Page headings use `Look.headerGap` below them everywhere.
  Library and Settings share one look (`Look` in Theme.swift): keep fonts, cards and sidebars consistent between them.
- Global search lives in each page header (⌘K) and searches the page you are on.
- Library cards: coloured frame fading toward the bottom; on hover the card grows over the frame (no content zoom).
- Transom clipboard cards scale as a whole with the drawer height.
- Clipboard pictures: with a synced clipboard folder, `picturesStayOnThisMac` writes new pictures to `Application Support/Transom/ClipboardImages` (local) instead of `<folder>/Images`; `ClipboardFolder.imageURL` looks local first, then the synced folder. Deleting an item or clearing history removes the file from both places.
- Library lists show 48 items a page (`Look.pageSize`, `TRANSOM_PAGE_SIZE=4` to test the pagination bar); empty pages use `EmptyState` (Theme.swift) with the one action that fills them. The Library hides the store's blank "always one note".
- Debug aids: `TRANSOM_MARK_SENSITIVE=<n>` (with a scratch `TRANSOM_SUPPORT_DIR`: marks the newest n items sensitive with different times left, to see the countdown and dissolve; it deletes them from that scratch history), `TRANSOM_LIGHT=1`, `TRANSOM_SECTION=<section>`, `TRANSOM_SNAPSHOT_DELAY=<seconds>`, `~/Library/Application Support/Transom/debug-scroll` (logs scroll events),
  and `TRANSOM_COPY_LATEST_IMAGE=1` (with `TRANSOM_PASTE=1`) to copy the newest image and paste it into the front app.
  Run those with `open -n -a /Applications/Transom.app --env NAME=1` so macOS uses the app's own Accessibility permission.
- Sensitive clips (`Clip.sensitive`): set when the pasteboard is concealed or `SecretPatterns` matches; shown as `SensitiveText`, excluded from `save()`, search, pinning, Save To, drag-in to Notes and Quick Access, and expired by `expireSensitive()` after 15 minutes. Anything that displays or exports clip text must check the flag.
- Tests: `swift test` (Swift Testing, `Tests/TransomTests`) covers the Markdown history format, version comparison, secret detection and folder-path handling; `swift test` needs to run outside Claude Code's sandbox (the Testing macro plugin is blocked inside it; if it still says the macro plugin is not found, kill stale `swift-plugin-server` processes and retry); add to it when touching storage or merge. CI (`.github/workflows/swift.yml`) runs them, then `./build.sh zip`, checks the bundle and keeps the zip as an artifact.
- Updates: `Updater.swift` asks GitHub releases/latest (tag `vX.Y`, assets must be named `Transom.dmg` and `Transom.dmg.sha256`), installs by mounting the DMG, verifying checksum and signature, then a shell script swaps the app after quit and reopens it. It needs the repo to be public. Test with `TRANSOM_UPDATE_FILE=/path/Transom.dmg TRANSOM_UPDATE_INSTALL=1` in a **debug build** (`./build.sh dev`; release builds ignore these) on a **copy** of the app in /tmp, since it replaces the app it runs from.
