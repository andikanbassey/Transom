# Security

## Reporting a problem

If you find a security problem in Transom, please report it privately instead of opening a public issue:

1. Go to the [Security tab](https://github.com/andikanbassey/Transom/security) of this repository.
2. Choose **Report a vulnerability** and describe what you found.

Please include the Transom version (Settings › General › About), your macOS version, and the steps to reproduce it. Do not include
real passwords or other private clipboard content in a report.

This is a free project maintained by one person. Reports are read and answered as quickly as possible, with no guaranteed response
time. You will be told what is decided, and credited in the changelog if you want to be.

## What matters most here

Transom reads the clipboard, so these are the areas worth a close look:

- **Sensitive items.** Passwords and secret keys are masked, kept in memory only and expired after 15 minutes. Anything that
  displays, saves, searches or exports them in the clear is a bug.
- **The updater.** It downloads the release DMG from GitHub, checks its SHA-256 and signature, then replaces the app. A way to
  make it install something else is a bug.
- **Links and AppleScript.** `transom://` links and AppleScript are off by default. Copying or pasting for another app needs a
  trusted app, and clipboard content is only ever read out through AppleScript, never through a link.
- **Files on disk.** History, notes and settings are plain files in `~/Library/Application Support/Transom/` or the folders you
  choose, including iCloud Drive.

## Supported versions

Only the latest release is supported. Update from Settings › General › About, or download it from the
[releases page](https://github.com/andikanbassey/Transom/releases/latest).
