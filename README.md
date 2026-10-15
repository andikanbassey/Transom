# Drawer

A clipboard history, quick notes and pinned files, tucked behind the top edge of your screen on macOS.
Scroll at the top of the screen and a drawer slides down. Everything you copied is a click away, with real cover
images for pictures, videos, links and files.

Drawer takes its layout from [Unclutter](https://unclutterapp.com) and its clipboard feature set from
[Paste](https://pasteapp.io). It is an independent project and is not affiliated with either.

![The Drawer, with sample items](docs/images/drawer.png)

> **Status:** early (v0.6). It is a native Swift app with no third-party dependencies.

## Features

### Opening and closing
- **Scroll down anywhere along the menu bar** to open (with a hidden menu bar, at the very top edge), swipe up over the top of the drawer to close. Settings › Shortcuts can limit it to the top edge. The shortcut, hold-a-key and wait openers are there too.
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
- Pin, search, and filter by **time, type and app** with three dropdowns; each item shows which app it came from.
- **Drag an item** onto Quick Access to keep it, or onto Notes to make a note from it (pictures are embedded).
- Copying the same picture again moves the earlier item to the top instead of storing it twice.
- History kept for a day, week, month, year or forever. Time is the only limit.
- Stored as one Markdown file per month, with formatting kept as Markdown, in the Clipboard folder.

### Quick Access
- Pin files and folders by dragging them in, or keep copies in a folder of your choice.
- Icon or list view, three item sizes, sort by name, kind, date added or date modified.
- Drag files back out to any app.

### Notes
- Notes are plain **Markdown files** in a folder you choose; pictures sit in an `Attachments` folder beside them.
- Opens on the list of your notes with a preview line each, remembers the note you were editing.

### Library
- A bigger window for everything, opened from the menu bar: clipboard, pinned, notes and Quick Access, with search (⌘K) for the page you are on.
- **Select** several items to pin or delete them together, or pick "last 5 minutes", "last hour" or "today" and clear them in one go.
- Cards or lists, for everything or per kind. Settings sit one click away, behind the same window.

### Privacy
- Skips passwords and other items that apps flag as concealed or transient.
- Allow list and block list for the apps Drawer records from.
- Optionally hide the drawer from screen sharing.
- Link previews can be switched off. They download the page to get a title and image.
- Everything is stored locally. Nothing is sent anywhere: no accounts, no analytics. The only network use is link previews (off if you like) and the iCloud Drive sync you turn on yourself.
- Link cover images are kept on your Mac only, never in the synced folder.

### Look and feel
- Liquid Glass on macOS 26 and later, a blurred material on earlier versions.
- Dark, light or system theme, background opacity, drawer height, camera-notch aware.
- Menu bar icon with pause, settings and quit. First-launch welcome screen.

### Updates
- Drawer checks GitHub for a new release about once a day and tells you in the menu bar menu (and once in a dialog per version). **Update Now** downloads the DMG, checks it against the published checksum, replaces the app in place and reopens it. Your settings and Accessibility permission carry over. Turn the check off in Settings › General, or use **Check for Updates** in About any time.

### iCloud
- Keep notes and files in iCloud Drive with one switch. macOS syncs the folders between your Macs.

## Install

Drawer needs **macOS 14 or later**.

### Download

1. Download `Drawer.dmg` from the [Releases](../../releases) page and open it.
2. Drag **Drawer** into **Applications**, then open it.
3. **macOS will warn that it can't verify the app.** This is expected, and it is explained below.

#### Why macOS shows a warning

Drawer is **not notarized by Apple yet**. Notarization needs a paid Apple Developer membership, which I don't have
at the moment. For any app that isn't notarized, macOS shows a standard warning along the lines of
*"Apple could not verify 'Drawer' is free of malware that may harm your Mac or compromise your privacy."*
That message is about Apple not having checked the app. It does not mean anything was found in it. Notarization is on
the list for when it is available.

#### How to open it anyway (once)

- **macOS 15 (Sequoia) and later:** click **Done** on the warning, then open **System Settings › Privacy & Security**,
  scroll down to **Security**, and click **Open Anyway** next to "Drawer was blocked". Confirm with your password or
  Touch ID, then click **Open**. You only need to do this the first time.
- **macOS 14 (Sonoma):** in **Applications**, right-click (or Control-click) **Drawer**, choose **Open**, then **Open**.
- **Terminal alternative (any version):**

  ```bash
  xattr -dr com.apple.quarantine /Applications/Drawer.app
  ```

  then open Drawer normally. This only removes the flag macOS adds to downloaded files.

The wording and the position of buttons change a little between macOS versions.

#### Is it safe?

You don't have to take my word for it:

- **The source is here.** Drawer is open source (MIT) and has no third-party dependencies. Read it, or build it yourself
  with the two commands below. An app you build yourself opens without any warning.
- **Check the download.** Each release lists a SHA-256 checksum. Compare it with
  `shasum -a 256 ~/Downloads/Drawer.dmg`; they should match exactly.
- **What it can see.** The clipboard (that is the point of the app). **Accessibility** is requested only if you want
  items to paste straight into the app you were using; without it, items are copied and you paste yourself.
- **What it sends.** Nothing. Everything is stored on your Mac. The only network use is link previews (a setting you can
  switch off, which downloads the linked page to get a title and image), a once-a-day check for a new version on GitHub
  (Settings › General › Check for updates, also switchable; it sends nothing but a request for the latest release) and iCloud Drive sync if you turn it on, which
  macOS itself performs. There is no analytics or tracking. If that ever changes it will be disclosed and switchable.
- **Where your data lives.** Plain files in `~/Library/Application Support/Drawer/`, or the iCloud Drive folders you pick.
  See [Data](#data). Delete the app and that folder to remove everything.

Updates are manual for now: download the new release and replace the app. Drawer is signed with a fixed identity, so
macOS should keep the permissions you granted.

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
./build.sh dev         # fast debug build and launch, for trying changes
./build.sh zip         # build and write build/Drawer.zip and its SHA-256 for sharing
./build.sh dmg         # build and write build/Drawer.dmg and its SHA-256 for sharing
```

The first launch opens a short welcome.

### Signing

By default the app is signed ad-hoc with a fixed designated requirement
(`identifier "com.studioab.drawer"`), so macOS keeps the Accessibility permission across rebuilds.
To sign with a real certificate instead:

```bash
security find-identity -v -p codesigning
DRAWER_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh install
```

### First launch

A short welcome explains how Drawer works and asks for the one permission it needs. You can change everything later in Settings.

<p align="center">
  <img src="docs/images/onboarding-1.png" width="24%" alt="Welcome">
  <img src="docs/images/onboarding-2.png" width="24%" alt="How Drawer works">
  <img src="docs/images/onboarding-3.png" width="24%" alt="Quick start">
  <img src="docs/images/onboarding-4.png" width="24%" alt="Paste to any app">
</p>

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
make-icon.swift       draws the app icon
Drawer.sdef           the AppleScript dictionary
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

## FAQ

**Is it free?** Yes. It is open source under the MIT licence.

**Does it send my clipboard anywhere?** No. There are no accounts and no analytics. See [Privacy](#privacy).

**Why does macOS warn me when I open it?** The app is not notarized yet. See [Why macOS shows a warning](#why-macos-shows-a-warning); it explains the steps and how to check the download.

**Where is my history stored?** As plain Markdown files, in `~/Library/Application Support/Drawer/` or the iCloud Drive folder you pick. See [Data](#data).

**How do I use it on two Macs?** Turn on iCloud Drive in Settings. Notes, Quick Access and clipboard history then sync through the folders themselves.

**How do I remove it?** Delete Drawer from Applications, then delete `~/Library/Application Support/Drawer` (and the iCloud Drive `Drawer` folder if you used it).

**I found a bug or have an idea.** Open an [issue](../../issues) or use *Settings › General › About*.

## Roadmap

The full plan, with the reasoning, is in [ROADMAP.md](ROADMAP.md); what is left before a public release is in
[RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md). In short:

**Now:** make the core trustworthy (capture hardening, speed at any history size, tests, a refactor) and add keyboard
navigation in the drawer.

**Next:** plain-text paste, search by app and date with text recognition in screenshots, pinboards, paste stack, a few
text transforms, per-app rules, export, and a URL scheme for Shortcuts and Raycast.

**Later:** an iPhone and iPad companion, shared pinboards, notarized release with auto-update.

**Not doing:** accounts, cloud AI, or anything that sends clipboard content off your Mac.

## Credits

Inspired by Unclutter and Paste. Built with Swift, AppKit and SwiftUI.

## Author

Andikan Bassey · [contact@andikanbassey.com](mailto:contact@andikanbassey.com)

## License

[MIT](LICENSE) © 2026 Andikan Bassey
