# Contributing to Magpie

Thanks for helping out!

## Development

```sh
./build.sh --install
```

- Source lives in `Sources/Magpie/`, grouped by area:
  - `App/`: startup and the menu bar commands (`MagpieApp.swift`), and every action the app
    can take, such as saving, moving, deleting and pinning (`AppModel.swift`)
  - `Library/`: the SwiftData models (`Models.swift`) and the link preview fetcher, which
    runs off the main thread (`Ingest.swift`)
  - `MainWindow/`: the window, its top bar, the drop target and the bottom hint (`MainView.swift`)
  - `Gallery/`: the masonry of cards (`GalleryView.swift`)
  - `Journal/`: the Journal, a numbered list of the same blocks (`JournalView.swift`). Sort
    orders are in `MagpieKit/BlockOrder.swift`
  - `SortInbox/`: Sort Inbox, one Inbox block at a time (`SortInboxView.swift`). The queue and the
    collection suggestion are in `MagpieKit/Sorting.swift`
  - `LuckyDip/`: Lucky Dip, one random pick from a pile (`LuckyDipView.swift`). Piles, the
    weighted pick, re-spins and the dip streak are in `MagpieKit/LuckyDip.swift`
  - `Rediscover/`: five old saves a day to keep or archive (`RediscoverView.swift`). The pick and
    the expiry rules are in `MagpieKit/Rediscover.swift`
  - `Tags/`: the tag editor in the details panel, the tag list in the Collections panel, and the
    tag menu and prompts (`TagViews.swift`). Name rules are in `MagpieKit/Tags.swift`
  - `Details/`: the panel that slides in for a selected Block (`DetailsPanel.swift`)
  - `Collections/`: the "N more" panel to find, pin and create collections (`CollectionsPopover.swift`)
  - `Settings/`: the Settings window (⌘,)
  - `DesignKit/`: Magpie's own look. Tokens, type, icons, parts (buttons, cards, controls, the
    top bar) and the window chrome
  - `Debug/`: the self-test, snapshot mode and sample data
- `Sources/MagpieKit/` holds the rules with no UI (link parsing and normalizing, masonry math,
  color math, the collection tree, the Sort Inbox queue and suggestions, the Inbox zero streak, piles and Lucky Dip, and `PageReader`, which reads video length, price, recipes and read time from a page's HTML), so they can be unit tested. Put new logic there, not in the views.
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
never touch your real library. Add a check to `Debug/SelfTest.swift` for every change with logic.

To try the app with sample data:

```sh
open --env APP_STORE=/tmp/Magpie-demo.store --env APP_SEED=1 build/Magpie.app
```

CI runs the build, the unit tests, the grid and design kit checks, the self-test and the
snapshots on every PR. Download the snapshots from the run's artifacts to review design changes.

## Pull requests

- Keep changes focused: one feature or fix per PR.
- Match the existing code style, and use the words the app uses (Block, Collection, Inbox,
  Lucky Dip…).
- Make sure `./build.sh` prints no warnings and every check above passes.
- Add a line to `CHANGELOG.md` under **Unreleased**.
