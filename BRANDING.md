# Transom branding

The one reference for how Transom looks and is named, and the checklists for changing any of it. The app was called Drawer until 0.7.

## Identity

| | |
|---|---|
| Name | Transom |
| Bundle id | `com.studioab.drawer`, **kept on purpose** from the Drawer days: changing it would reset the Accessibility grant, the login item and the preferences, and users never see it |
| Link scheme | `transom://` (`drawer://` still works as an alias for a few releases) |
| Data folder | `Application Support/Transom`. A folder named `Drawer` is moved there on first launch (`LegacyData.swift`). `TRANSOM_SUPPORT_DIR` points a test run at another folder |
| Environment variables | `TRANSOM_*`; the old `DRAWER_*` names are still read as a fallback (`Env.swift`) |
| App icon | Slate tile, a frosted drawer pulled open with a page, a picture and a link sticking out (kept from the Drawer days) |
| Menu bar | The drawer glyph: a screen edge with a drawer pulled down (a template image, tinted by macOS) |
| Sidebar | "Transom" and the app icon |
| Settings › General › About | Version, GitHub link, licence, credits |
| Status menu header | "Transom 0.6.0" (or "waiting, not capturing" in standby) |

A Beta channel existed for a while (its own bundle id, data folder and amber icon) and was dropped. It is in the git
history if it is ever wanted again; a test build can use a scratch data folder instead.

## Colour

| Token | Value | Used for |
|---|---|---|
| Tile, top | `#3A4156` (0.227, 0.255, 0.337) | Icon background gradient start |
| Tile, bottom | `#12141F` (0.071, 0.078, 0.122) | Icon background gradient end |
| Interior | `#171A29` | The inside of the drawer, behind the items |
| Drawer front | white to `#E6EBF5` | Frosted front with a rim and a shadow |
| Items | page white, sky `#73C7FF` to `#FFD19E`, hill `#338C66`, link `#4285F5` | The three things sticking out of the drawer |

The app itself follows the system accent colour; the icon is the only fixed brand colour.

## Icon

Drawn by `make-icon.swift` (Command Line Tools only) into `AppIcon.icns`; `build.sh` draws it when the `.icns` is missing, so
delete the file to regenerate after editing the script. (A layered Icon Composer version was built and dropped because it
needs Xcode; it is in git history, commit "New app icon as Icon Composer files".)

- **Design:** a drawer pulled open, a frosted front with a pull slot, three kinds of item inside: a page of text, a picture
  and a link. The icon kept the drawer when the app was renamed Transom: a window-with-glass-pane version (direction C in
  the design notes from the rename) was built and set aside; it is in git history (commit "New icon and menu bar glyph for Transom").
- **Wordmark:** "Transom" in SF Pro Display Semibold with tight tracking. (A mark with the "o" as a small window was sketched in
  the design notes from the rename; not built.)
- **Tile:** 824 of 1024 px, centred, corner radius 185, a soft shadow, a gradient top to bottom.
- **Sizes:** 16, 32, 128, 256, 512, each at 1x and 2x.
- The menu bar icon is separate (`MenuBarIcon` in `Theme.swift`).

## Names and wording

- The product is "Transom". Say "Library" and "Quick Access" for those things everywhere.
- Dialogs name the app explicitly ("Another copy of Transom is already running"), never "the other app".
- **Voice:** calm and short. Light and glass words (pane, bar, open, lit) over storage words (box, bin, vault). Never "stash" or "hoard".
- **Origin, said once in the welcome flow, once in Settings › General › About and here:** a transom is the small window above a
  door. It is hinged at the top, so you can open it a little and see through without opening the door. The app behaves the same
  way: it opens a little at the top edge of the screen to show what you have kept, without making you leave what you are doing.
- **Pitch lines:** *Everything within reach, just above the frame.* · *A window onto what you've kept.* · *Copy once. Find it again.*

## Two copies running

Two copies of Transom (one in Applications and one elsewhere, say) watch the same global shortcut, screen edge and clipboard.
When a second one starts it asks:

| Choice | Result |
|---|---|
| Use Transom | The other copy quits; this one carries on |
| Quit This One | This copy quits |
| Keep Both | This copy waits in standby |

Standby: no clipboard capture, no shortcut, no edge swipe, a dimmed menu bar icon, a status menu header that says "waiting,
not capturing", and "Make Transom the Active Copy". It becomes active by itself when the other copy quits.

## Where it lives in the code

| What | File |
|---|---|
| Name, version, repo link, copyright | `Sources/Transom/Brand.swift` |
| Data folder (`supportDir`) | `Sources/Transom/Stores.swift` |
| Two-copies prompt and standby | `Sources/Transom/InstanceGuard.swift`, `AppModel.standby` |
| Menu bar icon, status menu header | `Sources/Transom/main.swift`, `Theme.swift` (`MenuBarIcon`) |
| Sidebar brand | `Theme.swift` (`SidebarBrand`) |
| Data move from the old name, one-time notice | `Sources/Transom/LegacyData.swift` |
| Environment variables | `Sources/Transom/Env.swift` |
| About section | `Sources/Transom/SettingsView.swift` (General) |
| Bundle id, scheme, name, icon | `build.sh` |
| Icon drawing | `make-icon.swift` (`AppIcon.icns`) |

## Checklist: change the icon

- [ ] Edit `make-icon.swift` and the colour table above together.
- [ ] Delete `AppIcon.icns`, then `./build.sh` to regenerate it.
- [ ] Look at it at 1024, 128 and 32 px: glyph still readable.
- [ ] Reinstall and, if the Dock still shows the old icon, `killall Dock`.
- [ ] Screenshots in the README and release notes updated.

## Checklist: before a release

- [ ] Built with plain `./build.sh` (not `dev`): icon, name "Transom", version right.
- [ ] Version in `build.sh` (`CFBundleShortVersionString`, `CFBundleVersion`) and `CHANGELOG.md` agree.
- [ ] DMG volume name "Transom"; the file inside is `Transom.app`.
- [ ] Tried on a Mac or account that has never run Transom: first launch, welcome flow and the unsigned-app steps work.
