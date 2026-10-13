# Drawer

A clipboard history, quick notes and pinned files, tucked behind the top edge of your screen on macOS.
Scroll at the top of the screen and a drawer slides down. Everything you copied is a click away, with real cover
images for pictures, videos, links and files.

Drawer takes its layout from [Unclutter](https://unclutterapp.com) and its clipboard feature set from
[Paste](https://pasteapp.io). It is an independent project and is not affiliated with either.

> **Status:** early (v0.4). It is a native Swift app with no third-party dependencies.

## Features

### Opening and closing
- **Scroll at the top edge** to open, swipe up over the top of the drawer to close.
- **Hold a key** or **wait** at the top edge, or press a **global hotkey** (⇧⌘V by default, rebindable).
- Stays open until you click outside it, or closes by itself after 5, 10 or 15 seconds if you prefer.
- Scroll direction can be inverted separately for mouse and trackpad.
- Right-click anywhere on the drawer for pause, panel toggles and settings.

### Keyboard
- **← →** (cards) or **↑ ↓** (list) move through clipboard items, **Return** pastes, **⌥Return** pastes as plain text.
- **Space** previews the selected item, **Esc** steps back, then closes.
- **⌘F** searches, and so does simply starting to type.
- **⌘1–⌘9** quick paste still works as before.

### Clipboard history
- Every item gets a **cover image and a type pill**: text, link, colour, image, GIF, video, audio, PDF, folder or file.
- Real previews: first frame of videos and GIFs, first page of PDFs, page title and image for links,
  swatches for hex colours.
- Grouped by recency: Pinned, Past Hour, Today, Yesterday, This Week, This Month, Older.
- **Paste straight into the app you were using**, or just copy. ⌘1–⌘9 quick paste.
- Pin, search, filter by type, and see which app each item came from.
- History kept for a day, week, month, year or forever. Time is the only limit.
- Stored as one Markdown file per month, with formatting kept as Markdown, in the Clipboard folder.

### Files
- Pin files and folders by dragging them in, or keep copies in a folder of your choice.
- Icon or list view, three item sizes, sort by name, kind, date added or date modified.
- Drag files back out to any app.

### Notes
- Notes are plain **Markdown files** in a folder you choose.
- Opens on the list of your notes with a preview line each, remembers the note you were editing.

### Privacy
- Skips passwords and other items that apps flag as concealed or transient.
- Allow list and block list for the apps Drawer records from.
- Optionally hide the drawer from screen sharing.
- Link previews can be switched off. They download the page to get a title and image.
- Everything is stored locally. Nothing is sent anywhere.

### Look and feel
- Liquid Glass on macOS 26 and later, a blurred material on earlier versions.
- Dark, light or system theme, background opacity, drawer height, camera-notch aware.
- Menu bar icon with pause, settings and quit. First-launch welcome screen.

### iCloud
- Keep notes and files in iCloud Drive with one switch. macOS syncs the folders between your Macs.

## Install

Drawer needs **macOS 14 or later**.

### Build from source

You need the Swift toolchain. The Xcode Command Line Tools are enough (`xcode-select --install`).

```bash
git clone <this repository>
cd <this repository>
./build.sh install     # builds, copies to /Applications and launches
```

Other targets:

```bash
./build.sh             # build only: build/Drawer.app
./build.sh run         # build and launch from build/
./build.sh zip         # build and write build/Drawer.zip for sharing
```

The first launch opens a short welcome. Because the app is signed ad-hoc, a copy downloaded from elsewhere needs
right-click → Open the first time.

### Signing

By default the app is signed ad-hoc with a fixed designated requirement
(`identifier "com.studioab.drawer"`), so macOS keeps the Accessibility permission across rebuilds.
To sign with a real certificate instead:

```bash
security find-identity -v -p codesigning
DRAWER_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh install
```

## Permissions

| Permission | Why | Required |
|---|---|---|
| Accessibility | Press ⌘V in the app you were using, so a chosen item pastes directly | Only for "paste into the app". Without it items are copied and you paste yourself |

Opening the drawer by scrolling, holding a key, waiting or the hotkey needs no permission.

## Data

Stored in `~/Library/Application Support/Drawer/`:

- `settings.json` for settings; `Clipboard/` (monthly Markdown files and an `Images/` folder) for clipboard history
- `Notes/` and `Files/` unless you pick other folders (or iCloud Drive) in Settings

## Project layout

```
Sources/Drawer/
  main.swift          app entry, menu bar item, hotkey wiring
  Drawer.swift        the panel: triggers, scroll, show and hide
  Views.swift         drawer UI: clipboard, files and notes columns
  Clipboard.swift     clipboard model, capture, categories, previews
  Stores.swift        files and notes stores, shared app model
  Settings.swift      settings model, hotkeys, pasting
  SettingsView.swift  settings window
  Onboarding.swift    first-launch welcome
  Theme.swift         glass helper, button style, menu bar icon
build.sh              build, bundle, sign, install
make-icon.swift       renders the app icon
```

Debug aids: `Drawer --show` keeps the drawer open, and `DRAWER_SNAPSHOT=/path.png` renders it to an image.

## Automation

Off by default (Settings › Advanced › Automation). Once on, other apps and scripts can drive Drawer.

**Links** (`open "drawer://…"`):

| Link | Does |
|---|---|
| `drawer://open`, `drawer://close` | Show or hide the drawer |
| `drawer://search?q=invoice` | Open the Library on the clipboard with a search |
| `drawer://pause`, `resume`, `toggle-pause` | Pause or resume capture |
| `drawer://note?text=Hello` | Create a note |
| `drawer://pin?index=1` | Pin a clipboard item (1 is the newest) |
| `drawer://copy?index=1&plain=1` | Put an item back on the clipboard |
| `drawer://paste?index=1&plain=1` | Paste an item into the app in front |

**AppleScript:** `clip count`, `get clip text 1`, `copy clip 1`, `paste clip 1`, `pin clip 1`, `pause capture`,
`resume capture`, `new note "…"`, `search clips "…"`, `open drawer`. For example:
`osascript -e 'tell application "Drawer" to get clip text 1'`.

**Safety:** links that only change Drawer always work once automation is on. Copying and pasting for another app needs
that app to be trusted (you are asked the first time; trusted apps are listed in Settings and can be removed).
Clipboard content can be read out only with AppleScript, never through a link.

## Roadmap

**Next**
- Keyboard navigation inside the drawer (arrows and Return)
- Rich text and original image formats when pasting (items are plain text today)
- Notarized release and a DMG

**Planned**
- CloudKit sync for clipboard history (notes and files already sync through iCloud Drive)
- Pinboards: named groups of clipboard items
- Video duration and richer previews
- Per-app paste rules and plain-text mode
- Localization
- Automated tests

**Ideas**
- Shortcuts and AppleScript actions
- Snippets and text expansion
- Clipboard rules (strip tracking parameters, format on paste)

## Credits

Inspired by Unclutter and Paste. Built with Swift, AppKit and SwiftUI.

## Author

Andikan Bassey · [contact@andikanbassey.com](mailto:contact@andikanbassey.com)

## License

[MIT](LICENSE) © 2026 Andikan Bassey
