<p align="center">
  <img src="docs/icon.png" width="128" alt="Magpie icon">
</p>

<h1 align="center">Magpie</h1>

<p align="center">
  <b>Save anything. Actually come back to it.</b><br>
  A macOS app for links, images, videos, notes and files, instead of bookmark folders.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26+">
  <img src="https://img.shields.io/badge/status-early-orange" alt="Early">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
</p>

---

## Why

Browser bookmarks pile up in folders like "watch later" and "ideas" and never get opened again.
Magpie turns each save into a **Block** with a picture, keeps it in collections you can see,
and then nudges you to read, watch and use what you saved.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="800" alt="Magpie's Gallery: image-first cards for links, videos, places, notes and checklists, with pinned collections in the top bar">
  </picture>
</p>

## Features

- **Save anything.** Paste, drop or add links, images, videos, files, notes and checklists. Links get their title, picture and site name on their own, and videos, products and places show their length, price or a map
- **Quick Save** (⌃⌥Space, anywhere) saves Safari's front tab or the clipboard without leaving what you're doing. You can also drop things onto the Dock icon, or turn a screenshot into a Block (⌃⌥S)
- **Gallery and Journal.** See image-first cards, each tinted with its picture's color, or a dense list. Sort by newest, quickest, title, site, color, shuffle or your own order
- **Collections and tags.** Nest collections, pin up to 5 to the top bar, and tag across them
- **Sort Inbox.** Go through new saves one at a time from the keyboard, with a suggested collection. Reaching Inbox zero keeps a daily streak
- **Lucky Dip.** Can't decide what to read or watch? Pick a pile and how much time you have, and Magpie picks one. You get two re-spins a day, then you commit
- **Rediscover.** Five old saves a day to keep or archive. Collections like Watch later can expire their Blocks, so they empty themselves
- **Search everything,** including the text inside your images
- **Import your bookmarks** from Safari, Chrome or Firefox, with folders becoming collections
- Dark by default, with Light or Match my Mac. Every action has a keyboard shortcut
- Local and private. Everything stays on your Mac, with no account and no server
- **Update checks** through GitHub, with your permission and a switch to turn them off
- Never locked in: File → Export Library writes everything to plain files (JSON, pictures, and a bookmarks file any browser imports)

Coming next: an iPhone app with iCloud sync, and saving from the Share menu. See the [roadmap](ROADMAP.md).

## Install

Magpie needs macOS 26 (Tahoe) or later. With [Homebrew](https://brew.sh):

```sh
brew install --cask jleitaom/tap/magpie
```

Or download `Magpie-x.y.z.dmg` from the [latest release](https://github.com/jleitaom/magpie/releases/latest)
and drag **Magpie** into **Applications**. The first time you open it, macOS will say it can't verify
the app. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only
need to do this once.

Magpie checks for updates through GitHub, after asking you first. Updates keep the access you gave
Quick Save (Safari) and screenshots (Screen Recording): every release is signed with the same
certificate, so macOS recognizes the new version as the same app.

### Why the warning?

Magpie is free and isn't distributed through Apple's paid developer program, so macOS can't vouch
for it. Instead, every release is built in public by GitHub Actions from the source in this repo,
and you can check that your download matches:

```sh
gh attestation verify Magpie-1.0.0.dmg --repo jleitaom/magpie
```

See [SECURITY.md](SECURITY.md) for details, or build it yourself (below).

## Build from source

Building needs Xcode 26 (Swift 6.2) or the matching Swift toolchain.

```sh
git clone https://github.com/jleitaom/magpie.git
cd magpie
./build.sh --install    # builds, copies to /Applications and launches
```

Your builds are ad hoc signed, so macOS treats each rebuild as a new app and asks again for Safari
and Screen Recording access. To avoid that, create a self-signed code signing certificate named
`Magpie Self-Signed` in Keychain Access (Certificate Assistant → Create a Certificate, type Code
Signing); `build.sh` uses it automatically.

To try it with sample data without touching your library:

```sh
open --env APP_STORE=/tmp/Magpie-demo.store --env APP_SEED=1 /Applications/Magpie.app
```

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and
[CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## License

[MIT](LICENSE) © José Leitão

Magpie is an independent project and is not affiliated with Apple. macOS is a trademark of Apple Inc.
