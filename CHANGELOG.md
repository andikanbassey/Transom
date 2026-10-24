# Changelog

Each release is written as what you can now do.

## Unreleased

**Changed**
- **"Keep history for" now really removes old items, with a safety net.** Items past the period used to be hidden but stayed in your month files, so they were loaded again at every launch. They now leave the history (and your other Macs, through iCloud) and move to an archive on this Mac, with their pictures. The archive is emptied after 90 days. Pinned items and "Forever" are unchanged. Clear Unpinned, Erase History and deleting items still delete at once.
- **Restore removed items.** Settings › Clipboard › Keep history has a Restore menu: bring back what was removed in the past hour, today, this week, this month or the whole 90 days, with a count for each. Restored items keep their original date and are not expired again straight away.

**Faster**
- **Opening with a long history is faster.** Clearing, trimming and deleting many items at once no longer copies the whole history for each item: with 20,000 items Transom's start-up work dropped from 14 s of CPU to under 4 s.
- **A long history no longer weighs the drawer down.** The drawer draws the newest 200 items plus everything pinned, and ends with a "Show older" button for the next batch. With 20,000 items over a year, Transom's memory dropped from 94 MB to 47 MB. Searching and filters still look through the whole history.

## 0.7.1 (2026-10-22): sensitive items, scoped clearing, time sections

**New**
- **The clipboard strip is grouped by age.** Cards are split into Pinned, Past Hour, Today, Yesterday, This Week, This Month and Older, each with a caption and a gap, so a long history is easy to scan. Empty groups do not show. The time filter still narrows the list as before.
- **Clear Unpinned follows your filters.** With an app chosen in the app filter, right-click the filter pills (or open the ⋯ menu) and choose "Clear Unpinned from Claude (3)…": only that app's unpinned items go, after a confirmation with the count. The type and time filters count too, so you only ever clear what you can see. With no filter it clears every unpinned item, as before. Pinned items always stay.
- **Mark as Sensitive.** Right-click any item (text, link, picture or file) to mask it: the picture or text is replaced by a field of block characters that scrambles when the pointer is over it, and the card says "Sensitive link", "Sensitive image" and so on. It is removed from your history files (and, through iCloud, from your other Macs), kept in memory only and pasted exactly as copied. "Not Sensitive" puts it back.
- **A countdown on sensitive items.** Every sensitive item, marked by you or found automatically, shows a ring and the time left (15 minutes). In the last 30 seconds the characters drop away one by one and the card fades, and at zero it is gone.

**Fixed**
- The daily update check no longer uses up its day when it fails (you were offline, or GitHub did not answer): it tries again within the hour.

## 0.7 (2026-10-17): Drawer is now Transom

**The new name**
- ✨ **Drawer is now Transom.** A transom is the small window above a door, hinged at the top so you can open it a little and see through without opening the door. That is how the app opens at the top of your screen. The drawer icon stays as it was.
- Your **history, notes, Quick Access files and settings are unchanged.** The first time Transom starts it moves `Application Support/Drawer` to `Application Support/Transom` before anything reads it, and says so once. Folders you pointed at iCloud Drive keep their paths.
- The **bundle identifier is unchanged** (`com.studioab.drawer`), so macOS keeps your Accessibility permission, the Open at login item and your preferences. Drag Transom into Applications over, or next to, Drawer and quit Drawer; if both run, Transom asks which to keep.

**For scripts and tools**
- `transom://` links are the new form; **`drawer://` still works** and will for a few releases.
- **AppleScript:** the app is now named Transom, so `tell application "Drawer"` no longer finds it. Change it to `tell application "Transom"`, and `open drawer` to `open transom`. The other commands are unchanged.
- Test and debug switches are now `TRANSOM_*` (`TRANSOM_SUPPORT_DIR`, `TRANSOM_SNAPSHOT` and so on); the old `DRAWER_*` names are still read.
- The download is `Transom.dmg` (and `Transom.zip`) and the app inside is `Transom.app`.

**Library**
- Every Library page now explains itself when it is empty and offers the one action that fills it: **Add Files…** on Quick Access (you can also drop files from Finder onto the page), **New Note** on Notes, a pointer to the Clipboard page when nothing is pinned, and **Clear filters** when filters hide everything.
- Long lists are paged, 48 items at a time, with Previous and Next and "49–96 of 213" under the list. Select still picks across all pages.
- The Library no longer lists the blank note that is kept ready for typing.

**Updates**
- ✨ Transom now **checks for updates** (about once a day, switchable in Settings › General) and can **install them for you**: it downloads the release from GitHub, verifies its checksum, swaps the app and reopens. A new version shows in the menu bar menu and under Settings › General › About › Updates.

**Privacy**
- ✨ **Sensitive items stay hidden.** A password copied from a password manager, or a secret key (API token, private key), now appears in the Clipboard as a masked item: scrambled characters that animate when you point at them, with a lock and "Sensitive" instead of the text. You can still copy or paste it. It is kept in memory only, never written to disk or synced, can't be pinned, saved to Notes or Quick Access, or found by search, and is removed after 15 minutes. Settings › Privacy has a switch; off, such items are skipped as before.

**Fixed**
- Saving the clipboard history could delete the month's file instead of rewriting it when the Clipboard folder was reached through a symbolic link (for example a folder under `/tmp`). The history is now always written safely.

**Accessibility**
- ✨ **VoiceOver** can now find and press the clickable parts of Transom: the Library sidebar and Library | Settings switch, the round "+" button, cards and rows, the pin and delete buttons, the header icons, search, and the page controls. Icon-only controls have labels, and selected items are announced.

**Under the hood**
- Unit tests for the Markdown history format, version comparison, secret detection and folder paths run in CI.
- The updater's test switches are only read by debug builds.

**Good to know**
- SHA-256 of `Transom.dmg`: `a6fe8863a45dd7911a39c4d3ff7634bec94b14f681df1e8616f1e632c9fa346c`
- Not notarized yet, so macOS asks you to confirm opening it the first time. See [Install](README.md#install).
- Coming from Drawer: quit Drawer, drag Transom into Applications (it can replace Drawer.app) and open it. Your data moves across by itself.

## 0.6 (2026-10-15)

**Clipboard**
- ✨ Filter by **time, type and app** from three dropdowns, in the drawer and in the Library. The app menu lists the apps in your history, with their icons.
- ✨ **Drag an item** onto Quick Access to keep it, or onto Notes to turn it into a note. Pictures are embedded in the note.
- Copy the same picture again and it moves to the top instead of being stored twice.
- Link cover images stay on your Mac instead of syncing through iCloud, and a link copied on another Mac gets its cover fetched again.

**Library**
- ✨ **Select** several items to pin or delete them together. Pick all, the last 5 minutes, the last hour or today, and a confirmation protects you from deleting by accident.
- Library and Settings are one window with a switch at the bottom of the sidebar. Settings has a new **About** section: what Drawer is, the GitHub link, privacy, the licence and credits.
- Tidier headers: Select and search sit with the filters, at one height. The Theme setting (system, dark, light) now applies as soon as you change it.

**Drawer**
- ✨ **Scroll down anywhere on the menu bar** to open the drawer, not only at the very top edge (Settings › Shortcuts can limit it to the edge).
- With the clipboard shown as a list, the three panels are equal width.
- A cleaner clipboard header: filters in the middle, search first on the right, pause beside it.
- Clicking the x on a note asks before it deletes.
- The welcome screen is easier to read, with shorter copy.

**Fixed**
- Drawer no longer fails to start (no menu bar icon) when iCloud has moved the clipboard history off your Mac. History loads in the background.
- A screenshot saved from a tool that leaves its file in a temporary folder is kept properly in Notes and Quick Access.
- Opening a second copy of Drawer asks which one to keep, so both don't capture.

**Good to know**
- SHA-256 of `Drawer.dmg`: `bf0f0170b472e96f6b43e010128142f669651ecf1d7a9759ee78068ef598c40a`
- Not notarized yet, so macOS asks you to confirm opening it the first time. See [Install](README.md#install).

## 0.5.1 (2026-10-13)

**Fixed**
- Pasting an image from the drawer no longer creates a huge uncompressed `.tiff` (a 2 MB screenshot became about 27 MB in
  Finder). It now pastes the same PNG you copied.

**Good to know**
- SHA-256 of `Drawer.dmg`: `ad60c19de49b0d23ba89f71a386482d9d89e0f5f21cb92c385a664df0cac71d4`
- Not notarized yet, so macOS asks you to confirm opening it the first time. See [Install](README.md#install).

## 0.5 (2026-10-13)

The first public release. Drawer is a clipboard manager that lives at the top of your screen.

**Clipboard**
- ✨ Scroll at the top edge of the screen, or press ⇧⌘V, and everything you copied slides down as cards with real previews.
- Click an item to paste it into the app you were using. ⌘1–⌘9 paste the first nine.
- Pin what you want to keep; filter by type (text, links, images, colours, video, files); search the lot.
- ✨ Use it from the keyboard: arrows to move, Return to paste, ⌥Return for plain text, Space to preview, just start typing to search.
- Drag any item out into another app.
- Keep history for a day, a week, a month, a year or forever. There is no item limit.
- Passwords and one-time items that apps mark as private are skipped. Choose which apps Drawer records from.

**Library window**
- ✨ Open the Library from the menu bar to browse everything in a bigger window: clipboard, pinned, notes and Quick Access, with search (⌘K) scoped to the page you are on.
- Switch between cards and lists, for everything or per kind.

**Notes**
- Write notes as plain Markdown files in a folder you choose. The Library editor formats as you type and has a toolbar for headings, bold, italic, lists, checklists, quotes, links and code.
- Right-click a note to copy it as text, Markdown or rich text, duplicate it, or export it as Markdown, text, RTF or PDF.

**Quick Access**
- Pin files and folders for one-click access, with real previews. Drag them back out to any app.

**Sync**
- ✨ Turn on iCloud and notes, Quick Access and clipboard history stay in step across your Macs, both ways. Deleting something on one Mac removes it on the others.

**Automation**
- ✨ Control Drawer from Raycast, Alfred, Shortcuts-style scripts or the Terminal with `drawer://` links and AppleScript. Off by default; copying and pasting for another app needs a trusted app.

**Reliability and privacy**
- Very large copies (over 5 MB of text or 60 MB of image) are skipped instead of slowing everything down.
- A capture log in Settings › Advanced shows what Drawer saw and why something was or was not saved.
- Nothing leaves your Mac. No accounts, no analytics.

**Good to know**
- This build is not notarized yet, so macOS asks you to confirm opening it the first time. See [Install](README.md#install).
- SHA-256 of `Drawer.dmg`: `a2b0d4ae6b3683066afdd02030eed8457006f92e55e7357c121fc0a398403e4a`
