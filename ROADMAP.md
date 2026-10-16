# Roadmap

Transom is a clipboard manager first. Everything here is judged against one question: does it make copying and pasting
faster or more reliable? Anything that adds latency, bloat or a network dependency waits, or does not happen.

This is a plan, not a promise. Priorities move with what people actually use. To influence it, open a
[discussion](../../discussions/categories/ideas) or an [issue](../../issues/new/choose).

## Principles

- **Fast and light.** Opening Transom feels instant. Idle CPU and memory stay near zero. No web view, no dependencies.
- **Your data stays yours.** Plain Markdown files in a folder you choose, no account, and nothing leaves your Mac except
  iCloud Drive sync and link previews, both of which you can switch off.
- **Reliable before clever.** A missed copy or a lost item is worse than a missing feature.
- **Simple by default.** New abilities are options that stay out of the way until you turn them on.
- **No AI features for now.** On-device suggestions may come later, but only as an optional, off-by-default extra that
  does not slow anything down.

## Now: make the core trustworthy

- **Capture hardening.** Limit the size of a stored item, skip pathological pasteboards, never block the main thread while saving.
- **Fast at any history size.** Read recent months at launch and older months only when searched or scrolled to, so memory
  stays flat even with history kept forever.
- **Tests** for the parts that must not break: the Markdown history format, two-way sync merge and deletions.
- **A cleaner codebase.** Split the largest view file into one file per area and keep sizes and colours in one place.
- **Keyboard navigation.** Arrow keys to move, Return to paste, ⌘F to search, Space for a preview.
- **Live-checked behaviour.** Scroll-to-open and swipe-to-close on trackpads and mice, haptics, and Transom in front of
  full-screen apps, checked on real hardware and more than one macOS version.

## Next: small features that earn their place

- **Plain-text paste**, with a modifier key while choosing an item and an "always plain text" option.
- **Better search.** Filter by app and date as well as type, and optionally find text inside screenshots using on-device
  recognition. Recognition runs in the background, can be paused or turned off, and Settings will say what it costs.
- **Pinboards.** Split Pinned into named groups (replies, code, addresses) with a quiet board switcher.
- **Paste stack.** Collect several items, then paste them one after another, with a clear indicator while it is active.
- **A few text transforms on paste.** Trim, change case, strip formatting, join lines: instant and deterministic.
- **Sensitive-item handling.** Blur previews of items that look like secrets and expire one-time codes after a few minutes.
- **Per-app rules.** One place to record or hide, paste plain or formatted, and auto-delete after a day, per app.
- **Export and import** of your history as a zip of Markdown files.
- **Shortcuts and launcher integration** on top of the existing `transom://` links and AppleScript.

## Later

- **Notarized releases** with automatic updates that need no confirmation dialog on first launch.
- **iPhone and iPad companion** that reads the same iCloud Markdown history.
- **Shared pinboards** for teams.
- **Universal Clipboard awareness**, showing what you copied on your iPhone.
- **Optional on-device suggestions**, only if they can be instant and stay off by default.

## Not planned

- Accounts, or any cloud service run by the project.
- Cloud AI features, or anything that sends clipboard content off your Mac.
- Heavy analytics. If usage is ever measured, it will be minimal, anonymous and opt-out, and it will be disclosed in the app.

## Automation, as built

Transom can be driven from other apps through `transom://` links and AppleScript. The rules: it is off by default;
links that only change Transom work once automation is on; copying or pasting for another app needs a trusted app;
and clipboard content can be read out only through AppleScript, never through a link. See the README for the commands.
