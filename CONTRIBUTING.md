# Contributing to Magpie

Thanks for helping out!

## Development

```sh
./build.sh --install
```

- Source lives in `Sources/Magpie/`, grouped by area:
  - `App/`: startup and the menu bar commands (`MagpieApp.swift`), every action the app
    can take, such as saving, moving, deleting and pinning (`AppModel.swift`), and update
    checks through Sparkle (`Updater.swift`)
  - `Library/`: the SwiftData models (`Models.swift`), the link preview fetcher, which
    runs off the main thread (`Ingest.swift`), and export and import of the whole library
    (`ExportImport.swift`; the file formats are in `MagpieKit/Export.swift`). A new model field
    must be added to the export too, or the round-trip check in the self-test fails
  - `MainWindow/`: the window, its top bar, the drop target and the bottom hint (`MainView.swift`),
    and the "Saved to Inbox" message shown after a drop on the Dock icon (`DropHUD.swift`)
  - `Gallery/`: the masonry of cards and the right-click menu every Block shares (`GalleryView.swift`),
    and dragging cards into your own order (`Reorder.swift`)
  - `Journal/`: the Journal, a numbered list of the same blocks (`JournalView.swift`). Sort
    orders are in `MagpieKit/BlockOrder.swift`
  - `SortInbox/`: Sort Inbox, one Inbox block at a time (`SortInboxView.swift`). The queue and the
    pile suggestion are in `MagpieKit/Sorting.swift`
  - `LuckyDip/`: Lucky Dip, one random pick from a pile or everything (`LuckyDipView.swift`).
    The weighted pick, re-spins, start verbs and the dip streak are in `MagpieKit/LuckyDip.swift`
  - `Rediscover/`: five old saves a day to keep or archive (`RediscoverView.swift`). The pick's rules
    are in `MagpieKit/Rediscover.swift`
  - `QuickSave/`: the global shortcut (`HotKey.swift`, Carbon, no permission needed) and the floating
    panel that saves the front browser tab (Safari, or Chrome, Arc, Brave, Edge and other
    Chromium browsers) or the clipboard (`QuickSave.swift`)
  - `Import/`: the bookmarks import sheet (`ImportSheet.swift`); the file format is read by
    `MagpieKit/Bookmarks.swift`
  - `Tags/`: the tag editor in the details panel, the tag list in the Piles panel, and the
    tag menu and prompts (`TagViews.swift`). Name rules are in `MagpieKit/Tags.swift`
  - `Details/`: the panel that slides in for a selected Block (`DetailsPanel.swift`), and the
    Choose Picture sheet (`PictureChooser.swift`; the page's pictures are found by `MagpieKit/PagePictures.swift`)
  - `Collections/`: the "N more" panel to find, pin and create piles (`CollectionsPopover.swift`)
  - `Settings/`: the Settings window (⌘,), with General and Shortcuts tabs (`SettingsView.swift`)
  - `DesignKit/`: Magpie's own look. Tokens, type, icons, parts (buttons, cards, controls, the
    top bar) and the window chrome
  - `Debug/`: the self-test, snapshot mode and sample data
- `Sources/MagpieKit/` holds the rules with no UI (link parsing and normalizing, masonry math,
  color math, the pile tree, the Sort Inbox queue and suggestions, Lucky Dip,
  sort orders, tags, search, Rediscover, the bookmarks file, the export format, and `PageReader`,
  which reads video length, price, recipes and read time from a page's HTML), so they can be unit tested. Put new logic there, not in the views.
- The app target builds in Swift 6 mode with the main actor as its default isolation. Mark slow
  work `nonisolated` and run it off the main thread, like the preview fetch in `Ingest.swift`.
- The data model follows CloudKit's rules so iCloud sync can be turned on later without a
  migration: every attribute optional or defaulted, every relationship optional with an
  inverse, no `@Attribute(.unique)` (duplicates are caught in code on `normalizedURL`), order
  in a `sortIndex: Double`, and images in `@Attribute(.externalStorage)`.
- The app icon is `Icon/AppIcon.icon`, an Icon Composer file. `build.sh` compiles it with
  `scripts/make-icon.sh` when it changes, and `scripts/icon-review.sh` renders it in every look.

## Design rules

Every screen is built from the kit in `Sources/Magpie/DesignKit/`.

- Colors: views use `Ink.*` only. Each token has a light and a dark value. Card backgrounds come
  from `Ink.card(tint:)`, which keeps 7:1 contrast (tested in `ColorMath`).
- Type: `.kitType(.role)`, never `.font(.system…)`. Icons: `KitIconView(icon:)`, never
  `systemName:` outside `DesignKit/`.
- Sizes: `Space.*` (a 4 pt grid) and `Metric.*`. A size off the grid becomes a named `Metric`.
- Motion: `Motion.*`, and nothing animates when Reduce Motion is on.
- Every action has a menu bar item and a keyboard shortcut.
- Dark is the default. Check every change in light **and** dark.

## Checks

```sh
swift test                               # unit tests for MagpieKit
scripts/selftest.sh                      # the app's real actions on a fresh store in /tmp
APP_SELFTEST_NETWORK=1 scripts/selftest.sh   # also fetches real link previews
scripts/snap.sh                          # every page in light and dark, in /tmp/Magpie-shots
scripts/grid-lint.sh                     # must print PASS
```

The self-test, snapshots and sample data refuse to run unless the store is in `/tmp`, so they
never touch your real library. A `/tmp` library also keeps its own sort and view choices. Add a check to `Debug/SelfTest.swift` for every change with logic.

To try the app with sample data:

```sh
open --env APP_STORE=/tmp/Magpie-demo.store --env APP_SEED=1 build/Magpie.app
```

CI runs the build, the unit tests, the grid and design kit checks, the self-test and the
snapshots on every PR. Download the snapshots from the run's artifacts to review design changes.

## Releases

- Push a tag like `v1.0.0` and `.github/workflows/release.yml` builds a universal app, signs it,
  packages `Magpie-1.0.0.dmg` and `.zip` (`scripts/package.sh`), and publishes a GitHub release
  with checksums and a build provenance attestation. Before tagging, move the **Unreleased**
  notes in `CHANGELOG.md` under the new version. Run the workflow by hand for a dry run.
- Releases are signed with the `Magpie Self-Signed` certificate (the `SIGNING_CERT_P12` and
  `SIGNING_CERT_PASSWORD` secrets), so updates keep the access people granted.
- Releases publish an `appcast.xml` (written by `scripts/appcast.sh`) that Sparkle reads from
  the latest release. It's signed with the EdDSA key in the `SPARKLE_PRIVATE_KEY` secret; the
  maintainer keeps a copy in the login keychain (`generate_keys --account magpie`). Without that
  key, existing installs can't be updated, so don't lose it.
- Releases also update the Homebrew cask in
  [jleitaom/homebrew-tap](https://github.com/jleitaom/homebrew-tap) (written by `scripts/cask.sh`),
  using a deploy key that can only write to that repo (the `TAP_DEPLOY_KEY` secret).
- Sparkle never starts with a test library (`APP_STORE`), so the self-test and snapshots stay offline.

## Pull requests

- Keep changes focused: one feature or fix per PR.
- Match the existing code style, and use the words the app uses (Block, Pile, Inbox,
  Lucky Dip…).
- Make sure `./build.sh` prints no warnings and every check above passes.
- Add a line to `CHANGELOG.md` under **Unreleased**.
