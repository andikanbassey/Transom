# Changelog

Each release is written as what you can now do.

## 0.5 (draft, not released)

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
- SHA-256 of `Drawer.dmg`: *(paste here when the release is built)*
