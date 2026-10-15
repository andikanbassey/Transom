# Changelog

Each release is written as what you can now do.

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
- SHA-256 of `Drawer.dmg`: `b8f72b28665a170a76108aa70dcf7b3563901650499e0010583b432bba6bc57a`
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
