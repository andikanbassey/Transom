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
- **Grouping.** Pinned, Past Hour, Today, Yesterday, This Week, This Month, Older.
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
  Formatted text is stored as Markdown and pasted back with its styling. Pictures with no source file go in
  `Clipboard/Images/`; copied files stay as pointers. There is no item cap: time is the only limit.
- **Retention** moves items older than the chosen period to `Application Support/Transom/ClipboardArchive` (one `archived-<day>.md` per day, pictures in `Images`), on this Mac only, and deletes that archive after 90 days (`ClipboardArchive`). To get an item back, copy its block into the matching month file in the Clipboard folder.
- **Deletions** are remembered in `deleted.txt` so a delete on one Mac is not undone by another Mac's copy of the file.
- **Notes** are Markdown files in a folder. **Quick Access** files are references or copies in a folder.
- **Sync** works by pointing those folders at iCloud Drive; the newest change per item wins. Link cover images stay on
  your Mac. With "Keep pictures on this Mac" on, copied pictures do too.
- **Where.** `~/Library/Application Support/Transom/` unless you choose other folders in Settings.
- **Sensitive items** (concealed pasteboard types from password managers, and text that looks like a secret key) are the exception to all of this: they live in memory only, are never written to the history files, are masked everywhere they are shown, and expire after 15 minutes.
- **Rich text** is kept as Markdown (bold, italic, strikethrough, code, links); lists and headings are not kept yet.
