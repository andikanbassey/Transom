# Contributing

Thanks for taking a look. Transom is a small, focused app, and small, focused changes are easiest to review.

## Ideas and bugs

- **A bug:** [open an issue](../../issues/new/choose) with the steps, your Transom and macOS versions, and what you expected.
- **An idea:** start a [discussion](../../discussions/categories/ideas), or file a feature request if it is small and concrete.
  The [roadmap](ROADMAP.md) lists what is planned and what is not.

## Building

Only the Xcode Command Line Tools are needed.

```bash
./build.sh            # build/Transom.app
./build.sh dev        # fast debug build, then launch (for trying changes)
```

Try changes without touching your real history, notes or settings by pointing the app at a scratch folder:

```bash
TRANSOM_SUPPORT_DIR=/tmp/transom-test build/Transom.app/Contents/MacOS/Transom
```

`CLAUDE.md` has the rest: how to render the UI offscreen for review, the code layout, and the decisions to keep (no
dependencies, native controls, one shared look for the Library and Settings).

## Pull requests

- Keep one change per pull request and say what you checked and what you could not.
- Match the surrounding code: its naming, its comment density, its idiom.
- Check the UI with an offscreen render before and after (`TRANSOM_SNAPSHOT_VIEW`, see `CLAUDE.md`).
- Update the changelog for anything people will notice.

## Releases

See [docs/releasing.md](docs/releasing.md).
