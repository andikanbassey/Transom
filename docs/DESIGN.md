# Design and storage

How Transom looks and behaves, and how it stores your data. Names, colours and the icon are in
[BRANDING.md](../BRANDING.md).

## Design

- **Layout.** Three equal columns in the drawer: Quick Access, Clipboard and Notes. The layout is inspired by Unclutter and
  the feature set by Paste; Transom copies neither one for one.
- **Feel.** Premium and calm: generous spacing, clear hierarchy, Liquid Glass on macOS 26 and later (a blurred material
  before that) and native macOS controls. Custom switches were tried and rejected.
- **Clipboard rows.** Cover image on the left, name in the middle, a coloured type pill under the name.
  Images, GIFs, videos and PDFs show a real preview, files and folders their icon, hex codes a swatch, and text, links and
  audio a tinted symbol. Links show the page title and image. A name is the file name, the first two lines of text, or the
  domain and path.
- **Grouping.** Pinned, then each named group of pins, then Past Hour, Today, Yesterday, This Week, This Month, Older.
- **Selecting.** In the drawer, a card's type symbol turns into a circle on hover. Clicking it, or ⌘- or ⇧-clicking a card, starts
  select mode: the header becomes the selection bar, a click adds an item, ⇧-click adds a run, and a drag across cards picks
  everything it passes. Right-clicking one of several picked items acts on all of them. Confirmations appear at the bottom
  of the panel, not as alerts, so the drawer stays open.
- **Controls.** Each panel has a "⋯" menu for its own options and the right-most panel carries the settings gear.
  Right-clicking anywhere on Transom opens the app menu.
- **Closing.** Transom closes on a click outside, Esc, or a swipe up at the top; optional auto-close after 5, 10 or 15 seconds.
- **Scrolling.** Mouse and trackpad scroll direction are inverted separately (a trackpad is recognised by the gesture
  phase). A swipe up closes Transom anywhere, unless the list under the pointer can still scroll up.
- **Library.** One window holds the Library and Settings, switched by the pill at the bottom of the sidebar. Every Library
  page shares one header: heading, then the page's filters, Select and Search on one row. Long lists are paged, and empty
  pages say what belongs there and offer the one action that fills them.
- **Clicking an item** can paste it, only copy it, or open it in full (Settings › Clipboard).

## Storage

- **Clipboard history** is one Markdown file per month (`Clipboard/2026-10.md`), a section per day and one entry per copy
  between `<!-- drawer:clip {json} -->` markers. The marker keeps its original spelling so older history stays readable.
  Formatted text is stored as Markdown and pasted back with its styling. A pinned item's group is stored as `group` in the same JSON (only for pins). Pictures with no source file go in
  `Clipboard/Images/`; copied files stay as pointers. There is no item cap: time is the only limit.
- **Retention** moves items older than the chosen period to `Application Support/Transom/ClipboardArchive` (one `archived-<day>-<hour>.md` per hour, pictures in `Images`), on this Mac only, and deletes that archive after 90 days (`ClipboardArchive`). Settings › Clipboard › Restore brings a time range back.
- **Deletions** are remembered in `deleted.txt` so a delete on one Mac is not undone by another Mac's copy of the file.
- **Notes** are Markdown files in a folder. **Quick Access** files are references or copies in a folder.
- **Sync** works by pointing those folders at iCloud Drive; the newest change per item wins. Link cover images stay on
  your Mac. With "Keep pictures on this Mac" on, copied pictures do too.
- **Where.** `~/Library/Application Support/Transom/` unless you choose other folders in Settings.
- **Loading.** Memory holds every pin and the newest 200 unpinned items. Show older reads another batch; search, filters and the Library read the rest, and it is let go when they close. Items past the retention period are read from any month so they can be archived.
- **Index.** `Application Support/Transom/clipboard-index.json` caches each month file's item ids, dates, pins, source apps and short content hashes, so unchanged months need not be read. It holds no clipboard text, stays on this Mac, and is rebuilt if deleted. Erase History deletes it.
- **Sensitive items** (concealed pasteboard types from password managers, and text that looks like a secret key) are the exception to all of this: they live in memory only, are never written to the history files, are masked everywhere they are shown, and expire after 15 minutes.
- **Rich text** is kept as Markdown (bold, italic, strikethrough, code, links); lists and headings are not kept yet.
